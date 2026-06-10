import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Управляет записью голосовых сообщений.
///
/// Жизненный цикл:
/// 1. [startRecording] — начинает запись в tmp-файл (нативно) или blob (веб).
/// 2. [stopRecording]  — останавливает запись и возвращает путь + длительность.
/// 3. [cancelRecording] — останавливает и удаляет tmp-файл (свайп влево).
///
/// Формат вывода:
/// - Web              → WebM/Opus (.webm) — единственный гарантированный формат MediaRecorder API.
/// - Android / Linux  → Opus (.ogg) — нативная поддержка, хорошее сжатие.
/// - iOS / macOS / Windows → AAC (.m4a) — нативно, сервер принимает явно.
class AudioService {
  AudioService._();

  static final AudioService instance = AudioService._();

  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  String? _currentPath;
  DateTime? _startTime;

  StreamController<double>? _ampController;

  /// true, когда запись активна.
  bool get isRecording => _isRecording;

  /// Поток нормализованной амплитуды [0.0..1.0].
  Stream<double> get onAmplitude =>
      _ampController?.stream ?? const Stream.empty();

  // Кодек выбирается по платформе:
  //   Web    → Opus-in-WebM — единственный надёжный вариант через MediaRecorder API браузера.
  //   Linux  → Opus (.ogg)  — AAC не гарантирован в дистрибутивах Linux.
  //   Все остальные → AAC  (.m4a) — поддерживается ExoPlayer (Android) И
  //   AVFoundation (iOS/macOS), что обеспечивает кросс-платформенное
  //   воспроизведение между пользователями Android и iOS.
  static bool get _useOpus => !kIsWeb && Platform.isLinux;

  /// Начинает запись голосового сообщения.
  /// Бросает исключение если нет разрешения на микрофон или запись уже идёт.
  Future<void> startRecording() async {
    if (_isRecording) return;

    if (kIsWeb) {
      // На вебе hasPermission() возвращает false когда разрешение ещё в состоянии
      // 'prompt' (не запрашивалось) — не показывая диалог браузера совсем.
      // Поэтому на вебе пропускаем проверку: браузер сам покажет диалог при
      // вызове start(). Если пользователь ранее заблокировал микрофон —
      // start() выбросит исключение, которое поймает вызывающий код.
      final ts = DateTime.now().millisecondsSinceEpoch;
      _currentPath = 'voice_$ts.webm'; // путь на вебе игнорируется record-пакетом
      _startTime = DateTime.now();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 48000,
          numChannels: 1,
        ),
        path: _currentPath!,
      );
    } else {
      // Нативные платформы: явно проверяем разрешение перед записью.
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) throw Exception('Нет разрешения на микрофон');

      final dir = await getTemporaryDirectory();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final ext = _useOpus ? '.ogg' : '.m4a';
      _currentPath = '${dir.path}/voice_$ts$ext';
      _startTime   = DateTime.now();

      final config = _useOpus
          ? const RecordConfig(
              encoder:     AudioEncoder.opus,
              sampleRate:  16000,
              numChannels: 1,
            )
          : const RecordConfig(
              encoder:     AudioEncoder.aacLc,
              bitRate:     64000,
              sampleRate:  44100,
              numChannels: 1,
            );

      await _recorder.start(config, path: _currentPath!);
    }

    _isRecording = true;

    // Амплитудный поток — обновление каждые 100 мс
    _ampController = StreamController<double>.broadcast();
    _startAmplitudePolling();
  }

  void _startAmplitudePolling() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      try {
        final amp = await _recorder.getAmplitude();
        // amp.current в дБ (обычно от -160 до 0). Нормализуем в [0..1].
        final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        if (_ampController?.hasListener == true) {
          _ampController?.add(normalized);
        }
      } catch (_) {
        timer.cancel();
      }
    });
  }

  /// Останавливает запись и возвращает путь к файлу и длительность.
  /// Длительность измеряется таймером от старта до стопа.
  /// Возвращает null если запись не велась.
  ///
  /// На вебе [AudioRecorder.stop] возвращает blob URL вида
  /// `blob:https://...` — именно его мы передаём дальше как «путь»,
  /// чтобы [_uploadAudio] мог прочитать данные через HTTP-запрос к blob.
  Future<({String path, int durationMs})?> stopRecording() async {
    if (!_isRecording) return null;
    _isRecording = false;

    final durationMs =
        _startTime != null ? DateTime.now().difference(_startTime!).inMilliseconds : 0;

    // На вебе stop() возвращает blob URL; на нативных — тот же путь, что был передан в start().
    final stoppedPath = await _recorder.stop();
    await _ampController?.close();
    _ampController = null;

    // Используем blob URL (веб) или _currentPath (нативно).
    final path = (kIsWeb && stoppedPath != null) ? stoppedPath : _currentPath;
    _currentPath = null;
    _startTime   = null;

    if (path == null) return null;
    return (path: path, durationMs: durationMs.clamp(100, 3600000));
  }

  /// Отменяет запись и удаляет временный файл (свайп влево).
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    _isRecording = false;

    await _recorder.stop();
    await _ampController?.close();
    _ampController = null;

    final path = _currentPath;
    _currentPath = null;
    _startTime = null;

    // На вебе нет файловой системы — blob управляется браузером, удалять нечего.
    if (!kIsWeb && path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  /// Освобождает ресурсы.
  Future<void> dispose() async {
    await cancelRecording();
    _recorder.dispose();
  }
}
