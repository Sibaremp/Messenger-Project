import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_parser.dart';
import 'notification_settings.dart';

// ── Platform helpers (compile-safe, no dart:io) ───────────────────────────────

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS     => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get _isMacOS   => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
bool get _isLinux   => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

// flutter_local_notifications 17.x has NO Windows backend — Windows falls through
// to the no-op path in each show* method.
bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Platforms supported by flutter_local_notifications 17.x
bool get _supportsFln => !kIsWeb && !_isWindows;

// ── Channel IDs (must match AndroidManifest meta-data) ───────────────────────

const _chMessages = 'messages_channel';
const _chCalls    = 'calls_channel';
const _chSystem   = 'system_channel';

// ── Notification ID helpers ───────────────────────────────────────────────────

// Per-chat message notification (stable across app restarts)
int _chatNotifId(String chatId) => chatId.hashCode.abs() % 500_000;
// Per-chat Android group summary
int _chatSummaryId(String chatId) => chatId.hashCode.abs() % 500_000 + 500_000;

const _callNotifId   = 1_500_000;
const _systemNotifId = 1_500_001;

// ── NotificationService ───────────────────────────────────────────────────────

/// Singleton that manages all local notification display.
///
/// Usage:
///   await NotificationService.instance.init(onTap: router.handlePayload);
///   NotificationService.instance.showMessage(payload);
///   NotificationService.instance.openChat(chatId);   // suppress while in chat
///   NotificationService.instance.closeChat(chatId);  // re-enable on leave
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin   = FlutterLocalNotificationsPlugin();
  final _settings = NotificationSettings.instance;

  bool _initialized = false;

  /// Chat IDs currently visible on screen — notifications suppressed for these.
  final _openChats = <String>{};

  /// In-memory per-chat inbox lines for Android InboxStyle grouping.
  final _inboxLines = <String, List<String>>{};

  /// Per-chat unread counts (used for iOS badge).
  final _unreadCounts = <String, int>{};

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init({
    void Function(String payload)? onTap,
    void Function(NotificationResponse response)? onResponse,
  }) async {
    if (_initialized || !_supportsFln) return;
    _initialized = true;

    if (_isAndroid) await _createAndroidChannels();

    final settings = _buildInitSettings();
    if (settings == null) return;

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (r) {
        if (onResponse != null) {
          onResponse(r);
        } else if (r.payload != null && r.payload!.isNotEmpty && onTap != null) {
          onTap(r.payload!);
        }
      },
      onDidReceiveBackgroundNotificationResponse: _onBackgroundTap,
    );

    // iOS: request permissions
    if (_isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    // macOS: request permissions
    if (_isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // ── Chat open/close (notification suppression) ────────────────────────────

  void openChat(String chatId) {
    _openChats.add(chatId);
    clearChatNotifications(chatId);
  }

  void closeChat(String chatId) => _openChats.remove(chatId);

  // ── Show: message ─────────────────────────────────────────────────────────

  Future<void> showMessage(NotificationPayload p) async {
    if (!_supportsFln || !_initialized) return;
    final chatId = p.chatId;
    if (chatId == null) return;

    if (_openChats.contains(chatId)) return;
    if (await _settings.isChatMuted(chatId)) return;

    final sound   = await _settings.getSoundEnabled();
    final vibrate = await _settings.getVibrationEnabled();

    final title   = p.chatName ?? p.senderName ?? 'Сообщение';
    final text    = _formatBody(p);
    final payload = p.toPayloadString();

    // Track inbox lines for Android InboxStyle
    final lines = _inboxLines.putIfAbsent(chatId, () => []);
    lines.add(text);
    if (lines.length > 5) lines.removeAt(0);

    // Unread count for iOS/macOS badge
    _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1;
    final totalUnread = _unreadCounts.values.fold(0, (a, b) => a + b);

    final notifId = _chatNotifId(chatId);
    final sumId   = _chatSummaryId(chatId);

    // ── Android ──────────────────────────────────────────────────────────
    if (_isAndroid) {
      final styleInfo = lines.length > 1
          ? InboxStyleInformation(
              List<String>.from(lines),
              contentTitle: title,
              summaryText: '${lines.length} сообщений',
            )
          : null;

      await _plugin.show(
        notifId, title, text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chMessages, 'Сообщения',
            channelDescription: 'Уведомления о новых сообщениях',
            importance: Importance.high,
            priority: Priority.high,
            groupKey: 'chat_$chatId',
            setAsGroupSummary: false,
            styleInformation: styleInfo,
            playSound: sound,
            enableVibration: vibrate,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF5C6BC0),
          ),
        ),
        payload: payload,
      );

      // Android group summary
      await _plugin.show(
        sumId, title, '${lines.length} новых сообщений',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chMessages, 'Сообщения',
            importance: Importance.high,
            priority: Priority.high,
            groupKey: 'chat_x',  // overridden per-call below
            setAsGroupSummary: true,
            playSound: false,
            enableVibration: false,
          ),
        ),
        payload: payload,
      );
      // Re-show summary with correct groupKey (const can't use variable)
      await _plugin.cancel(sumId);
      await _plugin.show(
        sumId, title, '${lines.length} новых сообщений',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chMessages, 'Сообщения',
            importance: Importance.high,
            priority: Priority.high,
            groupKey: 'chat_$chatId',
            setAsGroupSummary: true,
            playSound: false,
            enableVibration: false,
          ),
        ),
        payload: payload,
      );
      return;
    }

    // ── iOS ───────────────────────────────────────────────────────────────
    if (_isIOS) {
      await _plugin.show(
        notifId, title, text,
        NotificationDetails(
          iOS: DarwinNotificationDetails(
            sound: sound ? 'default' : null,
            badgeNumber: totalUnread,
            threadIdentifier: chatId,
            presentAlert: true,
            presentBadge: true,
            presentSound: sound,
          ),
        ),
        payload: payload,
      );
      return;
    }

    // ── macOS ─────────────────────────────────────────────────────────────
    if (_isMacOS) {
      await _plugin.show(
        notifId, title, text,
        NotificationDetails(
          macOS: DarwinNotificationDetails(
            sound: sound ? 'default' : null,
            badgeNumber: totalUnread,
            threadIdentifier: chatId,
            presentAlert: true,
            presentBadge: true,
            presentSound: sound,
          ),
        ),
        payload: payload,
      );
      return;
    }

    // ── Linux ─────────────────────────────────────────────────────────────
    if (_isLinux) {
      await _plugin.show(
        notifId, title, text,
        const NotificationDetails(),
        payload: payload,
      );
    }
  }

  // ── Show: incoming call ───────────────────────────────────────────────────

  Future<void> showIncomingCall(NotificationPayload p) async {
    if (!_supportsFln || !_initialized) return;

    final title   = p.callerName ?? 'Входящий звонок';
    final text    = p.isVideo ? '📹 Видеозвонок' : '📞 Голосовой звонок';
    final payload = p.toPayloadString();

    if (_isAndroid) {
      await _plugin.show(
        _callNotifId, title, text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chCalls, 'Звонки',
            channelDescription: 'Уведомления о входящих звонках',
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.call,
            playSound: true,
            enableVibration: true,
            ongoing: true,
            autoCancel: false,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFF43A047),
            actions: [
              const AndroidNotificationAction(
                'decline',
                'Отклонить',
                cancelNotification: true,
                showsUserInterface: false,
              ),
              const AndroidNotificationAction(
                'accept',
                'Принять',
                cancelNotification: true,
                showsUserInterface: true,
              ),
            ],
          ),
        ),
        payload: payload,
      );
      return;
    }

    if (_isIOS || _isMacOS) {
      final darwin = DarwinNotificationDetails(
        sound: 'default',
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        categoryIdentifier: 'CALL_CATEGORY',
      );
      await _plugin.show(
        _callNotifId, title, text,
        NotificationDetails(
          iOS:   _isIOS   ? darwin : null,
          macOS: _isMacOS ? darwin : null,
        ),
        payload: payload,
      );
      return;
    }

    if (_isLinux) {
      await _plugin.show(
        _callNotifId, title, text,
        const NotificationDetails(),
        payload: payload,
      );
    }
  }

  // ── Show: system ──────────────────────────────────────────────────────────

  Future<void> showSystem(NotificationPayload p) async {
    if (!_supportsFln || !_initialized) return;

    final title   = p.title ?? 'Системное уведомление';
    final text    = p.body ?? '';
    final payload = p.toPayloadString();

    if (_isAndroid) {
      await _plugin.show(
        _systemNotifId, title, text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chSystem, 'Системные',
            channelDescription: 'Системные уведомления',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        payload: payload,
      );
      return;
    }

    if (_isIOS || _isMacOS) {
      final darwin = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      );
      await _plugin.show(
        _systemNotifId, title, text,
        NotificationDetails(
          iOS:   _isIOS   ? darwin : null,
          macOS: _isMacOS ? darwin : null,
        ),
        payload: payload,
      );
      return;
    }

    if (_isLinux) {
      await _plugin.show(
        _systemNotifId, title, text,
        const NotificationDetails(),
        payload: payload,
      );
    }
  }

  // ── Dispatch ──────────────────────────────────────────────────────────────

  Future<void> show(NotificationPayload p) async {
    switch (p.type) {
      case NotificationType.message:      return showMessage(p);
      case NotificationType.callIncoming: return showIncomingCall(p);
      case NotificationType.system:       return showSystem(p);
      case NotificationType.unknown:      break;
    }
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  Future<void> clearChatNotifications(String chatId) async {
    _inboxLines.remove(chatId);
    _unreadCounts.remove(chatId);
    if (!_supportsFln || !_initialized) return;
    await _plugin.cancel(_chatNotifId(chatId));
    await _plugin.cancel(_chatSummaryId(chatId));
  }

  Future<void> clearCallNotification() async {
    if (!_supportsFln || !_initialized) return;
    await _plugin.cancel(_callNotifId);
  }

  Future<void> clearAll() async {
    _inboxLines.clear();
    _unreadCounts.clear();
    if (!_supportsFln || !_initialized) return;
    await _plugin.cancelAll();
  }

  Future<void> resetBadge() async {
    _unreadCounts.clear();
    if (!_supportsFln || !_initialized) return;
    if (_isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(badge: true);
    }
    if (_isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(badge: true);
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  InitializationSettings? _buildInitSettings() {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin  = DarwinInitializationSettings(
      requestAlertPermission:  false,
      requestBadgePermission:  false,
      requestSoundPermission:  false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'open');

    if (_isAndroid) return const InitializationSettings(android: android);
    if (_isIOS)     return const InitializationSettings(iOS: darwin);
    if (_isMacOS)   return const InitializationSettings(macOS: darwin);
    if (_isLinux)   return const InitializationSettings(linux: linux);
    return null; // unsupported platform
  }

  Future<void> _createAndroidChannels() async {
    final ap = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (ap == null) return;

    await ap.createNotificationChannel(const AndroidNotificationChannel(
      _chMessages, 'Сообщения',
      description: 'Уведомления о новых сообщениях',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    ));
    await ap.createNotificationChannel(const AndroidNotificationChannel(
      _chCalls, 'Звонки',
      description: 'Уведомления о входящих звонках',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: false,
    ));
    await ap.createNotificationChannel(const AndroidNotificationChannel(
      _chSystem, 'Системные',
      description: 'Системные уведомления',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    ));
  }

  static String _formatBody(NotificationPayload p) {
    final sender = p.senderName;
    // Если сервер передал тип вложения — используем читаемую метку.
    // В противном случае берём text из тела (сервер уже подставил нужный текст).
    final text = p.body ?? '';
    if (sender != null && sender.isNotEmpty) return '$sender: $text';
    return text;
  }

}

// ── Background tap handler (top-level, required by flutter_local_notifications) ─

@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse details) {
  // Navigation is impossible here (no Flutter context in background isolate).
  // The payload will be picked up via getNotificationAppLaunchDetails on resume.
}
