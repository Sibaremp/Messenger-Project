import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caspian_college_messenger/main.dart';
import 'package:caspian_college_messenger/services/auth_service.dart';
import 'package:caspian_college_messenger/services/api_chat_service.dart';
import 'package:caspian_college_messenger/services/signaling_service.dart';
import 'package:caspian_college_messenger/services/notification_router.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final auth             = AuthService();
    final chatService      = ApiChatService(auth);
    final signalingService = SignalingService(auth);
    final notifRouter      = NotificationRouter(
      navigatorKey:     navigatorKey,
      signalingService: signalingService,
      auth:             auth,
    );
    await tester.pumpWidget(MyApp(
      chatService:      chatService,
      auth:             auth,
      signalingService: signalingService,
      notifRouter:      notifRouter,
      firebaseReady:    false,
    ));
  });
}
