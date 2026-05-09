import 'dart:convert';

// ── Notification types ────────────────────────────────────────────────────────

enum NotificationType { message, callIncoming, system, unknown }

// ── Payload model ─────────────────────────────────────────────────────────────

/// Unified model for all notification payloads.
/// Produced from FCM data-map and stored as JSON string in local notification payload.
class NotificationPayload {
  final NotificationType type;

  // message
  final String? chatId;
  final String? chatName;
  final String? senderId;
  final String? senderName;
  final String? body;

  // call_incoming
  final String? callId;
  final String? callerId;
  final String? callerName;
  final bool isVideo;
  final bool isGroup;

  // system
  final String? title;

  const NotificationPayload({
    required this.type,
    this.chatId,
    this.chatName,
    this.senderId,
    this.senderName,
    this.body,
    this.callId,
    this.callerId,
    this.callerName,
    this.isVideo = false,
    this.isGroup = false,
    this.title,
  });

  // ── Factory: from FCM data map ─────────────────────────────────────────────

  factory NotificationPayload.fromFcmData(Map<String, dynamic> data) {
    final rawType = data['type'] as String? ?? '';
    switch (rawType) {
      case 'message':
        return NotificationPayload(
          type: NotificationType.message,
          chatId: data['chatId'] as String?,
          // Server sends 'chatName' for group chats; falls back to senderName as title
          chatName: data['chatName'] as String?,
          senderId: data['senderId'] as String?,
          senderName: data['senderName'] as String?,
          // Server sends 'text'; some gateways may use 'body'
          body: (data['text'] ?? data['body']) as String?,
        );

      case 'call_incoming':
        return NotificationPayload(
          type: NotificationType.callIncoming,
          callId: data['callId'] as String?,
          callerId: data['callerId'] as String?,
          callerName: data['callerName'] as String?,
          isVideo: data['isVideo'] == 'true' || data['isVideo'] == true,
          isGroup: data['isGroup'] == 'true' || data['isGroup'] == true,
        );

      case 'system':
        return NotificationPayload(
          type: NotificationType.system,
          title: data['title'] as String?,
          body: data['body'] as String?,
        );

      case 'admin_notification':
        // Административное уведомление — показываем как системное.
        return NotificationPayload(
          type:  NotificationType.system,
          title: data['title'] as String?,
          body:  data['body']  as String?,
        );

      default:
        return const NotificationPayload(type: NotificationType.unknown);
    }
  }

  // ── Serialisation for local notification payload string ────────────────────

  String toPayloadString() => jsonEncode({
        'type': _typeToString(type),
        if (chatId != null) 'chatId': chatId,
        if (chatName != null) 'chatName': chatName,
        if (senderId != null) 'senderId': senderId,
        if (senderName != null) 'senderName': senderName,
        if (body != null) 'body': body,
        if (callId != null) 'callId': callId,
        if (callerId != null) 'callerId': callerId,
        if (callerName != null) 'callerName': callerName,
        'isVideo': isVideo,
        'isGroup': isGroup,
        if (title != null) 'title': title,
      });

  factory NotificationPayload.fromPayloadString(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const NotificationPayload(type: NotificationType.unknown);
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return NotificationPayload.fromFcmData(map);
    } catch (_) {
      return const NotificationPayload(type: NotificationType.unknown);
    }
  }

  static String _typeToString(NotificationType t) {
    switch (t) {
      case NotificationType.message:      return 'message';
      case NotificationType.callIncoming: return 'call_incoming';
      case NotificationType.system:       return 'system';
      case NotificationType.unknown:      return 'unknown';
    }
  }
}
