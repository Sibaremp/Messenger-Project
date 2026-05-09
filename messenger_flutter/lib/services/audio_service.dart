import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Управляет записью голосовых сообщений.
///
/// Жизненный цикл:
/// 1. [startRecording] — начинает запись в tmp-файл.
/// 2. [stopRecording]  — останавливает запись и возвращает путь + длительность.
/// 3. [cancelRecording] — останавливает и удаляет tmp-файл (свайп влево).
///
/// Формат вывода:
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
  //   Linux  → Opus (.ogg)  — AAC не гарантирован в дистрибутивах Linux.
  //   Все остальные → AAC  (.m4a) — поддерживается ExoPlayer (Android) И
  //   AVFoundation (iOS/macOS), что обеспечивает кросс-платформенное
  //   воспроизведение между пользователями Android и iOS.
  static bool get _useOpus => !kIsWeb && Platform.isLinux;

  /// Начинает запись голосового сообщения.
  /// Бросает исключение если нет разрешения на микрофон или запись уже идёт.
  Future<void> startRecording() async {
    if (_isRecording) return;

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
  Future<({String path, int durationMs})?> stopRecording() async {
    if (!_isRecording) return null;
    _isRecording = false;

    final durationMs =
        _startTime != null ? DateTime.now().difference(_startTime!).inMilliseconds : 0;

    await _recorder.stop();
    await _ampController?.close();
    _ampController = null;

    final path = _currentPath;
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

    if (path != null) {
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
