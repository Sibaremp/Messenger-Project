import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';

/// Кэширует последние [maxMessages] сообщений каждого чата в SharedPreferences,
/// а также список всех чатов — для мгновенного отображения при запуске приложения
/// до завершения запроса к серверу.
class LocalCacheService {
  static const int    maxMessages = 25;
  static const String _prefix     = 'msg_cache_v2_';
  static const String _tsPrefix   = 'msg_cache_ts_';
  static const String _chatsKey   = 'chat_list_cache_v1';

  // Синглтон
  static final LocalCacheService instance = LocalCacheService._();
  LocalCacheService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ── Загрузка ────────────────────────────────────────────────────────────────

  /// Возвращает закэшированные сообщения чата, либо `null` если кэша нет.
  Future<List<Message>?> loadMessages(String chatId) async {
    final prefs = await _p;
    final raw = prefs.getString('$_prefix$chatId');
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((j) => Message.fromJson(j as Map<String, dynamic>, currentUserId: ''))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Время последнего сохранения кэша для чата (null если кэша нет).
  Future<DateTime?> lastSaved(String chatId) async {
    final prefs = await _p;
    final ts = prefs.getInt('$_tsPrefix$chatId');
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }

  // ── Сохранение ──────────────────────────────────────────────────────────────

  /// Сохраняет последние [maxMessages] сообщений.
  /// Пустой список сохраняется намеренно — это сигнал «чат очищен»,
  /// чтобы при следующем открытии не загружался устаревший кэш.
  Future<void> saveMessages(String chatId, List<Message> messages) async {
    final prefs  = await _p;
    final last   = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : List<Message>.from(messages);
    final json   = jsonEncode(last.map((m) => m.toJson()).toList());
    await prefs.setString('$_prefix$chatId', json);
    await prefs.setInt('$_tsPrefix$chatId',
        DateTime.now().millisecondsSinceEpoch);
  }

  // ── Список чатов ────────────────────────────────────────────────────────────

  /// Сохраняет список чатов (только метаданные + последнее сообщение).
  Future<void> saveChats(List<Chat> chats, {required String currentUserId}) async {
    final prefs = await _p;
    final json  = jsonEncode(chats.map((c) => c.toJson()).toList());
    await prefs.setString(_chatsKey, json);
  }

  /// Возвращает закэшированный список чатов, либо `[]` если кэша нет.
  Future<List<Chat>> loadCachedChats({required String currentUserId}) async {
    final prefs = await _p;
    final raw   = prefs.getString(_chatsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((j) => Chat.fromJson(j as Map<String, dynamic>, currentUserId: currentUserId))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Очистка ─────────────────────────────────────────────────────────────────

  Future<void> clearChat(String chatId) async {
    final prefs = await _p;
    await prefs.remove('$_prefix$chatId');
    await prefs.remove('$_tsPrefix$chatId');
  }

  Future<void> clearAll() async {
    final prefs = await _p;
    final keys  = prefs.getKeys()
        .where((k) => k.startsWith(_prefix) || k.startsWith(_tsPrefix))
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    await prefs.remove(_chatsKey);
  }
}
