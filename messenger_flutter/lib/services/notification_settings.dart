import 'package:shared_preferences/shared_preferences.dart';

/// Per-user notification preferences stored in SharedPreferences.
/// Keys are namespaced to avoid collisions with the rest of the app.
class NotificationSettings {
  NotificationSettings._();
  static final NotificationSettings instance = NotificationSettings._();

  static const _sound        = 'notif_sound_enabled';
  static const _vibration    = 'notif_vibration_enabled';
  static const _mutePrefix   = 'notif_mute_chat_';

  // ── Sound ──────────────────────────────────────────────────────────────────

  Future<bool> getSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sound) ?? true;
  }

  Future<void> setSoundEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sound, value);
  }

  // ── Vibration ─────────────────────────────────────────────────────────────

  Future<bool> getVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vibration) ?? true;
  }

  Future<void> setVibrationEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibration, value);
  }

  // ── Per-chat mute ─────────────────────────────────────────────────────────

  Future<bool> isChatMuted(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_mutePrefix$chatId') ?? false;
  }

  Future<void> setChatMuted(String chatId, bool muted) async {
    final prefs = await SharedPreferences.getInstance();
    if (muted) {
      await prefs.setBool('$_mutePrefix$chatId', true);
    } else {
      await prefs.remove('$_mutePrefix$chatId');
    }
  }

  Future<void> toggleChatMute(String chatId) async {
    final current = await isChatMuted(chatId);
    await setChatMuted(chatId, !current);
  }
}
