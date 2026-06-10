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
import 'l10n/app_localizations.dart';

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
  bool _sidebarCollapsed = false;
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

    // Убеждаемся что хаб звонков подключён (актуально после логина
    // когда токен мог быть недоступен при создании SignalingService).
    widget.signalingService.ensureConnected();

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
    // На мобильных ResponsiveShell рендерит ChatListScreen, который сам
    // подписан на onIncomingCall. Чтобы не было двух диалогов — пропускаем
    // обработку здесь и отдаём её ChatListScreen.
    final width = MediaQuery.of(context).size.width;
    if (width < AppSizes.desktopBreakpoint) return;
    // В сообществах: проверяем может ли пользователь говорить
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
          // Завершаем предыдущий звонок (если есть), освобождаем камеру/микрофон
          await CallScreen.forceEndActive();
          // Небольшая пауза, чтобы предыдущий экран успел unmount
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
                signalingService: widget.signalingService,
                auth: widget.auth,
                canSpeak: canSpeak,
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
            // Chat no longer exists on server — close its notification suppression.
            NotificationService.instance.closeChat(_selectedChat!.id);
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
      _isSearching = false;
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
  String _sidebarActionLabel(BuildContext context) {
    if (_activeTabController.index == 1 &&
        (_nav == SidebarNav.chat || _nav == SidebarNav.academic)) {
      return context.l10n.createGroup;
    }
    return context.l10n.newChat;
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
      AppSnack.info(context, context.l10n.onlyTeacherCanCreate);
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
              title: Text(isAcademic ? context.l10n.createAcademicGroup : context.l10n.createGroup,
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
              title: Text(isAcademic ? context.l10n.createAcademicCommunity : context.l10n.createCommunity,
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
    // Close notifications for the currently open chat before navigating away.
    if (_selectedChat != null) {
      NotificationService.instance.closeChat(_selectedChat!.id);
    }
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
    setState(() => _showContactPicker = false);
    _selectChat(chat);
    _loadChats();
  }

  void _openCreateDialog(ChatType type, {bool isAcademic = false}) {
    showDialog(
      context: context,
      builder: (_) => _DesktopCreateChatDialog(
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
            if (!mounted) return;
            setState(() => _chats.add(chat));
            _selectChat(chat);
          } catch (e) {
            if (!mounted) return;
                        AppSnack.error(context, context.l10n.profileSaveError(e.toString()));
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
            actionLabel: _sidebarActionLabel(context),
            actionIcon: _sidebarActionIcon,
            showActionButton: _showActionButton,
            displayName: widget.auth.currentUser?.displayName,
            userName: widget.auth.currentUser?.name,
            userAvatarPath: _myAvatarPath,
            chatUnreadCount: _regularChats.fold(
                0, (sum, c) => sum + c.unreadCount),
            onSettingsTap: _openProfile,
            collapsed: _sidebarCollapsed,
            onToggleCollapse: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
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
        onChatSelected: (chat) => _selectChat(chat),
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
          title: context.l10n.chatSection,
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
          tabs: [Tab(text: context.l10n.personalTab), Tab(text: context.l10n.groupsTab)],
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
          title: context.l10n.academicSection,
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
          tabs: [Tab(text: context.l10n.personalTab), Tab(text: context.l10n.groupsTab)],
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
      return Center(
        child: Text(context.l10n.noChats, style: const TextStyle(color: AppColors.subtle)),
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
                onTap: () => _selectChat(chat),
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
                      context.l10n.search,
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
          Text(
            context.l10n.selectChat,
            style: const TextStyle(color: AppColors.subtle, fontSize: 16),
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
  final _searchFocus = FocusNode();
  String _query = '';

  bool get _showTeachers => widget.initialTab == 1;

  static const _avatarColors = [
    Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFF42A5F5), Color(0xFFEF5350),
    Color(0xFFAB47BC), Color(0xFF26C6DA), Color(0xFFEC407A), Color(0xFF66BB6A),
    Color(0xFFFFA726), Color(0xFF8D6E63),
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
      final q = _query.toLowerCase().trim();
      list = list.where((c) {
        if (c.name.toLowerCase().contains(q)) return true;
        if (c.displayName?.toLowerCase().contains(q) ?? false) return true;
        if (c.group?.toLowerCase().contains(q) ?? false) return true;
        return false;
      });
    }
    // Сортируем по ФИО/логину
    final result = list.toList()
      ..sort((a, b) => a.bestName.toLowerCase().compareTo(b.bestName.toLowerCase()));
    return result;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
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
    final primary = Theme.of(context).colorScheme.primary;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF141414) : const Color(0xFFF7F7F7),
      body: Column(
        children: [
          // ── Шапка ──────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.only(
              top: widget.embedded ? 12 : MediaQuery.of(context).padding.top + 12,
              left: 16, right: 16, bottom: 12,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1C) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 8, offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.embedded)
                      IconButton(
                        icon: Icon(Icons.arrow_back_ios_new,
                            size: 18, color: isDark ? Colors.white70 : Colors.black54),
                        onPressed: widget.onBack,
                        padding: const EdgeInsets.only(right: 8),
                        constraints: const BoxConstraints(),
                      ),
                    Expanded(
                      child: Text(
                        _showTeachers ? context.l10n.teachersTitle : context.l10n.newChatDesktop,
                        style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    // Счётчик контактов
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${filtered.length}',
                        style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Поиск ───────────────────────────────────────────────
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Поиск по имени, нику или группе...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white30 : Colors.black38, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: isDark ? Colors.white38 : Colors.black38, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: isDark ? Colors.white54 : Colors.black45, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                              _searchFocus.requestFocus();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFF0F0F0),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: primary.withValues(alpha: 0.5), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Список ─────────────────────────────────────────────────────
          Expanded(
            child: _buildContactList(filtered, isDark, primary),
          ),
        ],
      ),
    );
  }

  Widget _buildContactList(List<AppContact> filtered, bool isDark, Color primary) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_search_rounded, size: 40,
                  color: isDark ? Colors.white24 : Colors.black26),
            ),
            const SizedBox(height: 16),
            Text(
              _query.isEmpty
                  ? (_showTeachers ? context.l10n.noTeachers : context.l10n.noStudents)
                  : 'Никого не найдено',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 15, fontWeight: FontWeight.w500),
            ),
            if (_query.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Попробуй другой запрос',
                style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 13),
              ),
            ],
          ],
        ),
      );
    }

    // Группируем по первой букве ФИО/логина
    final grouped = <String, List<AppContact>>{};
    for (final c in filtered) {
      final letter = c.bestName.isNotEmpty ? c.bestName[0].toUpperCase() : '#';
      grouped.putIfAbsent(letter, () => []).add(c);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: sortedKeys.length,
      itemBuilder: (context, sectionIndex) {
        final letter = sortedKeys[sectionIndex];
        final contacts = grouped[letter]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: primary, letterSpacing: 1.0),
              ),
            ),
            ...contacts.map((c) {
              final color = _colorFor(c.name);
              final hasChat = _hasChat(c.name);
              final displayName = c.bestName;
              final hasFullName = c.displayName?.isNotEmpty == true;
              final subtitle = [
                if (hasFullName) c.name,
                if (c.group != null) c.group!,
              ].join(' · ');

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _select(c),
                    borderRadius: BorderRadius.circular(14),
                    hoverColor: primary.withValues(alpha: 0.06),
                    splashColor: primary.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        // Аватар с индикатором онлайн
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: color.withValues(alpha: 0.18),
                              child: Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: color, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                                  ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15,
                                  color: isDark ? Colors.white : Colors.black87),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              if (subtitle.isNotEmpty)
                                const SizedBox(height: 2),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white54 : Colors.black45),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasChat)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              context.l10n.openContact,
                              style: TextStyle(
                                fontSize: 12, color: primary, fontWeight: FontWeight.w600),
                            ),
                          )
                        else
                          Icon(Icons.chevron_right_rounded,
                              color: isDark ? Colors.white24 : Colors.black26, size: 20),
                      ]),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
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
      setState(() => _nameError = context.l10n.enterNameError);
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
    final base = widget.type == ChatType.group
        ? context.l10n.newGroup
        : context.l10n.newCommunityTitle;
    final title = widget.isAcademic ? '$base (${context.l10n.academicSection.toLowerCase()})' : base;
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
            child: Text(context.l10n.cancel)),
        FilledButton(
          onPressed: _submit,
          style:
              FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          child: Text(context.l10n.create),
        ),
      ],
    );
  }
}
