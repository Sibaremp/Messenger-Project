import 'package:shared_preferences/shared_preferences.dart';

/// Глобальный уровень громкости для всех медиа.
/// Сохраняется через SharedPreferences и восстанавливается при запуске.
class VolumeService {
  VolumeService._();
  static final VolumeService instance = VolumeService._();

  static const String _key = 'video_volume';
  static const double defaultVolume = 0.7;

  double _volume = defaultVolume;

  /// Текущий уровень громкости [0.0 … 1.0].
  double get volume => _volume;

  /// Инициализация — вызвать один раз в [main()] перед [runApp].
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _volume = (prefs.getDouble(_key) ?? defaultVolume).clamp(0.0, 1.0);
  }

  /// Сохраняет новый уровень громкости.
  Future<void> save(double v) async {
    _volume = v.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, _volume);
  }
}
