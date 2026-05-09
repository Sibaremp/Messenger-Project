import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_config.dart';
import '../services/audio_player_service.dart';

/// Виджет воспроизведения голосового сообщения в пузыре чата.
class AudioMessageBubble extends StatefulWidget {
  /// Путь/URL к аудиофайлу (серверный относительный или абсолютный).
  final String audioPath;

  /// Длительность из модели (мс). Показывается до загрузки трека.
  final int? durationMs;

  /// Цвет иконок/текста — адаптируется к цвету пузыря.
  final Color foregroundColor;

  const AudioMessageBubble({
    super.key,
    required this.audioPath,
    this.durationMs,
    this.foregroundColor = Colors.white,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  final _svc = AudioPlayerService.instance;
  StreamSubscription<AudioPlayerState>? _sub;

  bool     _isPlaying = false;
  bool     _isLoading = false;
  bool     _hasError  = false;
  Duration _position  = Duration.zero;
  Duration _duration  = Duration.zero;

  /// Идентификатор трека = путь до файла.
  String get _id => widget.audioPath;

  /// Полный URL для воспроизведения (нормализует localhost → IP эмулятора).
  String get _url =>
      ApiConfig.resolveMediaUrl(widget.audioPath) ?? widget.audioPath;

  @override
  void initState() {
    super.initState();
    if (widget.durationMs != null) {
      _duration = Duration(milliseconds: widget.durationMs!);
    }

    _sub = _svc.stateStream.listen((state) {
      if (!mounted) return;

      if (state.id != _id) {
        // Другой трек заиграл — сбросить этот виджет
        if (_isPlaying || _isLoading) {
          setState(() {
            _isPlaying = false;
            _isLoading = false;
            _hasError  = false;
            _position  = Duration.zero;
          });
        }
        return;
      }

      setState(() {
        _isPlaying = state.isPlaying;
        _isLoading = state.isLoading;
        _hasError  = state.hasError;
        _position  = state.position;
        // Обновляем длительность только если сервер вернул реальное значение
        if (state.duration > Duration.zero) _duration = state.duration;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isLoading) return;
    if (_isPlaying) {
      await _svc.pause();
    } else {
      // Если трек дошёл до конца — визуально сбрасываем позицию
      // до того как сервис начнёт загрузку (иначе бар остаётся на 100%).
      if (_position >= _duration && _duration > Duration.zero) {
        setState(() { _position = Duration.zero; });
      }
      await _svc.play(_id, _url);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Прогресс в [0..1] на основе миллисекунд для плавности
    final totalMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1;
    final progress = (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    final fg   = widget.foregroundColor;
    final fgDim = fg.withAlpha(160);

    return SizedBox(
      width: 224,
      child: Row(
        children: [
          // ── Play / Pause / Loading / Error ─────────────────────────────
          SizedBox(
            width: 40,
            height: 40,
            child: _isLoading
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: fg,
                    ),
                  )
                : _hasError
                    ? Icon(Icons.error_outline, color: fg, size: 28)
                    : IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: fg,
                          size: 36,
                        ),
                        onPressed: _togglePlay,
                      ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Прогресс-бар ──────────────────────────────────────
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor:   fg,
                    inactiveTrackColor: fg.withAlpha(70),
                    thumbColor:         fg,
                    overlayColor:       fg.withAlpha(30),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: _hasError
                        ? null
                        : (v) async {
                            final target = Duration(
                              milliseconds:
                                  (v * _duration.inMilliseconds).round(),
                            );
                            await _svc.seekTo(target);
                          },
                  ),
                ),

                // ── Время ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 2),
                  child: _hasError
                      ? Text(
                          'Ошибка воспроизведения',
                          style: TextStyle(fontSize: 10, color: fgDim),
                        )
                      : Text(
                          _isPlaying || _position > Duration.zero
                              ? '${_fmt(_position)} / ${_fmt(_duration)}'
                              : _fmt(_duration),
                          style: TextStyle(fontSize: 11, color: fgDim),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
