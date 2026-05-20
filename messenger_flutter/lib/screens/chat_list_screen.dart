import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart' as svc;
import '../services/call_state.dart';
import '../services/local_cache_service.dart';
import '../auth_screen.dart' show AuthScreen;
import '../profile_screen.dart' show ProfileAvatar;
import '../services/signaling_service.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/member_picker.dart';
import '../widgets/settings_overlay.dart' show MobileSettingsPage;
import 'call_screen.dart' show CallScreen, IncomingCallOverlay;
import 'chat_screen.dart';
import 'search_screen.dart';
import '../utils/app_snack.dart';
import '../services/notification_service.dart';
import '../l10n/app_localizations.dart';

/// Главный мобильный экран с BottomNavigationBar (4 вкладки).
/// Используется при ширине экрана < [AppSizes.desktopBreakpoint].
class ChatListScreen extends StatefulWidget {
  final ChatService service;
  final svc.AuthService auth;
  final SignalingService? signalingService;

  const ChatListScreen({
    super.key,
    required this.service,
    required this.auth,
    this.signalingService,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with TickerProviderStateMixin {
  // ── Навигация BottomNav ─────────────────────────────────────────
  int _bottomIndex = 1; // 0=Академический, 1=Общение, 2=Уведомления, 3=Профиль

  // ── Два TabController для двух chat-секций ──────────────────────
  late final TabController _academicTabCtrl;
  late final TabController _chatTabCtrl;

  // ── Данные ──────────────────────────────────────────────────────
  String? _myAvatarPath;
  List<Chat> _chats = [];
  StreamSubscription<ChatEvent>? _eventSub;
  StreamSubscription<IncomingCallInfo>? _incomingCallSub;

  List<AppContact> _contacts = [];

  // ── Уведомления (упоминания) ─────────────────────────────────
  /// Накопленные уведомления (упоминания текущего пользователя).
  final List<_AppNotification> _notifications = [];

  /// Количество непрочитанных уведомлений — отображается бейджем.
  int get _unreadNotifications =>
      _notifications.where((n) => !n.read).length;

  @override
  void initState() {
    super.initState();
    _academicTabCtrl = TabController(length: 2, vsync: this);
    _chatTabCtrl = TabController(length: 2, vsync: this);

    // Все операции с setState откладываем до первого кадра,
    // чтобы не попасть в фазу build (TabBarView синхронизирует
    // TabController во время build и может вызвать listener).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Обновляем FAB при переключении вкладок.
      // ВАЖНО: setState оборачиваем в addPostFrameCallback, иначе TabBarView
      // может синхронно уведомить слушателей прямо внутри buildScope() —
      // это вызывает "setState() called during build".
      _academicTabCtrl.addListener(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      });
      _chatTabCtrl.addListener(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      });

      _loadChats();
      _loadAvatar();
      _loadContacts();

      // Подписываемся на входящие звонки (для мобильного режима и узкого веба)
      _incomingCallSub =
          widget.signalingService?.onIncomingCall.listen(_onIncomingCall);

      _eventSub = widget.service.events.listen((event) {
        if (!mounted) return;
        _loadChats();
        if (event is SessionTerminated && event.isCurrent) {
          _logout();
        }
        if (event is MessageReceived && !event.message.isMe) {
          final myName = widget.auth.currentUser?.name ?? '';
          final msg = event.message;

          final mentioned = msg.mentions
              .any((m) => m.username == myName || m.userId == 'all');
          if (mentioned) {
            setState(() {
              _notifications.insert(0, _AppNotification(
                type:       _NotifType.mention,
                senderName: msg.senderName ?? context.l10n.participantLabel,
                message:    msg.text,
                time:       msg.time,
              ));
            });
          }

          final replyTo = msg.replyTo;
          if (!mentioned && replyTo != null && replyTo.senderName == myName) {
            setState(() {
              _notifications.insert(0, _AppNotification(
                type:       _NotifType.reply,
                senderName: msg.senderName ?? context.l10n.participantLabel,
                message:    msg.text,
                time:       msg.time,
              ));
            });
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _academicTabCtrl.dispose();
    _chatTabCtrl.dispose();
    _eventSub?.cancel();
    _incomingCallSub?.cancel();
    super.dispose();
  }

  void _onIncomingCall(IncomingCallInfo info) {
    if (!mounted) return;
    final myName = widget.auth.currentUser?.name ?? '';
    final relatedChat = info.chatId != null
        ? _chats.where((c) => c.id == info.chatId).firstOrNull
        : null;
    final canSpeak = relatedChat == null ||
        relatedChat.type != ChatType.community ||
        relatedChat.isCreatorOrAdmin(myName);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, anim, anim2) => IncomingCallOverlay(
        callInfo: info,
        onAccept: () async {
          Navigator.of(ctx).pop();
          await CallScreen.forceEndActive();
          await Future.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => CallScreen(
                callId: info.callId,
                peerId: info.callerId,
                peerName: info.callerName,
                isVideo: info.isVideo,
                isOutgoing: false,
                isGroup: info.isGroup,
                signalingService: widget.signalingService!,
                auth: widget.auth,
                canSpeak: canSpeak,
              ),
            ),
          );
        },
        onDecline: () {
          widget.signalingService?.leaveCall(info.callId);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _loadChats() async {
    // Показываем кэшированные чаты мгновенно (до ответа сервера)
    final uid = widget.auth.currentUser?.id ?? '';
    final cached = await LocalCacheService.instance.loadCachedChats(currentUserId: uid);
    if (mounted && cached.isNotEmpty && _chats.isEmpty) {
      // Откладываем setState до конца текущего кадра, чтобы не попасть в build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chats.isEmpty) {
          setState(() => _chats = List.from(cached));
        }
      });
    }

    try {
      final chats = await widget.service.loadChats();
      if (!mounted) return;
      // Сохраняем актуальный список в кэш
      unawaited(LocalCacheService.instance.saveChats(chats, currentUserId: uid));
      setState(() => _chats = List.from(chats));
    } catch (_) {
      // Сервер недоступен — остаёмся на кэшированных данных
    }
  }

  Future<void> _loadAvatar() async {
    final user = widget.auth.currentUser;
    if (user?.avatarUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _myAvatarPath = user!.avatarUrl);
      });
    }
  }

  Future<void> _loadContacts() async {
    try {
      final raw = await widget.auth.loadContacts();
      if (!mounted) return;
      setState(() {
        _contacts = raw.map((j) => AppContact.fromJson(j)).toList();
      });
    } catch (_) {}
  }

  /// Отображаемое имя чата: для личных чатов — ФИО, иначе название группы.
  String _chatDisplayName(Chat chat) {
    if (chat.type != ChatType.direct) return chat.name;
    final contactName =
        _contacts.where((c) => c.name == chat.name).firstOrNull?.bestName;
    if (contactName != null) return contactName;
    final memberName = chat.members
        .where((m) => m.name == chat.name)
        .firstOrNull
        ?.displayName;
    return memberName ?? chat.name;
  }

  // ── Сортированные и фильтрованные списки ───────────────────────
  List<Chat> get _sortedChats =>
      [..._chats]..sort((a, b) => b.lastTime.compareTo(a.lastTime));

  // Общение (не академические)
  List<Chat> get _regularChats =>
      _sortedChats.where((c) => !c.isAcademic).toList();
  List<Chat> get _regularPersonal =>
      _regularChats.where((c) => c.type == ChatType.direct).toList();
  List<Chat> get _regularGroups =>
      _regularChats.where((c) => c.type != ChatType.direct).toList();

  // Академические
  List<Chat> get _academicChats =>
      _sortedChats.where((c) => c.isAcademic).toList();
  List<Chat> get _academicPersonal =>
      _academicChats.where((c) => c.type == ChatType.direct).toList();
  List<Chat> get _academicGroups =>
      _academicChats.where((c) => c.type != ChatType.direct).toList();

  void _onChatUpdated(Chat updated) {
    setState(() {
      final i = _chats.indexWhere((c) => c.id == updated.id);
      if (i != -1) _chats[i] = updated;
    });
  }

  // ── Логика FAB ─────────────────────────────────────────────────
  /// Нужно ли показывать FAB для текущей комбинации раздел+вкладка
  bool get _showFab {
    switch (_bottomIndex) {
      case 0: // Академический
        // Личные → новый чат; Группы → только преподаватели
        if (_academicTabCtrl.index == 0) return true;
        return widget.auth.currentUser?.isTeacher == true;
      case 1: // Общение
        // Личные → новый чат, Группы → создать группу/сообщество
        return true;
      default:
        return false; // Уведомления, Профиль
    }
  }

  void _onFabPressed() {
    switch (_bottomIndex) {
      case 0: // Академический
        if (_academicTabCtrl.index == 0) {
          _openNewDirectChat();
        } else {
          // Только преподаватель сюда попадёт (из _showFab)
          _showGroupCreateOptions(isAcademic: true);
        }
      case 1: // Общение
        if (_chatTabCtrl.index == 0) {
          _openNewDirectChat();
        } else {
          _showGroupCreateOptions();
        }
    }
  }

  /// Bottom sheet для создания группы/сообщества
  void _showGroupCreateOptions({bool isAcademic = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.group, color: AppColors.textLight),
              ),
              title: Text(
                  isAcademic ? context.l10n.createAcademicGroup : context.l10n.createGroup,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(context.l10n.allCanWrite),
              onTap: () {
                Navigator.pop(context);
                _openCreateDialog(ChatType.group, isAcademic: isAcademic);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.campaign, color: AppColors.textLight),
              ),
              title: Text(
                  isAcademic ? context.l10n.createAcademicCommunity : context.l10n.createCommunity,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(context.l10n.onlyAdminWrites),
              onTap: () {
                Navigator.pop(context);
                _openCreateDialog(ChatType.community, isAcademic: isAcademic);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openNewDirectChat() async {
    final name = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _ContactPickerScreen(
          contacts: _contacts,
          existingChats: _chats,
        ),
      ),
    );
    if (name == null || !mounted) return;

    final chat = await widget.service.createDirectChat(contactName: name);
    if (!mounted) return;

    if (!_contacts.any((c) => c.name == name)) {
      setState(() => _contacts.add(AppContact(name: name)));
    }

    NotificationService.instance.openChat(chat.id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chat: chat,
          service: widget.service,
          onChatUpdated: _onChatUpdated,
          contacts: _contacts,
          auth: widget.auth,
          signalingService: widget.signalingService,
        ),
      ),
    );
    NotificationService.instance.closeChat(chat.id);
    _loadChats();
  }

  void _openCreateDialog(ChatType type, {bool isAcademic = false}) {
    showDialog(
      context: context,
      builder: (_) => _CreateChatDialog(
        type: type,
        isAcademic: isAcademic,
        contacts: _contacts,
        creatorName: widget.auth.currentUser?.name ?? context.l10n.you,
        onCreated: (name, members, adminName, description) async {
          try {
            final chat = await widget.service.createGroupOrCommunity(
              name: name,
              type: type,
              members: members,
              adminName: adminName,
              isAcademic: isAcademic,
              description: description,
            );
            if (mounted) {
              setState(() => _chats.add(chat));
            }
          } catch (e) {
            if (mounted) {
                            AppSnack.error(context, context.l10n.profileSaveError(e.toString()));
            }
          }
        },
      ),
    );
  }

  Future<void> _logout() async {
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (ctx) => AuthScreen(
          auth: widget.auth,
          onLoginSuccess: () {
            Navigator.of(ctx).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) {
                  widget.signalingService?.ensureConnected();
                  return ChatListScreen(
                    service: widget.service,
                    auth: widget.auth,
                    signalingService: widget.signalingService,
                  );
                },
              ),
              (_) => false,
            );
          },
        ),
      ),
      (_) => false,
    );
  }

  // ── Build ──────────────────────────────────────────────────────

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          service: widget.service,
          contacts: _contacts,
          auth: widget.auth,
          signalingService: widget.signalingService,
        ),
      ),
    ).then((_) => _loadChats());
  }


  /// Возвращает только активную вкладку — исключает одновременную инициализацию
  /// всех четырёх страниц в IndexedStack, которая приводила к
  /// «setState during build» из дочерних initState.
  Widget _buildCurrentPage() {
    switch (_bottomIndex) {
      case 0:
        return _buildAcademicTab();
      case 1:
        return _buildChatTab();
      case 2:
        return _MobileNotificationsPage(
          notifications: _notifications,
          onMarkRead: (n) => setState(() => _notifications.remove(n)),
          onMarkAllRead: () => setState(() => _notifications.clear()),
        );
      case 3:
        return SafeArea(
          bottom: false,
          child: MobileSettingsPage(
            auth: widget.auth,
            service: widget.service,
            onAvatarChanged: _loadAvatar,
            onLogout: _logout,
          ),
        );
      default:
        return _buildChatTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: _buildCurrentPage(),
      floatingActionButton: _showFab
          ? FloatingActionButton(
              onPressed: _onFabPressed,
              backgroundColor: primary,
              elevation: 3,
              child: const Icon(Icons.edit_outlined, color: Colors.white, size: 22),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bottomIndex,
        onDestinationSelected: (i) {
          setState(() {
            _bottomIndex = i;
            if (i == 2) {
              for (final n in _notifications) { n.read = true; }
            }
          });
        },
        backgroundColor:
            isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: context.l10n.academicSection,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: context.l10n.chatSection,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text('$_unreadNotifications',
                  style: const TextStyle(fontSize: 10)),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: context.l10n.notificationsTab,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: context.l10n.settingsTab,
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicTab() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildTabHeader(context.l10n.academicSection, _academicTabCtrl),
          Expanded(
            child: TabBarView(
              controller: _academicTabCtrl,
              children: [
                _buildChatList(_academicPersonal),
                _buildChatList(_academicGroups),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildTabHeader(context.l10n.chatSection, _chatTabCtrl),
          Expanded(
            child: TabBarView(
              controller: _chatTabCtrl,
              children: [
                _buildChatList(_regularPersonal),
                _buildChatList(_regularGroups),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabHeader(String title, TabController ctrl) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Единая шапка: лого + название слева, поиск + аватар справа ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
          child: Row(
            children: [
              // Логотип
              Image.asset(
                'assets/images/logo.png',
                width: 32,
                height: 32,
              ),
              const SizedBox(width: 8),
              // Название приложения
              const Text(
                'Caspian Messenger',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              // Поиск
              IconButton(
                icon: Icon(Icons.search_rounded, color: primary, size: 24),
                onPressed: _openSearch,
                splashRadius: 22,
              ),
              // Аватар / профиль
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => MobileSettingsPage.openProfilePage(
                    context,
                    auth: widget.auth,
                    onAvatarChanged: _loadAvatar,
                  ),
                  child: ProfileAvatar(avatarPath: _myAvatarPath, radius: 18),
                ),
              ),
            ],
          ),
        ),
        // ── Pill-chips (Telegram folders style) ─────────────────────
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _tgTabChip(context.l10n.personalTab, ctrl.index == 0, Icons.person_outline,
                  () => _switchTab(ctrl, 0), primary, isDark),
              const SizedBox(width: 8),
              _tgTabChip(context.l10n.groupsTab, ctrl.index == 1, Icons.group_outlined,
                  () => _switchTab(ctrl, 1), primary, isDark),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  void _switchTab(TabController ctrl, int index) {
    ctrl.animateTo(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _tgTabChip(String label, bool selected, IconData icon,
      VoidCallback onTap, Color primary, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: isDark ? 0.25 : 0.12)
              : isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected
                    ? primary
                    : isDark
                        ? Colors.white54
                        : Colors.black45),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? primary
                    : isDark
                        ? Colors.white60
                        : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Иконка статуса для превью ──────────────────────────────────

  Widget _statusIcon(MessageStatus status) {
    return switch (status) {
      MessageStatus.sending   => const Icon(Icons.access_time, size: 14, color: AppColors.subtle),
      MessageStatus.sent      => const Icon(Icons.done, size: 16, color: AppColors.subtle),
      MessageStatus.delivered => const Icon(Icons.done_all, size: 16, color: AppColors.subtle),
      MessageStatus.read      => const Icon(Icons.done_all, size: 16, color: Color(0xFF4FC3F7)),
      MessageStatus.error     => const Icon(Icons.error_outline, size: 14, color: Colors.red),
    };
  }

  // ── Общий список чатов ─────────────────────────────────────────

  Widget _buildChatList(List<Chat> chats) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    if (chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 64,
                color: AppColors.subtle.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(context.l10n.noChats,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : Colors.black38)),
            const SizedBox(height: 6),
            Text(context.l10n.pressEditToStart,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white24 : Colors.black26)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat     = chats[index];
        final name     = _chatDisplayName(chat);
        final hasUnread = chat.unreadCount > 0;
        final isLastMsg = chat.messages.isNotEmpty;
        final isMyLast  = isLastMsg && chat.messages.last.isMe;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey(chat.id),
            onTap: () async {
              NotificationService.instance.openChat(chat.id);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    chat: chat,
                    service: widget.service,
                    onChatUpdated: _onChatUpdated,
                    contacts: _contacts,
                    auth: widget.auth,
                    signalingService: widget.signalingService,
                  ),
                ),
              );
              NotificationService.instance.closeChat(chat.id);
              _loadChats();
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Аватар 54px ──────────────────────────────
                      ChatAvatar(
                          type: chat.type,
                          avatarPath: chat.avatarPath,
                          chatName: name),
                      const SizedBox(width: 12),
                      // ── Контент ──────────────────────────────────
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // ── Строка 1: имя + время ─────────────
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  // Иконка типа (группа / канал)
                                  if (chat.type == ChatType.group)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 3),
                                      child: Icon(Icons.group_rounded,
                                          size: 14,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38),
                                    )
                                  else if (chat.type == ChatType.community)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 3),
                                      child: Icon(Icons.campaign_rounded,
                                          size: 14,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38),
                                    ),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  if (isMyLast) ...[
                                    _statusIcon(chat.messages.last.status),
                                    const SizedBox(width: 3),
                                  ],
                                  Text(
                                    formatChatTime(chat.lastTime),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hasUnread
                                          ? primary
                                          : AppColors.subtle,
                                      fontWeight: hasUnread
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              // ── Строка 2: превью + бейдж ──────────
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      chat.lastMessage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                  if (hasUnread) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      constraints:
                                          const BoxConstraints(minWidth: 22),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        chat.unreadCount > 99
                                            ? '99+'
                                            : '${chat.unreadCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Разделитель от аватара, как в Telegram
                Padding(
                  padding: const EdgeInsets.only(left: 78),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Мобильная страница уведомлений (встроена в IndexedStack)
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileNotificationsPage extends StatefulWidget {
  final List<_AppNotification> notifications;
  final void Function(_AppNotification) onMarkRead;
  final VoidCallback onMarkAllRead;

  const _MobileNotificationsPage({
    required this.notifications,
    required this.onMarkRead,
    required this.onMarkAllRead,
  });

  @override
  State<_MobileNotificationsPage> createState() =>
      _MobileNotificationsPageState();
}

class _MobileNotificationsPageState extends State<_MobileNotificationsPage> {
  int _selectedFilter = 0;

  List<_AppNotification> get _filtered {
    if (_selectedFilter == 1) {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      return widget.notifications
          .where((n) => n.time.isAfter(cutoff))
          .toList();
    }
    return widget.notifications;
  }

  void _markRead(_AppNotification n) => widget.onMarkRead(n);
  void _markAllRead() => widget.onMarkAllRead();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _filtered;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Заголовок в стиле Telegram ────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(context.l10n.notificationsTab,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),
                ),
                if (widget.notifications.isNotEmpty)
                  TextButton.icon(
                    onPressed: _markAllRead,
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: Text(context.l10n.markAllRead,
                        style: const TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),
          ),
          // ── Фильтр-чипсы ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                _buildFilterChip(context.l10n.allNotif, _selectedFilter == 0,
                    () => setState(() => _selectedFilter = 0)),
                const SizedBox(width: 8),
                _buildFilterChip(context.l10n.lastDay, _selectedFilter == 1,
                    () => setState(() => _selectedFilter = 1)),
              ],
            ),
          ),
          Divider(
            height: 0.5,
            thickness: 0.5,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07),
          ),
          // Список
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(context.l10n.noNotifications,
                        style: const TextStyle(color: AppColors.subtle)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 24,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey.withValues(alpha: 0.15),
                    ),
                    itemBuilder: (_, i) {
                      final n = items[i];
                      // Dismissible позволяет смахнуть уведомление, чтобы
                      // пометить прочитанным — привычная мобильная идиома.
                      return Dismissible(
                        key: ValueKey(
                            '${n.senderName}_${n.time.millisecondsSinceEpoch}'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => _markRead(n),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.done_all,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        child: _buildNotificationCard(n, isDark),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onTap) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: isDark ? 0.25 : 0.12)
              : isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? primary
                : isDark
                    ? Colors.white60
                    : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(_AppNotification n, bool isDark) {
    final isMention = n.type == _NotifType.mention;
    final accentColor = isMention ? Theme.of(context).colorScheme.primary : Colors.teal;
    final typeIcon   = isMention ? Icons.alternate_email : Icons.reply;
    final typeLabel  = isMention ? context.l10n.mentionLabel : context.l10n.replyNotif;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Иконка типа уведомления
        CircleAvatar(
          radius: 22,
          backgroundColor: accentColor.withValues(alpha: 0.15),
          child: Icon(typeIcon, color: accentColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Тип + имя отправителя
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      typeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      n.senderName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (n.message.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  n.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatTime(n.time),
              style: TextStyle(fontSize: 11, color: AppColors.subtle),
            ),
            const SizedBox(height: 6),
            // Кнопка «Прочитать» — удаляет уведомление из списка
            GestureDetector(
              onTap: () => _markRead(n),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  context.l10n.readBtn,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Тип уведомления — упоминание или ответ на сообщение пользователя.
enum _NotifType { mention, reply }

class _AppNotification {
  final _NotifType type;
  final String senderName;
  /// Текст сообщения, в котором упомянули / ответили.
  final String message;
  final DateTime time;
  bool read = false;

  _AppNotification({
    required this.type,
    required this.senderName,
    required this.message,
    required this.time,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// Диалог создания группы / сообщества
// ═══════════════════════════════════════════════════════════════════════════════

class _CreateChatDialog extends StatefulWidget {
  final ChatType type;
  final bool isAcademic;
  final List<AppContact> contacts;
  /// Имя текущего пользователя — становится создателем группы/сообщества.
  final String creatorName;
  final Future<void> Function(
          String name, List<ChatMember> members, String? adminName, String? description)
      onCreated;

  const _CreateChatDialog({
    required this.type,
    required this.contacts,
    required this.onCreated,
    required this.creatorName,
    this.isAcademic = false,
  });

  @override
  State<_CreateChatDialog> createState() => _CreateChatDialogState();
}

class _CreateChatDialogState extends State<_CreateChatDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Set<String> _selectedContacts = {};
  String? _nameError;

  String _title(BuildContext context) {
    final base = widget.type == ChatType.group
        ? context.l10n.newGroup
        : context.l10n.newCommunityTitle;
    return widget.isAcademic ? '$base (${context.l10n.academicSection.toLowerCase()})' : base;
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = context.l10n.enterNameError);
      return;
    }

    // Создатель всегда идёт первым с ролью creator.
    // Остальные участники — с ролью member.
    final members = [
      ChatMember(name: widget.creatorName, role: MemberRole.creator),
      ..._selectedContacts
          .where((n) => n != widget.creatorName) // исключаем дублирование
          .map((n) => ChatMember(name: n, role: MemberRole.member)),
    ];
    // adminName — реальное имя создателя (сервер и клиент используют это поле)
    final adminName = widget.creatorName;
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    Navigator.pop(context);
    await widget.onCreated(name, members, adminName, description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title(context)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.chatNameLabel,
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.l10n.descriptionOpt,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            MemberPickerSection(
              contacts: widget.contacts,
              selected: _selectedContacts,
              onToggle: (login, sel) => setState(() {
                sel ? _selectedContacts.add(login) : _selectedContacts.remove(login);
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          child: Text(context.l10n.create),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Экран выбора контакта для нового чата
// ═══════════════════════════════════════════════════════════════════════════════

class _ContactPickerScreen extends StatefulWidget {
  final List<AppContact> contacts;
  final List<Chat> existingChats;

  const _ContactPickerScreen({
    required this.contacts,
    required this.existingChats,
  });

  @override
  State<_ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<_ContactPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  List<fc.Contact>? _deviceContacts;
  bool _loadingDevice = false;
  bool _permissionDenied = false;
  Set<String> _registeredPhones = {};

  @override
  void initState() {
    super.initState();
    _loadRegisteredPhones();
    if (_isMobile) _loadDeviceContacts();
  }

  void _loadRegisteredPhones() {
    // Все зарегистрированные телефоны берём из списка контактов сервера
    final phones = <String>{};
    for (final c in widget.contacts) {
      if (c.phone != null && c.phone!.isNotEmpty) {
        phones.add(c.phone!.replaceAll(RegExp(r'\D'), ''));
      }
    }
    setState(() => _registeredPhones = phones);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool _isInApp(fc.Contact contact) {
    for (final p in contact.phones) {
      final normalized = p.number.replaceAll(RegExp(r'\D'), '');
      if (normalized.isNotEmpty && _registeredPhones.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  List<AppContact> get _filteredApp {
    if (_query.isEmpty) return widget.contacts;
    final q = _query.toLowerCase();
    return widget.contacts
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.group?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  List<fc.Contact> get _filteredDevice {
    final all = _deviceContacts ?? [];
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) => c.displayName.toLowerCase().contains(q)).toList();
  }

  bool _hasChat(String name) => widget.existingChats
      .any((c) => c.name == name && c.type == ChatType.direct);

  Future<void> _loadDeviceContacts() async {
    if (!mounted) return;
    setState(() {
      _loadingDevice = true;
      _permissionDenied = false;
    });
    final granted = await fc.FlutterContacts.requestPermission(readonly: true);
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _loadingDevice = false;
        _permissionDenied = true;
      });
      return;
    }
    final contacts = await fc.FlutterContacts.getContacts(withProperties: true);
    if (mounted) {
      setState(() {
        _deviceContacts = contacts;
        _loadingDevice = false;
      });
    }
  }

  Widget _openBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          context.l10n.openBtn,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _inAppBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 11, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              context.l10n.inAppContacts,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final filteredApp = _filteredApp;
    final filteredDevice = _filteredDevice;
    final deviceLoaded = _deviceContacts != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.newChat),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: context.l10n.searchByNameOrNumber,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Builder(builder: (context) {
        if (_isMobile) {
          if (_loadingDevice) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                  SizedBox(height: 16),
                  Text(context.l10n.loadingContacts,
                      style: const TextStyle(color: AppColors.subtle)),
                ],
              ),
            );
          }

          if (_permissionDenied) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.contacts_outlined,
                        size: 56, color: AppColors.subtle),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.noContactAccess,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.allowAccessDesc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.subtle),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _loadDeviceContacts,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.retry),
                      style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            );
          }

          if (deviceLoaded) {
            return _buildContactList(filteredApp, filteredDevice);
          }

          return const SizedBox.shrink();
        }

        return _buildAppContactsOnly(filteredApp);
      }),
    );
  }

  Widget _buildContactList(
      List<AppContact> appContacts, List<fc.Contact> deviceContacts) {
    return ListView(
      children: [
        _SectionHeader(
          title: '${context.l10n.deviceContacts} (${deviceContacts.length})',
        ),
        if (deviceContacts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(context.l10n.noContactsFound,
                  style: const TextStyle(color: AppColors.subtle)),
            ),
          )
        else
          ...deviceContacts.map((dc) => _deviceContactTile(dc)),
        if (appContacts.isNotEmpty) ...[
          _SectionHeader(
            title: '${context.l10n.inAppContacts} (${appContacts.length})',
          ),
          ...appContacts.map((c) => _appContactTile(c)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAppContactsOnly(List<AppContact> contacts) {
    if (contacts.isEmpty) {
      return Center(
        child:
            Text(context.l10n.noContactsFound, style: const TextStyle(color: AppColors.subtle)),
      );
    }
    return ListView(
      children: contacts.map((c) => _appContactTile(c)).toList(),
    );
  }

  Widget _deviceContactTile(fc.Contact dc) {
    final displayName = dc.displayName;
    final phone = dc.phones.isNotEmpty ? dc.phones.first.number : null;
    final hasChat = _hasChat(displayName);
    final inApp = _isInApp(dc);

    return Column(
      children: [
        ListTile(
          leading: dc.photo != null
              ? CircleAvatar(backgroundImage: MemoryImage(dc.photo!))
              : CircleAvatar(
                  backgroundColor: inApp
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                      : Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  child: Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
          title: Text(displayName),
          subtitle: phone != null
              ? Text(phone,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.subtle))
              : null,
          trailing:
              hasChat ? _openBadge() : inApp ? _inAppBadge() : null,
          onTap: () => Navigator.of(context).pop(displayName),
        ),
        const Divider(height: 1, indent: 72),
      ],
    );
  }

  Widget _appContactTile(AppContact contact) {
    final hasChat = _hasChat(contact.name);
    final displayName = contact.bestName;
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(displayName),
          subtitle: contact.group != null
              ? Text(contact.group!,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.subtle))
              : null,
          trailing: hasChat ? _openBadge() : null,
          onTap: () => Navigator.of(context).pop(contact.name),
        ),
        const Divider(height: 1, indent: 72),
      ],
    );
  }
}

// ── Заголовок секции ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.subtle,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Логотип Caspian Messenger ─────────────────────────────────────────────────

/// Компактная брендовая плашка: иконка + "Caspian Messenger".
/// Используется в шапке вкладок чатов.
class _CaspianLogo extends StatelessWidget {
  const _CaspianLogo();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Иконка: градиентный круг с волной ───────────────────────
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0088CC), Color(0xFF00C8C8)],
            ),
          ),
          child: const Icon(Icons.waves_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        // ── Надпись ──────────────────────────────────────────────────
        Text(
          'Caspian Messenger',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }
}
