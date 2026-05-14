import 'dart:async';
import 'package:flutter/material.dart';
import 'models.dart';
import 'app_constants.dart';
import 'services/chat_service.dart';
import 'services/auth_service.dart' as svc;
import 'services/local_cache_service.dart';
import 'services/signaling_service.dart';
import 'services/call_state.dart';
import 'services/notification_service.dart';
import 'services/notification_router.dart';
import 'auth_screen.dart' show AuthScreen;
import 'widgets/sidebar.dart';
import 'widgets/chat_widgets.dart';
import 'widgets/member_picker.dart';
import 'widgets/settings_overlay.dart';
import 'screens/chat_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/call_screen.dart';
import 'widgets/notifications_panel.dart';
import 'screens/search_screen.dart';
import 'utils/app_snack.dart';

/// Адаптивная оболочка приложения.
/// - Узкий экран (<800): стандартная мобильная навигация (ChatListScreen).
/// - Широкий экран (>=800): трёх панельный desktop-режим (sidebar + список + чат/профиль).
class ResponsiveShell extends StatefulWidget {
  final ChatService service;
  final svc.AuthService auth;
  final SignalingService signalingService;
  /// Optional — routes chat-tap notifications to this shell.
  final NotificationRouter? notifRouter;

  const ResponsiveShell({
    super.key,
    required this.service,
    required this.auth,
    required this.signalingService,
    this.notifRouter,
  });

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell>
    with TickerProviderStateMixin {
  SidebarNav _nav = SidebarNav.chat;
  Chat? _selectedChat;
  String? _myAvatarPath;
  List<Chat> _chats = [];
  bool _isSearching = false;
  StreamSubscription<ChatEvent>? _eventSub;
  late final TabController _chatTabController;
  late final TabController _academicTabController;

  /// Возвращает активный TabController для текущего раздела.
  TabController get _activeTabController =>
      _nav == SidebarNav.academic ? _academicTabController : _chatTabController;

  List<AppContact> _contacts = [];
  StreamSubscription<IncomingCallInfo>? _incomingCallSub;

  @override
  void initState() {
    super.initState();
    _chatTabController = TabController(length: 2, vsync: this);
    _academicTabController = TabController(length: 2, vsync: this);

    // Откладываем все операции, которые могут вызвать setState, до первого кадра.
    // Это предотвращает "setState() called during build" — TabBarView синхронно
    // уведомляет слушателей TabController прямо внутри buildScope().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadChats();
      _loadAvatar();
      _loadContacts();
      _eventSub = widget.service.events.listen((event) {
        if (!mounted) return;
        _loadChats();
        if (event is ConnectionRestored) {
          _loadContacts();
        }
        if (event is SessionTerminated && event.isCurrent) {
          _logout();
        }
      });
    });

    _incomingCallSub =
        widget.signalingService.onIncomingCall.listen(_onIncomingCall);

    // Wire notification router so tapping a message notification opens the chat.
    if (widget.notifRouter != null) {
      widget.notifRouter!.onOpenChat = _openChatById;
    }
  }

  @override
  void dispose() {
    _chatTabController.dispose();
    _academicTabController.dispose();
    _eventSub?.cancel();
    _incomingCallSub?.cancel();
    super.dispose();
  }

  void _onIncomingCall(IncomingCallInfo info) {
    if (!mounted) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, anim, anim2) => IncomingCallOverlay(
        callInfo: info,
        onAccept: () {
          Navigator.of(ctx).pop();
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
                signalingService: widget.signalingService,
                auth: widget.auth,
              ),
            ),
          );
        },
        onDecline: () {
          widget.signalingService.leaveCall(info.callId);
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
      setState(() {
        _chats = List.from(chats);
        if (_selectedChat != null) {
          final idx = _chats.indexWhere((c) => c.id == _selectedChat!.id);
          if (idx != -1) {
            _selectedChat = _chats[idx];
          } else {
            _selectedChat = null;
          }
        }
      });
    } catch (_) {
      // Сервер временно недоступен — молча игнорируем.
      // При восстановлении SignalR-соединения придёт ConnectionRestored
      // и _loadChats() будет вызван снова автоматически.
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
    } catch (_) {
      // Сервер недоступен — контакты останутся пустыми
    }
  }

  /// Отображаемое имя чата: для личных чатов — ФИО из контактов (если есть),
  /// иначе из участников чата, иначе логин.
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

  List<Chat> get _sortedChats =>
      [..._chats]..sort((a, b) => b.lastTime.compareTo(a.lastTime));

  // ── Обычные чаты (раздел «Общение») ────────────────────────────
  List<Chat> get _regularChats =>
      _sortedChats.where((c) => !c.isAcademic).toList();

  List<Chat> get _personalChats =>
      _regularChats.where((c) => c.type == ChatType.direct).toList();

  List<Chat> get _groupChats =>
      _regularChats.where((c) => c.type != ChatType.direct).toList();

  // ── Академические чаты (раздел «Академический») ────────────────
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
      if (_selectedChat?.id == updated.id) _selectedChat = updated;
    });
  }

  /// Selects a chat by ID (used by NotificationRouter when a message tap arrives).
  void _openChatById(String chatId) {
    if (!mounted) return;
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) {
      // Chat not yet loaded — reload the list and retry once.
      _loadChats().then((_) {
        if (!mounted) return;
        final idx2 = _chats.indexWhere((c) => c.id == chatId);
        if (idx2 != -1) _selectChat(_chats[idx2]);
      });
      return;
    }
    _selectChat(_chats[idx]);
  }

  void _selectChat(Chat chat) {
    // Close the previous chat (re-enable notifications) before switching.
    if (_selectedChat != null && _selectedChat!.id != chat.id) {
      NotificationService.instance.closeChat(_selectedChat!.id);
    }
    setState(() {
      _selectedChat = chat;
      _nav = chat.isAcademic ? SidebarNav.academic : SidebarNav.chat;
    });
    // Mark the new chat as open (suppresses incoming notifications for it).
    NotificationService.instance.openChat(chat.id);
  }

  /// Открывает личный чат из панели (embedded mode).
  /// Если чата ещё нет в списке — добавляет его, затем переключает панель.
  void _onOpenDirectChat(Chat chat) {
    setState(() {
      final idx = _chats.indexWhere((c) => c.id == chat.id);
      if (idx == -1) {
        _chats.add(chat);
      } else {
        _chats[idx] = chat;
      }
    });
    _selectChat(chat);
  }


  /// Показывать ли кнопку действия в sidebar
  bool get _showActionButton {
    // В академическом разделе на вкладке «Группы» — только для преподавателей
    if (_nav == SidebarNav.academic && _activeTabController.index == 1) {
      return widget.auth.currentUser?.isTeacher == true;
    }
    // В остальных случаях: только для чатов (Общение / Академический)
    return _nav == SidebarNav.chat || _nav == SidebarNav.academic;
  }

  /// Текст и иконка кнопки в sidebar зависят от вкладки
  String get _sidebarActionLabel {
    if (_activeTabController.index == 1 &&
        (_nav == SidebarNav.chat || _nav == SidebarNav.academic)) {
      return 'Создать группу';
    }
    return 'Новый чат';
  }

  IconData get _sidebarActionIcon => Icons.add;

  /// Обработчик нажатия кнопки
  void _showCreateOptions() {
    final isGroupsTab = _activeTabController.index == 1 &&
        (_nav == SidebarNav.chat || _nav == SidebarNav.academic);
    final isAcademic = _nav == SidebarNav.academic;

    // На вкладке «Личные» — сразу новый чат
    if (!isGroupsTab) {
      _openNewDirectChat();
      return;
    }

    // Академические группы может создавать только преподаватель
    if (isAcademic && widget.auth.currentUser?.isTeacher != true) {
      AppSnack.info(context, 'Только преподаватель может создавать академические группы');
      return;
    }

    // На вкладке «Группы» — выбор: группа или сообщество
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
              width: 40, height: 4,
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
              title: Text(isAcademic ? 'Создать академическую группу' : 'Создать группу',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
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
              title: Text(isAcademic ? 'Создать академическое сообщество' : 'Создать сообщество',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
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
    setState(() {
      _selectedChat = null;
      _showContactPicker = true;
      _contactPickerInitialTab = _nav == SidebarNav.academic ? 1 : 0;
    });
  }

  bool _showContactPicker = false;
  int _contactPickerInitialTab = 0;

  Future<void> _onContactPicked(AppContact contact) async {
    final chat = await widget.service.createDirectChat(
      contactName: contact.name,
      isAcademic: contact.isTeacher,
    );
    if (!mounted) return;
    if (!_contacts.any((c) => c.name == contact.name)) {
      _contacts.add(contact);
    }
    setState(() {
      _selectedChat = chat;
      _showContactPicker = false;
    });
    _loadChats();
  }

  void _openCreateDialog(ChatType type, {bool isAcademic = false}) {
    showDialog(
      context: context,
      builder: (_) => _DesktopCreateChatDialog(
        type: type,
        isAcademic: isAcademic,
        contacts: _contacts,
        creatorName: widget.auth.currentUser?.name ?? 'Я',
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
            if (!mounted) return;
            setState(() {
              _chats.add(chat);
              _selectedChat = chat;
            });
          } catch (e) {
            if (!mounted) return;
                        AppSnack.error(context, 'Ошибка: $e');
          }
        },
      ),
    );
  }

  /// Открывает главное меню настроек (пункт «Настройки» в сайдбаре).
  void _openSettings() {
    showSettingsOverlay(
      context,
      auth: widget.auth,
      service: widget.service,
      onAvatarChanged: _loadAvatar,
      onLogout: _logout,
    );
  }

  /// Открывает только страницу профиля (нажатие на карточку пользователя).
  void _openProfile() {
    showSettingsOverlay(
      context,
      auth: widget.auth,
      service: widget.service,
      onAvatarChanged: _loadAvatar,
      onLogout: _logout,
      profileOnly: true,
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
                builder: (_) => ResponsiveShell(
              service: widget.service,
              auth: widget.auth,
              signalingService: widget.signalingService,
            ),
              ),
              (_) => false,
            );
          },
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < AppSizes.desktopBreakpoint) {
      return ChatListScreen(
        service: widget.service,
        auth: widget.auth,
        signalingService: widget.signalingService,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          // ── Sidebar (полная высота) ─────────────────────────────
          Sidebar(
            selected: _nav,
            onSelect: (nav) {
              if (nav == SidebarNav.profile) {
                _openSettings();
              } else {
                setState(() {
                  _nav = nav;
                  _isSearching = false;
                });
              }
            },
            onNewChat: _showCreateOptions,
            onLogout: _logout,
            actionLabel: _sidebarActionLabel,
            actionIcon: _sidebarActionIcon,
            showActionButton: _showActionButton,
            displayName: widget.auth.currentUser?.displayName,
            userName: widget.auth.currentUser?.name,
            userAvatarPath: _myAvatarPath,
            chatUnreadCount: _regularChats.fold(
                0, (sum, c) => sum + c.unreadCount),
            onSettingsTap: _openProfile,
          ),
          VerticalDivider(
              width: 1, thickness: 1,
              color: Theme.of(context).dividerColor),

          // ── Контент (панели без общего TopBar) ──────────────────
          Expanded(
            child: Row(
              children: [
                // ── Средняя панель ─────────────────────────────
                if (_nav == SidebarNav.chat || _nav == SidebarNav.academic)
                  SizedBox(
                    width: AppSizes.middlePanelWidth,
                    child: _nav == SidebarNav.academic
                        ? _buildAcademicListPanel()
                        : _buildChatListPanel(),
                  ),
                if (_nav == SidebarNav.chat || _nav == SidebarNav.academic)
                  VerticalDivider(
                      width: 1, thickness: 1,
                      color: Theme.of(context).dividerColor),

                // ── Правая панель ───────────────────────────────
                Expanded(
                  child: _buildRightPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    // Режим поиска — показываем SearchScreen вместо чата
    if (_isSearching) {
      return SearchScreen(
        service: widget.service,
        contacts: _contacts,
        embedded: true,
        auth: widget.auth,
        signalingService: widget.signalingService,
        onChatSelected: (chat) {
          setState(() {
            _selectedChat = chat;
            _isSearching = false;
          });
        },
      );
    }

    switch (_nav) {
      case SidebarNav.profile:
        // Settings are shown as an overlay — fall through to empty panel.
        return const _EmptyPanel();
      case SidebarNav.notifications:
        return NotificationsPanel(service: widget.service);
      case SidebarNav.academic:
      case SidebarNav.chat:
        if (_showContactPicker) {
          return _SimpleContactPicker(
            key: ValueKey('picker_$_contactPickerInitialTab'),
            contacts: _contacts,
            existingChats: _chats,
            embedded: true,
            initialTab: _contactPickerInitialTab,
            onBack: () => setState(() => _showContactPicker = false),
            onContactPicked: _onContactPicked,
          );
        }
        if (_selectedChat != null) {
          return ChatScreen(
            key: ValueKey(_selectedChat!.id),
            chat: _selectedChat!,
            service: widget.service,
            onChatUpdated: _onChatUpdated,
            contacts: _contacts,
            embedded: true,
            auth: widget.auth,
            signalingService: widget.signalingService,
            onOpenDirectChat: _onOpenDirectChat,
          );
        }
        return const _EmptyPanel();
    }
  }

  Widget _statusIcon(MessageStatus status) {
    return switch (status) {
      MessageStatus.sending   => const Icon(Icons.access_time, size: 13, color: AppColors.subtle),
      MessageStatus.sent      => const Icon(Icons.done, size: 15, color: AppColors.subtle),
      MessageStatus.delivered => const Icon(Icons.done_all, size: 15, color: AppColors.subtle),
      MessageStatus.read      => const Icon(Icons.done_all, size: 15, color: Color(0xFF4FC3F7)),
      MessageStatus.error     => const Icon(Icons.error_outline, size: 13, color: Colors.red),
    };
  }

  // ── Средняя панель: список чатов ───────────────────────────────────────

  Widget _buildChatListPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _PanelHeader(
          title: 'Общение',
          isDark: isDark,
          isSearching: _isSearching,
          onSearchTap: () => setState(() => _isSearching = true),
          onSearchClose: () => setState(() => _isSearching = false),
        ),
        TabBar(
          controller: _chatTabController,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: AppColors.subtle,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [Tab(text: 'Личные'), Tab(text: 'Группы')],
          onTap: (_) => setState(() {}),
        ),
        Expanded(
          child: TabBarView(
            controller: _chatTabController,
            children: [
              _buildDesktopChatList(_personalChats),
              _buildDesktopChatList(_groupChats),
            ],
          ),
        ),
      ],
    );
  }

  // ── Средняя панель: академический раздел ─────────────────────────────────

  Widget _buildAcademicListPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _PanelHeader(
          title: 'Академический',
          isDark: isDark,
          isSearching: _isSearching,
          onSearchTap: () => setState(() => _isSearching = true),
          onSearchClose: () => setState(() => _isSearching = false),
        ),
        TabBar(
          controller: _academicTabController,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: AppColors.subtle,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [Tab(text: 'Личные'), Tab(text: 'Группы')],
          onTap: (_) => setState(() {}),
        ),
        Expanded(
          child: TabBarView(
            controller: _academicTabController,
            children: [
              _buildDesktopChatList(_academicPersonal),
              _buildDesktopChatList(_academicGroups),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopChatList(List<Chat> chats) {
    if (chats.isEmpty) {
      return const Center(
        child: Text('Нет чатов', style: TextStyle(color: AppColors.subtle)),
      );
    }
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        final isSelected = _selectedChat?.id == chat.id;
        return Column(
          children: [
            Material(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() {
                  _selectedChat = chat;
                  _isSearching = false;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      ChatAvatar(
                          type: chat.type, avatarPath: chat.avatarPath, chatName: _chatDisplayName(chat)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _chatDisplayName(chat),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (chat.messages.isNotEmpty && chat.messages.last.isMe) ...[
                                  _statusIcon(chat.messages.last.status),
                                  const SizedBox(width: 3),
                                ],
                                Expanded(
                                  child: Text(
                                    chat.lastMessage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.subtle, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
          ],
        );
      },
    );
  }
}

// ─── Заголовок средней панели (название + строка поиска) ────────────────────

class _PanelHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  final bool isSearching;
  final VoidCallback onSearchTap;
  final VoidCallback onSearchClose;

  const _PanelHeader({
    required this.title,
    required this.isDark,
    required this.isSearching,
    required this.onSearchTap,
    required this.onSearchClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Заголовок раздела
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          // Строка поиска
          GestureDetector(
            onTap: onSearchTap,
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(8),
                border: isSearching
                    ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(
                    Icons.search,
                    size: 16,
                    color: isSearching
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.subtle.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Поиск',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.subtle.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  if (isSearching)
                    GestureDetector(
                      onTap: onSearchClose,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.close,
                            size: 15, color: AppColors.subtle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Пустое правое окно ──────────────────────────────────────────────────────

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 64,
              color: AppColors.subtle.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text(
            'Выберите чат',
            style: TextStyle(color: AppColors.subtle, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ─── Выборщик контактов с табами Общение/Академический ────────────────────────

class _SimpleContactPicker extends StatefulWidget {
  final List<AppContact> contacts;
  final List<Chat> existingChats;
  final bool embedded;
  final int initialTab;
  final VoidCallback? onBack;
  final ValueChanged<AppContact>? onContactPicked;

  const _SimpleContactPicker({
    super.key,
    required this.contacts,
    required this.existingChats,
    this.embedded = false,
    this.initialTab = 0,
    this.onBack,
    this.onContactPicked,
  });

  @override
  State<_SimpleContactPicker> createState() => _SimpleContactPickerState();
}

class _SimpleContactPickerState extends State<_SimpleContactPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  bool get _showTeachers => widget.initialTab == 1;

  static const _avatarColors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6), Color(0xFFFFB74D),
    Color(0xFFBA68C8), Color(0xFF4DD0E1), Color(0xFFF06292), Color(0xFFAED581),
  ];

  Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return _avatarColors[hash % _avatarColors.length];
  }

  bool _hasChat(String name) => widget.existingChats
      .any((c) => c.name == name && c.type == ChatType.direct);

  List<AppContact> get _filtered {
    var list = widget.contacts.where((c) => c.isTeacher == _showTeachers);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((c) =>
          c.name.toLowerCase().contains(q) ||
          (c.group?.toLowerCase().contains(q) ?? false));
    }
    return list.toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(AppContact contact) {
    if (widget.embedded) {
      widget.onContactPicked?.call(contact);
    } else {
      Navigator.pop(context, contact.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
            : null,
        title: Text(
          _showTeachers ? 'Преподаватели' : 'Новый чат',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: _showTeachers ? 'Поиск преподавателей...' : 'Поиск контактов...',
                hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38),
                prefixIcon: Icon(Icons.search,
                    color: isDark ? Colors.white38 : Colors.black38),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            color: isDark ? Colors.white54 : Colors.black45),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFF2F2F2),
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
      body: _buildContactList(
        _filtered, isDark,
        _showTeachers ? 'Нет преподавателей' : 'Нет студентов',
      ),
    );
  }

  Widget _buildContactList(List<AppContact> filtered, bool isDark, String emptyText) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 56,
                color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? emptyText : 'Ничего не найдено',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38, fontSize: 15),
            ),
          ],
        ),
      );
    }

    // Группируем по первой букве
    final grouped = <String, List<AppContact>>{};
    for (final c in filtered) {
      final letter = c.name.isNotEmpty ? c.name[0].toUpperCase() : '#';
      grouped.putIfAbsent(letter, () => []).add(c);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: sortedKeys.length,
      itemBuilder: (context, sectionIndex) {
        final letter = sortedKeys[sectionIndex];
        final contacts = grouped[letter]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(letter, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary, letterSpacing: 0.5)),
            ),
            ...contacts.map((c) {
              final color = _colorFor(c.name);
              final hasChat = _hasChat(c.name);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _select(c),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: color.withValues(alpha: 0.18),
                        child: Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                          style: TextStyle(color: color,
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87)),
                            if (c.group != null)
                              Text(c.group!, style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white54 : Colors.black45)),
                          ],
                        ),
                      ),
                      if (hasChat)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                          child: Text('Открыть', style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                ),
              );
            }),
            if (sectionIndex < sortedKeys.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 60, right: 16),
                child: Divider(height: 1,
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
              ),
          ],
        );
      },
    );
  }
}

// ─── Диалог создания группы (desktop) ────────────────────────────────────────

class _DesktopCreateChatDialog extends StatefulWidget {
  final ChatType type;
  final bool isAcademic;
  final List<AppContact> contacts;
  final String creatorName;
  final Future<void> Function(
          String name, List<ChatMember> members, String? adminName, String? description)
      onCreated;

  const _DesktopCreateChatDialog({
    required this.type,
    required this.contacts,
    required this.onCreated,
    required this.creatorName,
    this.isAcademic = false,
  });

  @override
  State<_DesktopCreateChatDialog> createState() =>
      _DesktopCreateChatDialogState();
}

class _DesktopCreateChatDialogState
    extends State<_DesktopCreateChatDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Set<String> _selected = {};
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название');
      return;
    }
    final members = [
      ChatMember(name: widget.creatorName, role: MemberRole.creator),
      ..._selected
          .where((n) => n != widget.creatorName)
          .map((n) => ChatMember(name: n, role: MemberRole.member)),
    ];
    final adminName = widget.creatorName;
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();
    Navigator.pop(context);
    await widget.onCreated(name, members, adminName, description);
  }

  @override
  Widget build(BuildContext context) {
    final base =
        widget.type == ChatType.group ? 'Новая группа' : 'Новое сообщество';
    final title = widget.isAcademic ? '$base (академическая)' : base;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Название',
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
              decoration: const InputDecoration(
                labelText: 'Описание (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            MemberPickerSection(
              contacts: widget.contacts,
              selected: _selected,
              onToggle: (login, sel) => setState(() {
                sel ? _selected.add(login) : _selected.remove(login);
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: _submit,
          style:
              FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          child: const Text('Создать'),
        ),
      ],
    );
  }
}
