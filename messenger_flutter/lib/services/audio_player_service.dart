import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';

/// Состояние воспроизведения одного трека.
class AudioPlayerState {
  final String id;
  final bool isPlaying;   // аудио реально играет (playing && processingState==ready)
  final Duration position;
  final Duration duration;
  final bool isLoading;   // загрузка / буферизация
  final bool hasError;

  const AudioPlayerState({
    required this.id,
    this.isPlaying = false,
    this.position  = Duration.zero,
    this.duration  = Duration.zero,
    this.isLoading = false,
    this.hasError  = false,
  });
}

/// Синглтон-сервис воспроизведения голосовых сообщений.
///
/// Гарантирует, что одновременно играет не более одного сообщения.
class AudioPlayerService {
  AudioPlayerService._();
  static final AudioPlayerService instance = AudioPlayerService._();

  AudioPlayer? _player;
  String?      _currentId;
  final List<StreamSubscription> _subs = [];

  // Кэш полей текущего состояния — формируют объект AudioPlayerState.
  bool     _isPlaying = false;
  bool     _isLoading = false;
  bool     _hasError  = false;
  Duration _position  = Duration.zero;
  Duration _duration  = Duration.zero;

  final _stateCtrl = StreamController<AudioPlayerState>.broadcast();
  Stream<AudioPlayerState> get stateStream => _stateCtrl.stream;
  String? get currentId => _currentId;

  // ── Публичные методы ──────────────────────────────────────────────────────

  Future<void> play(String id, String url) async {
    // Тот же трек и плеер жив в середине воспроизведения → просто возобновить.
    // При completed / idle создаём плеер заново — seek+play ненадёжен на ряде
    // платформ (idle не знает URL, completed может не принять seek).
    if (_currentId == id && _player != null) {
      final ps = _player!.processingState;
      if (ps == ProcessingState.loading ||
          ps == ProcessingState.buffering ||
          ps == ProcessingState.ready) {
        await _player!.play();
        return;
      }
      // completed / idle → пересоздаём ↓
    }

    await _stop();

    _currentId = id;
    _isLoading = true;
    _isPlaying = false;
    _hasError  = false;
    _position  = Duration.zero;
    _duration  = Duration.zero;
    _emit();

    final player = AudioPlayer();
    _player = player;

    // ── playerStateStream: атомарная пара (playing, processingState) ────
    // Использование атомарного потока гарантирует, что isPlaying никогда
    // не выйдет из синхронизации с реальным processingState плеера.
    _subs.add(player.playerStateStream.listen((ps) {
      final processing = ps.processingState;

      // ВАЖНО: не трогаем _isLoading когда processing == idle.
      // Новый AudioPlayer при создании сразу испускает idle-событие ещё
      // до начала setUrl. Если мы здесь сбросим _isLoading=false, виджет
      // мгновенно переключится обратно на кнопку play и пользователь
      // увидит «кнопка не работает».
      // _isLoading=true мы выставили вручную перед этим — оставляем его
      // до тех пор, пока плеер не перейдёт в реальное состояние.
      if (processing == ProcessingState.loading ||
          processing == ProcessingState.buffering) {
        _isLoading = true;
      } else if (processing == ProcessingState.ready ||
                 processing == ProcessingState.completed) {
        _isLoading = false;
      }
      // idle → _isLoading не изменяем

      // «Реально играет» — только когда processing == ready
      _isPlaying = ps.playing && processing == ProcessingState.ready;

      if (processing == ProcessingState.completed) {
        _isPlaying = false;
        _position  = _duration;
      }

      // idle после того, как duration уже получена = ошибка воспроизведения
      if (processing == ProcessingState.idle && _currentId == id) {
        if (_duration > Duration.zero) {
          _hasError  = true;
          _isPlaying = false;
          _isLoading = false;
        }
      }

      _emit();
    }));

    // ── positionStream ───────────────────────────────────────────────────
    _subs.add(player.positionStream.listen((pos) {
      if (_player?.processingState != ProcessingState.completed) {
        _position = pos;
        _emit();
      }
    }));

    // ── durationStream ───────────────────────────────────────────────────
    _subs.add(player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        _duration = dur;
        _isLoading = false;
        _emit();
      }
    }));

    // ── Асинхронные ошибки ExoPlayer / AVFoundation ──────────────────────
    _subs.add(player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('AudioPlayerService: playback error: $e');
        _isLoading = false;
        _isPlaying = false;
        _hasError  = true;
        _emit();
      },
    ));

    try {
      final isLocal = !url.startsWith('http://') && !url.startsWith('https://');
      if (isLocal) {
        await player.setFilePath(
          url.startsWith('file://') ? url.substring(7) : url,
        );
      } else {
        await player.setUrl(url);
      }
      await player.play();
    } catch (e, st) {
      debugPrint('AudioPlayerService: setUrl/play error: $e\n$st');
      _isLoading = false;
      _isPlaying = false;
      _hasError  = true;
      _emit();
    }
  }

  Future<void> pause()                  async => _player?.pause();
  Future<void> seekTo(Duration position) async {
    await _player?.seek(position);
    _position = position;
    _emit();
  }

  Future<void> stop() async {
    final id = _currentId;
    await _stop();
    if (id != null) _stateCtrl.add(AudioPlayerState(id: id));
  }

  Future<void> dispose() async {
    await _stop();
    await _stateCtrl.close();
  }

  // ── Приватные ─────────────────────────────────────────────────────────────

  Future<void> _stop() async {
    for (final s in _subs) s.cancel();
    _subs.clear();
    if (_player != null) {
      try { await _player!.stop(); } catch (_) {}
      try { await _player!.dispose(); } catch (_) {}
      _player = null;
    }
    _currentId = null;
    _isPlaying = false;
    _isLoading = false;
    _hasError  = false;
    _position  = Duration.zero;
    _duration  = Duration.zero;
  }

  void _emit() {
    if (_currentId == null || _stateCtrl.isClosed) return;
    _stateCtrl.add(AudioPlayerState(
      id:        _currentId!,
      isPlaying: _isPlaying,
      isLoading: _isLoading,
      position:  _position,
      duration:  _duration,
      hasError:  _hasError,
    ));
  }
}
