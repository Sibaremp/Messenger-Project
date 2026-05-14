import 'package:shared_preferences/shared_preferences.dart';

/// Per-user notification preferences stored in SharedPreferences.
/// Keys are namespaced to avoid collisions with the rest of the app.
class NotificationSettings {
  NotificationSettings._();
  static final NotificationSettings instance = NotificationSettings._();

  static const _sound        = 'notif_sound_enabled';
  static const _vibration    = 'notif_vibration_enabled';
  static const _mutePrefix   = 'notif_mute_chat_';

  // Category toggles
  static const _chats       = 'notif_chats_enabled';
  static const _groups      = 'notif_groups_enabled';
  static const _communities = 'notif_communities_enabled';
  static const _news        = 'notif_news_enabled';
  static const _calls       = 'notif_calls_enabled';
  static const _preview     = 'notif_preview_enabled';

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

  // ── Categories ────────────────────────────────────────────────────────────

  Future<bool> getChatsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_chats) ?? true;
  Future<void> setChatsEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_chats, v);

  Future<bool> getGroupsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_groups) ?? true;
  Future<void> setGroupsEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_groups, v);

  Future<bool> getCommunitiesEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_communities) ?? true;
  Future<void> setCommunitiesEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_communities, v);

  Future<bool> getNewsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_news) ?? true;
  Future<void> setNewsEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_news, v);

  Future<bool> getCallsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_calls) ?? true;
  Future<void> setCallsEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_calls, v);

  Future<bool> getPreviewEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_preview) ?? true;
  Future<void> setPreviewEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_preview, v);

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
