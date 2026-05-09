import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_kit/media_kit.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'theme.dart';
import 'services/chat_service.dart';
import 'services/auth_service.dart';
import 'services/api_chat_service.dart';
import 'services/signaling_service.dart';
import 'services/notification_service.dart';
import 'services/notification_router.dart';
import 'services/volume_service.dart';
import 'responsive_shell.dart';
import 'auth_screen.dart';

/// Global navigator key — required for notification-triggered navigation.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Top-level FCM background handler — выполняется в отдельном Dart-изоляте.
/// Вызывается когда приложение свёрнуто или закрыто, и FCM-сообщение
/// является data-only (без notification-блока).
///
/// • Сообщения чата:  сервер добавляет notification-блок → Android/iOS
///   показывают их автоматически; этот хендлер для них НЕ вызывается.
/// • Входящие звонки: data-only → показываем local notification с fullScreenIntent.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final type = message.data['type'] as String?;
  if (type == 'call_incoming') {
    await _bgShowCallNotification(message.data);
  }
}

/// Показывает full-screen уведомление о входящем звонке из фонового изолята.
/// Использует FlutterLocalNotificationsPlugin напрямую (без синглтона).
@pragma('vm:entry-point')
Future<void> _bgShowCallNotification(Map<String, dynamic> data) async {
  const _callChannelId   = 'calls_channel';
  const _callChannelName = 'Звонки';
  const _callNotifId     = 1_500_000;

  final plugin = FlutterLocalNotificationsPlugin();

  // Инициализируем плагин в фоновом изоляте (только Android актуально).
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  // Создаём канал если его нет (идемпотентно).
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        _callChannelId,
        _callChannelName,
        description: 'Уведомления о входящих звонках',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));

  final callerName = data['callerName'] as String? ?? 'Входящий звонок';
  final isVideo    = data['isVideo'] == 'true';

  await plugin.show(
    _callNotifId,
    callerName,
    isVideo ? '📹 Видеозвонок' : '📞 Голосовой звонок',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _callChannelId,
        _callChannelName,
        importance:      Importance.max,
        priority:        Priority.max,
        // fullScreenIntent показывает звонок поверх заблокированного экрана
        fullScreenIntent: true,
        category:        AndroidNotificationCategory.call,
        playSound:       true,
        enableVibration: true,
        // ongoing: уведомление нельзя смахнуть пальцем
        ongoing:    true,
        autoCancel: false,
        color: const Color(0xFF43A047),
        actions: const [
          AndroidNotificationAction(
            'call_decline',
            'Отклонить',
            cancelNotification: true,
            showsUserInterface: false, // не открывает приложение
          ),
          AndroidNotificationAction(
            'call_accept',
            'Принять',
            cancelNotification: true,
            showsUserInterface: true, // выводит приложение на передний план
          ),
        ],
      ),
    ),
    // Payload содержит все данные звонка — router обработает их при открытии
    payload: jsonEncode(data),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Register media_kit as just_audio backend on platforms without native support.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized(
      windows: Platform.isWindows,
      linux:   Platform.isLinux,
    );
  }

  await VolumeService.instance.init();

  // Audio session — mobile / macOS only (Windows/Linux may hang).
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }

  // Firebase is optional — app runs without google-services.json.
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
    firebaseReady = true;
  } catch (_) {}

  final auth             = AuthService();
  await auth.tryRestoreSession();
  final ChatService chatService   = ApiChatService(auth);
  final signalingService          = SignalingService(auth);

  // ── Notification service & router ──────────────────────────────────────────
  // Router is created here so it can be passed down. init() is called inside
  // _AppRootState.initState after the widget tree (and navigator) is ready.
  final notifRouter = NotificationRouter(
    navigatorKey:      navigatorKey,
    signalingService:  signalingService,
    auth:              auth,
    firebaseReady:     firebaseReady,
    // onOpenChat is wired by ResponsiveShell via a callback; see _AppRootState
  );

  runApp(ThemeProvider(
    child: MyApp(
      chatService:       chatService,
      auth:              auth,
      signalingService:  signalingService,
      notifRouter:       notifRouter,
      firebaseReady:     firebaseReady,
    ),
  ));
}

// ── MyApp ─────────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  final ChatService chatService;
  final AuthService auth;
  final SignalingService signalingService;
  final NotificationRouter notifRouter;
  final bool firebaseReady;

  const MyApp({
    super.key,
    required this.chatService,
    required this.auth,
    required this.signalingService,
    required this.notifRouter,
    required this.firebaseReady,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caspian Messenger',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      themeMode: ThemeProvider.of(context).themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
        Locale('en', 'US'),
        Locale('kk', 'KZ'),
      ],
      home: _AppRoot(
        chatService:       chatService,
        auth:              auth,
        signalingService:  signalingService,
        notifRouter:       notifRouter,
        firebaseReady:     firebaseReady,
      ),
    );
  }
}

// ── _AppRoot ──────────────────────────────────────────────────────────────────

class _AppRoot extends StatefulWidget {
  final ChatService chatService;
  final AuthService auth;
  final SignalingService signalingService;
  final NotificationRouter notifRouter;
  final bool firebaseReady;

  const _AppRoot({
    required this.chatService,
    required this.auth,
    required this.signalingService,
    required this.notifRouter,
    required this.firebaseReady,
  });

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Управление ресурсами при переходе в фон / возврате.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Освобождаем аудио-сессию чтобы не удерживать ресурсы в фоне.
        // (не актуально для Web и не-мобильных платформ)
        if (!kIsWeb &&
            (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
          AudioSession.instance.then((s) => s.setActive(false));
        }
      case AppLifecycleState.resumed:
        // Возвращаем аудио-сессию при выходе на передний план.
        if (!kIsWeb &&
            (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
          AudioSession.instance.then((s) => s.setActive(true));
        }
      default:
        break;
    }
  }

  Future<void> _initNotifications() async {
    // ── 1. Init local notifications plugin ───────────────────────────────────
    try {
      await NotificationService.instance.init(
        onResponse: widget.notifRouter.handleResponse,
      );
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }

    // ── 2. Firebase / FCM setup ───────────────────────────────────────────────
    if (widget.firebaseReady) await _setupFcm();

    // ── 3. Wire router (cold-start & background taps) ─────────────────────────
    // Runs after a short delay so the navigator is fully mounted.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await widget.notifRouter.init();
    } catch (e) {
      debugPrint('[NotificationRouter] init error: $e');
    }
  }

  Future<void> _setupFcm() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission (iOS/macOS/Android 13+)
    await messaging.requestPermission(alert: true, sound: true, badge: true);

    // Disable FCM auto-display of foreground notifications on iOS —
    // we show them via flutter_local_notifications instead.
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    // Register / refresh FCM token
    messaging.onTokenRefresh.listen(widget.auth.registerFcmToken);
    final token = await messaging.getToken();
    if (token != null) widget.auth.registerFcmToken(token);
  }

  @override
  Widget build(BuildContext context) {
    return AuthGate(
      auth: widget.auth,
      homeScreen: ResponsiveShell(
        service:          widget.chatService,
        auth:             widget.auth,
        signalingService: widget.signalingService,
        notifRouter:      widget.notifRouter,
      ),
    );
  }
}

