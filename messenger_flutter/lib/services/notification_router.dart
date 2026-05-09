import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/call_screen.dart';
import 'notification_parser.dart';
import 'notification_service.dart';
import 'auth_service.dart';
import 'signaling_service.dart';
import 'call_state.dart';

/// Routes notification taps and FCM messages to the correct screen.
///
/// Create one instance and keep it alive for the app lifetime.
/// Call [init] after the navigator is mounted (inside State.initState or
/// after the first frame).
class NotificationRouter {
  final GlobalKey<NavigatorState> navigatorKey;
  final SignalingService signalingService;
  final AuthService auth;
  /// Флаг успешной инициализации Firebase. Если false — FCM-вызовы пропускаются.
  final bool firebaseReady;

  /// Called when a chat notification is tapped.
  /// Set by ResponsiveShell after it mounts so it can select the right chat.
  void Function(String chatId)? onOpenChat;

  NotificationRouter({
    required this.navigatorKey,
    required this.signalingService,
    required this.auth,
    this.firebaseReady = false,
    this.onOpenChat,
  });

  // ── Init: cold-start / background tap recovery ────────────────────────────

  Future<void> init() async {
    // FCM-функции доступны только если Firebase успешно инициализировался.
    if (firebaseReady) {
      // 1. App launched from terminated state via FCM notification tap
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        _routeFcm(initial.data);
      }

      // 2. App in background, FCM notification tapped
      FirebaseMessaging.onMessageOpenedApp.listen((msg) => _routeFcm(msg.data));

      // 3. App in foreground — show local notification (call handled by SignalR)
      FirebaseMessaging.onMessage.listen(_handleForegroundFcm);
    }

    // 4. Local notification tapped while app was terminated (cold-start)
    //    Не требует Firebase — работает всегда.
    if (!kIsWeb) {
      final plugin = FlutterLocalNotificationsPlugin();
      final launchDetails = await plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final response = launchDetails!.notificationResponse;
        if (response != null) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          handleResponse(response);
        }
      }
    }
  }

  // ── Notification response (tap on notification or action button) ──────────

  /// Called by [NotificationService.init] onTap callback (foreground & background).
  void handlePayload(String payloadString) {
    _routePayload(NotificationPayload.fromPayloadString(payloadString));
  }

  /// Handles full NotificationResponse (including action IDs like call_accept).
  /// Called by [NotificationService.init] onResponse callback.
  void handleResponse(NotificationResponse response) {
    final actionId = response.actionId;
    final payload  = response.payload;

    // Action buttons on call notification
    if (actionId == 'call_accept' && payload != null && payload.isNotEmpty) {
      final p = NotificationPayload.fromPayloadString(payload);
      if (p.type == NotificationType.callIncoming) {
        NotificationService.instance.clearCallNotification();
        _handleIncomingCall(p);
        return;
      }
    }
    if (actionId == 'call_decline' && payload != null && payload.isNotEmpty) {
      final p = NotificationPayload.fromPayloadString(payload);
      if (p.type == NotificationType.callIncoming && p.callId != null) {
        NotificationService.instance.clearCallNotification();
        signalingService.leaveCall(p.callId!);
        return;
      }
    }

    // Regular tap (no action button)
    if (payload != null && payload.isNotEmpty) {
      handlePayload(payload);
    }
  }

  // ── Foreground FCM ────────────────────────────────────────────────────────

  void _handleForegroundFcm(RemoteMessage msg) {
    final p = NotificationPayload.fromFcmData(msg.data);
    switch (p.type) {
      case NotificationType.callIncoming:
        // SignalR already shows the in-app overlay when the connection is live.
        // This path fires only when SignalR is disconnected (rare foreground edge-case).
        _handleIncomingCall(p);
        break;
      case NotificationType.message:
        NotificationService.instance.showMessage(p);
        break;
      case NotificationType.system:
        NotificationService.instance.showSystem(p);
        break;
      case NotificationType.unknown:
        break;
    }
  }

  // ── FCM data → route ──────────────────────────────────────────────────────

  void _routeFcm(Map<String, dynamic> data) {
    _routePayload(NotificationPayload.fromFcmData(data));
  }

  // ── Core routing ──────────────────────────────────────────────────────────

  void _routePayload(NotificationPayload p) {
    switch (p.type) {
      case NotificationType.message:
        if (p.chatId != null) _openChat(p.chatId!);
        break;
      case NotificationType.callIncoming:
        _handleIncomingCall(p);
        break;
      case NotificationType.system:
        _showSystemDialog(p.title, p.body);
        break;
      case NotificationType.unknown:
        break;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _openChat(String chatId) {
    NotificationService.instance.clearChatNotifications(chatId);
    if (onOpenChat != null) {
      onOpenChat!(chatId);
    } else {
      // Fallback: pop any modals and let the shell show the chat list
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  void _handleIncomingCall(NotificationPayload p) {
    final callId   = p.callId;
    final callerId = p.callerId;
    if (callId == null || callerId == null) return;

    NotificationService.instance.clearCallNotification();

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final info = IncomingCallInfo(
      callId: callId,
      callerId: callerId,
      callerName: p.callerName ?? 'Неизвестный',
      isVideo: p.isVideo,
      isGroup: p.isGroup,
    );

    Navigator.of(ctx, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _RouterIncomingCallPage(
          info: info,
          signalingService: signalingService,
          auth: auth,
        ),
      ),
    );
  }

  void _showSystemDialog(String? title, String? body) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title ?? 'Уведомление'),
        content: body != null ? Text(body) : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }
}

// ── Incoming call page used by the router ─────────────────────────────────────

class _RouterIncomingCallPage extends StatelessWidget {
  final IncomingCallInfo info;
  final SignalingService signalingService;
  final AuthService auth;

  const _RouterIncomingCallPage({
    required this.info,
    required this.signalingService,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IncomingCallOverlay(
        callInfo: info,
        onAccept: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => CallScreen(
                callId: info.callId,
                peerId: info.callerId,
                peerName: info.callerName,
                isVideo: info.isVideo,
                isOutgoing: false,
                isGroup: info.isGroup,
                signalingService: signalingService,
                auth: auth,
              ),
            ),
          );
        },
        onDecline: () {
          signalingService.leaveCall(info.callId);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
