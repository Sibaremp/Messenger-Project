import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart' as svc;
import '../services/api_config.dart' show ApiConfig;
import '../auth_screen.dart' show AuthScreen;
import 'package:image_picker/image_picker.dart';
import '../profile_screen.dart' show ProfileAvatar, UserProfile, ProfileRole;
import '../services/sim_service.dart';
import '../services/signaling_service.dart';
import '../theme.dart' show ThemeProvider, AppThemeMode;
import '../widgets/chat_widgets.dart';
import 'chat_screen.dart';
import 'search_screen.dart';
import 'devices_screen.dart';

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
  late StreamSubscription<ChatEvent> _eventSub;

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
    // Обновляем FAB при переключении вкладок
    _academicTabCtrl.addListener(() => setState(() {}));
    _chatTabCtrl.addListener(() => setState(() {}));
    _loadChats();
    _loadAvatar();
    _loadContacts();
    _eventSub = widget.service.events.listen((event) {
      if (!mounted) return;
      _loadChats();
      // Принудительный logout, если текущий сеанс завершён удалённо.
      if (event is SessionTerminated && event.isCurrent) {
        _logout();
      }
      // Уведомления: упоминания и ответы на сообщения текущего пользователя.
      if (event is MessageReceived && !event.message.isMe) {
        final myName = widget.auth.currentUser?.name ?? '';
        final msg = event.message;

        // @упоминание (@ник или @all)
        final mentioned = msg.mentions
            .any((m) => m.username == myName || m.userId == 'all');
        if (mentioned) {
          setState(() {
            _notifications.insert(0, _AppNotification(
              type:       _NotifType.mention,
              senderName: msg.senderName ?? 'Участник',
              message:    msg.text,
              time:       msg.time,
            ));
          });
        }

        // Ответ на моё сообщение
        final replyTo = msg.replyTo;
        if (!mentioned && replyTo != null && replyTo.senderName == myName) {
          setState(() {
            _notifications.insert(0, _AppNotification(
              type:       _NotifType.reply,
              senderName: msg.senderName ?? 'Участник',
              message:    msg.text,
              time:       msg.time,
            ));
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _academicTabCtrl.dispose();
    _chatTabCtrl.dispose();
    _eventSub.cancel();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final chats = await widget.service.loadChats();
    if (mounted) setState(() => _chats = List.from(chats));
  }

  Future<void> _loadAvatar() async {
    final user = widget.auth.currentUser;
    if (user?.avatarUrl != null) {
      if (mounted) setState(() => _myAvatarPath = user!.avatarUrl);
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
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.group, color: AppColors.textLight),
              ),
              title: Text(
                  isAcademic ? 'Создать академическую группу' : 'Создать группу',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Все участники могут писать'),
              onTap: () {
                Navigator.pop(context);
                _openCreateDialog(ChatType.group, isAcademic: isAcademic);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.campaign, color: AppColors.textLight),
              ),
              title: Text(
                  isAcademic ? 'Создать академическое сообщество' : 'Создать сообщество',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Только администратор пишет'),
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
    _loadChats();
  }

  void _openCreateDialog(ChatType type, {bool isAcademic = false}) {
    showDialog(
      context: context,
      builder: (_) => _CreateChatDialog(
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
            if (mounted) {
              setState(() => _chats.add(chat));
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка: $e')),
              );
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
                builder: (_) => ChatListScreen(service: widget.service, auth: widget.auth),
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

  Widget _searchAction() => IconButton(
        icon: const Icon(Icons.search),
        onPressed: _openSearch,
      );

  Widget _avatarAction() => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _bottomIndex = 3),
          child: ProfileAvatar(avatarPath: _myAvatarPath, radius: 18),
        ),
      );

  TabBar _tabBar(TabController ctrl) => TabBar(
        controller: ctrl,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.subtle,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        tabs: const [Tab(text: 'Личные'), Tab(text: 'Группы')],
      );

  /// Каждый ребёнок — самостоятельный Scaffold, чтобы AppBar и SafeArea
  /// работали корректно для каждой вкладки.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _bottomIndex,
        children: [
          // 0 — Академический
          _buildAcademicTab(),
          // 1 — Общение
          _buildChatTab(),
          // 2 — Уведомления
          _MobileNotificationsPage(
            notifications: _notifications,
            onMarkRead: (n) => setState(() => _notifications.remove(n)),
            onMarkAllRead: () => setState(() => _notifications.clear()),
          ),
          // 3 — Профиль
          _MobileProfilePage(
            auth: widget.auth,
            onLogout: _logout,
            onAvatarChanged: _loadAvatar,
            service: widget.service,
          ),
        ],
      ),
      floatingActionButton: _showFab
          ? FloatingActionButton(
              onPressed: _onFabPressed,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: AppColors.textLight),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomIndex,
        onTap: (i) {
          setState(() {
            _bottomIndex = i;
            // Помечаем уведомления прочитанными при переходе на вкладку
            if (i == 2) {
              for (final n in _notifications) {
                n.read = true;
              }
            }
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.subtle,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.school_outlined),
            activeIcon: Icon(Icons.school),
            label: 'Академический',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Общение',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text(
                '$_unreadNotifications',
                style: const TextStyle(fontSize: 10),
              ),
              child: const Icon(Icons.notifications_none),
            ),
            activeIcon: const Icon(Icons.notifications),
            label: 'Уведомления',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicTab() {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxHeight < 400;
          return Column(
            children: [
              Material(
                elevation: 2,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, isLandscape ? 4 : 12, 4, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Академический',
                                style: TextStyle(
                                    fontSize: isLandscape ? 16 : 20,
                                    fontWeight: FontWeight.bold)),
                          ),
                          _searchAction(),
                          if (!isLandscape) _avatarAction(),
                        ],
                      ),
                    ),
                    _tabBar(_academicTabCtrl),
                  ],
                ),
              ),
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
          );
        },
      ),
    );
  }

  Widget _buildChatTab() {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = constraints.maxHeight < 400;
          return Column(
            children: [
              Material(
                elevation: 2,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, isLandscape ? 4 : 12, 4, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Общение',
                                style: TextStyle(
                                    fontSize: isLandscape ? 16 : 20,
                                    fontWeight: FontWeight.bold)),
                          ),
                          _searchAction(),
                          if (!isLandscape) _avatarAction(),
                        ],
                      ),
                    ),
                    _tabBar(_chatTabCtrl),
                  ],
                ),
              ),
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
          );
        },
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
    if (chats.isEmpty) {
      return const Center(
        child: Text('Нет чатов', style: TextStyle(color: AppColors.subtle)),
      );
    }
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        return Column(
          key: ValueKey(chat.id),
          children: [
            InkWell(
              onTap: () async {
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
                _loadChats();
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    ChatAvatar(type: chat.type, avatarPath: chat.avatarPath, chatName: chat.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  chat.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (chat.type != ChatType.direct) ...[
                                if (chat.members.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(
                                      '${chat.members.length + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.subtle,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    chat.type == ChatType.group
                                        ? 'Группа'
                                        : 'Сообщество',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
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
                                  style: const TextStyle(color: AppColors.subtle),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Правая колонка: время + бейдж непрочитанных
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatChatTime(chat.lastTime),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.subtle),
                        ),
                        if (chat.unreadCount > 0) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 20),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              chat.unreadCount > 99
                                  ? '99+'
                                  : '${chat.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
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
            Divider(height: 1, color: Colors.grey[300]),
          ],
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
          // Заголовок
          Material(
            elevation: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: const Text('Уведомления',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          // Подзаголовок
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Следите за актуальными данными преподавателей',
              style: TextStyle(fontSize: 13, color: AppColors.subtle),
            ),
          ),
          // Фильтры
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('Все', _selectedFilter == 0,
                    () => setState(() => _selectedFilter = 0)),
                const SizedBox(width: 8),
                _buildFilterChip('За сутки', _selectedFilter == 1,
                    () => setState(() => _selectedFilter = 1)),
                const Spacer(),
                if (widget.notifications.isNotEmpty)
                  TextButton.icon(
                    onPressed: _markAllRead,
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Прочитать все',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.2),
          ),
          // Список
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Нет уведомлений',
                        style: TextStyle(color: AppColors.subtle)),
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
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.done_all,
                              color: AppColors.primary),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.subtle.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.subtle,
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(_AppNotification n, bool isDark) {
    final isMention = n.type == _NotifType.mention;
    final accentColor = isMention ? AppColors.primary : Colors.teal;
    final typeIcon   = isMention ? Icons.alternate_email : Icons.reply;
    final typeLabel  = isMention ? 'Упоминание' : 'Ответ на сообщение';

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
                  'Прочитать',
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
// Мобильная страница профиля (встроена в IndexedStack)
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileProfilePage extends StatefulWidget {
  final svc.AuthService auth;
  final VoidCallback onLogout;
  final VoidCallback onAvatarChanged;

  /// ChatService для передачи в экран управления устройствами.
  final ChatService service;

  const _MobileProfilePage({
    required this.auth,
    required this.onLogout,
    required this.onAvatarChanged,
    required this.service,
  });

  @override
  State<_MobileProfilePage> createState() => _MobileProfilePageState();
}

class _MobileProfilePageState extends State<_MobileProfilePage> {
  UserProfile? _profile;
  bool _simLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    final user = widget.auth.currentUser;
    if (user == null) return;
    setState(() {
      _profile = UserProfile(
        name: user.name,
        login: user.name,
        bio: user.bio ?? '',
        avatarPath: user.avatarUrl,
        group: user.group,
        phone: user.phone,
        role: user.isTeacher ? ProfileRole.teacher : ProfileRole.student,
      );
    });
  }

  // ─── Сохранение поля на сервере ─────────────────────────────────────────────

  Future<void> _saveField({
    String? name, String? bio, String? phone, bool? clearPhone,
    String? avatarPath, bool? clearAvatar,
  }) async {
    try {
      // Если пришёл локальный путь аватарки — сначала заливаем на сервер.
      String? resolvedAvatar = avatarPath;
      if (clearAvatar != true &&
          avatarPath != null &&
          avatarPath.isNotEmpty &&
          !ApiConfig.isServerMediaPath(avatarPath)) {
        resolvedAvatar = await widget.auth.uploadAvatar(avatarPath);
      }
      await widget.auth.updateProfile(
        name: name,
        bio: bio,
        phone: clearPhone == true ? '' : phone,
        avatarUrl: clearAvatar == true ? '' : resolvedAvatar,
      );
      if (!mounted) return;
      _loadProfile();
      widget.onAvatarChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка сохранения'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ─── Редактирование текстового поля через диалог ──────────────────────────

  Future<void> _editTextField({
    required String title,
    required String current,
    required String hint,
    int maxLength = 32,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    required Future<void> Function(String value) onSave,
  }) async {
    final ctrl = TextEditingController(text: current);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20,
            MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Готово',
                  style: TextStyle(color: AppColors.primary,
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: maxLength,
            maxLines: maxLines,
            keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
            textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
            onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ]),
      ),
    );
    if (result != null && result.trim() != current.trim()) {
      await onSave(result.trim());
    }
  }

  // ─── Аватар ────────────────────────────────────────────────────────────────

  Future<void> _pickAvatar(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked != null && mounted) {
      await _saveField(avatarPath: picked.path);
    }
  }

  void _showAvatarOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.camera_alt, color: Colors.white, size: 20)),
            title: const Text('Сделать фото'),
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.camera); },
          ),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.photo_library, color: Colors.white, size: 20)),
            title: const Text('Выбрать из галереи'),
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.gallery); },
          ),
          if (_profile?.avatarPath != null)
            ListTile(
              leading: CircleAvatar(
                  backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 20)),
              title: const Text('Удалить фото', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _saveField(clearAvatar: true, avatarPath: null);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ─── Телефон из SIM ────────────────────────────────────────────────────────

  Future<void> _fillFromSim() async {
    setState(() => _simLoading = true);
    final result = await SimService.fetchSimCards();
    if (!mounted) return;
    setState(() => _simLoading = false);
    if (result.status == SimResult.success) {
      final sims = result.simCards;
      if (sims.length == 1 && sims.first.phoneNumber?.isNotEmpty == true) {
        await _saveField(phone: sims.first.phoneNumber!);
      }
    }
  }

  // ─── Управление устройствами ───────────────────────────────────────────────

  void _openDevices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DevicesScreen(
          auth: widget.auth,
          events: widget.service.events,
          onLogout: widget.onLogout,
        ),
      ),
    );
  }

  // ─── Выход ─────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Выйти', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = _profile;

    return SafeArea(
      bottom: false,
      child: p == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _buildPage(p, isDark),
    );
  }

  Widget _buildPage(UserProfile p, bool isDark) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Заголовок
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Профиль',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),

        // Шапка: аватар (нажимаемый) + имя + бейджи
        _buildHeader(p, isDark),
        const SizedBox(height: 16),

        // Тема
        _buildThemeCard(isDark),
        const SizedBox(height: 12),

        // Личные данные — каждое поле нажимаемое
        _buildEditableInfoCard(p, isDark),
        const SizedBox(height: 12),

        // Устройства
        _card(isDark: isDark,
          child: _actionRow(
            icon: Icons.devices_outlined, label: 'Управление устройствами',
            color: AppColors.primary, isDark: isDark, onTap: _openDevices,
          ),
        ),
        const SizedBox(height: 12),

        // Выйти
        _card(isDark: isDark,
          child: _actionRow(
            icon: Icons.logout, label: 'Выйти из аккаунта',
            color: Colors.red, isDark: isDark, onTap: _logout,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Шапка
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(UserProfile p, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          // Нажимаемый аватар
          GestureDetector(
            onTap: _showAvatarOptions,
            child: Stack(
              children: [
                ProfileAvatar(avatarPath: p.avatarPath, radius: 48),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
                        width: 2.5),
                    ),
                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            p.name.isNotEmpty ? p.name : 'Пользователь',
            style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(p.login, style: TextStyle(
              fontSize: 14, color: isDark ? Colors.white54 : Colors.black45)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _badge(p.roleLabel,
                  p.role == ProfileRole.teacher ? AppColors.primary : Colors.blue),
              if (p.group != null && p.group!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _badge(p.group!, isDark ? Colors.white54 : Colors.black54,
                    filled: false, isDark: isDark),
              ],
            ],
          ),
          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(p.bio, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black54)),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text, Color color,
      {bool filled = true, bool isDark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12)
            : isDark ? Colors.white.withValues(alpha: 0.08)
                     : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: filled ? color : (isDark ? Colors.white54 : Colors.black54),
      )),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Тема
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildThemeCard(bool isDark) {
    final provider = ThemeProvider.of(context);
    final current = provider.mode;
    return _card(isDark: isDark, padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.brightness_6_outlined, 'Тема оформления', isDark),
          const SizedBox(height: 14),
          Row(children: [
            _themeChip(Icons.light_mode, 'Светлая', current == AppThemeMode.light,
                isDark, () => provider.setMode(AppThemeMode.light)),
            const SizedBox(width: 8),
            _themeChip(Icons.dark_mode, 'Тёмная', current == AppThemeMode.dark,
                isDark, () => provider.setMode(AppThemeMode.dark)),
            const SizedBox(width: 8),
            _themeChip(Icons.brightness_auto, 'Авто', current == AppThemeMode.system,
                isDark, () => provider.setMode(AppThemeMode.system)),
          ]),
        ],
      ),
    );
  }

  Widget _themeChip(IconData icon, String label, bool selected, bool isDark,
      VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary
                : isDark ? Colors.white.withValues(alpha: 0.06)
                         : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary
                  : isDark ? Colors.white12 : Colors.black12),
          ),
          child: Column(children: [
            Icon(icon, size: 20,
                color: selected ? Colors.white
                    : isDark ? Colors.white54 : Colors.black45),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white
                    : isDark ? Colors.white54 : Colors.black45)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Редактируемые поля (inline‑tap)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEditableInfoCard(UserProfile p, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
          child: Text('Личные данные', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
        ),
        _card(isDark: isDark, child: Column(children: [
          // Имя — нажать для редактирования
          _editableRow(
            icon: Icons.person_outline,
            label: 'Имя',
            value: p.name.isNotEmpty ? p.name : 'Не указано',
            isEmpty: p.name.isEmpty,
            isDark: isDark,
            onTap: () => _editTextField(
              title: 'Имя',
              current: p.name,
              hint: 'Введите имя',
              maxLength: 32,
              onSave: (v) async {
                if (v.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Имя не может быть пустым'),
                    behavior: SnackBarBehavior.floating,
                  ));
                  return;
                }
                await _saveField(name: v);
              },
            ),
          ),
          _divider(isDark),

          // Логин — read-only, замочек
          _infoRow(
            icon: Icons.alternate_email,
            label: 'Логин',
            value: p.login,
            isDark: isDark,
            trailing: const Icon(Icons.lock_outline, size: 15, color: AppColors.subtle),
          ),
          _divider(isDark),

          // О себе
          _editableRow(
            icon: Icons.info_outline,
            label: 'О себе',
            value: p.bio.isNotEmpty ? p.bio : 'Не указано',
            isEmpty: p.bio.isEmpty,
            isDark: isDark,
            onTap: () => _editTextField(
              title: 'О себе',
              current: p.bio,
              hint: 'Расскажите немного о себе...',
              maxLength: 120,
              maxLines: 3,
              onSave: (v) => _saveField(bio: v),
            ),
          ),
          _divider(isDark),

          // Телефон (только через SIM)
          _readOnlyRow(
            icon: Icons.phone_outlined,
            label: 'Телефон',
            value: p.phone != null && p.phone!.isNotEmpty ? p.phone! : 'Не указан',
            isEmpty: p.phone == null || p.phone!.isEmpty,
            isDark: isDark,
            trailing: SimService.isSupported
                ? (_simLoading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : GestureDetector(
                        onTap: _fillFromSim,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.sim_card_outlined,
                              color: AppColors.primary, size: 16),
                        ),
                      ))
                : null,
          ),
          _divider(isDark),

          // Учебная группа (только чтение)
          _readOnlyRow(
            icon: Icons.school_outlined,
            label: 'Учебная группа',
            value: p.group != null && p.group!.isNotEmpty ? p.group! : 'Не выбрана',
            isEmpty: p.group == null || p.group!.isEmpty,
            isDark: isDark,
          ),
        ])),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Строка‑row
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _editableRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    bool isEmpty = false,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black45)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15,
                        color: isEmpty
                            ? (isDark ? Colors.white30 : Colors.black26)
                            : (isDark ? Colors.white : Colors.black87))),
              ],
            )),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ] else
              Icon(Icons.chevron_right, size: 18,
                  color: isDark ? Colors.white24 : Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    bool isEmpty = false,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black45)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15,
                      color: isEmpty
                          ? (isDark ? Colors.white30 : Colors.black26)
                          : (isDark ? Colors.white : Colors.black87))),
            ],
          )),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ] else
            Icon(Icons.lock_outline, size: 14,
                color: isDark ? Colors.white24 : Colors.black26),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black45)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87)),
            ],
          )),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon, required String label, required Color color,
    required bool isDark, required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 15,
              color: color == Colors.red ? Colors.red
                  : isDark ? Colors.white : Colors.black87))),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Утилиты
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _card({required bool isDark, EdgeInsets? padding, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
          blurRadius: 6, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _cardTitle(IconData icon, String label, bool isDark) {
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87)),
    ]);
  }

  Widget _divider(bool isDark) => Padding(
    padding: const EdgeInsets.only(left: 62),
    child: Divider(height: 1,
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
  );
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

  String get _title {
    final base = widget.type == ChatType.group ? 'Новая группа' : 'Новое сообщество';
    return widget.isAcademic ? '$base (академическая)' : base;
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введите название');
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
      title: Text(_title),
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
            const Text(
              'Добавить участников',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: widget.contacts.map((contact) {
                  final selected = _selectedContacts.contains(contact.name);
                  return CheckboxListTile(
                    value: selected,
                    title: Text(contact.name),
                    subtitle: contact.group != null
                        ? Text(contact.group!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.subtle))
                        : null,
                    secondary: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person,
                          color: AppColors.textLight, size: 18),
                    ),
                    activeColor: AppColors.primary,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() {
                      val == true
                          ? _selectedContacts.add(contact.name)
                          : _selectedContacts.remove(contact.name);
                    }),
                  );
                }).toList(),
              ),
            ),
            if (_selectedContacts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Выбрано: ${_selectedContacts.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Создать'),
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

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

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
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Открыть',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.primary,
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
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 11, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'В приложении',
              style: TextStyle(
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
        title: const Text('Новый чат'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Поиск по имени или номеру…',
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
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('Загружаем контакты…',
                      style: TextStyle(color: AppColors.subtle)),
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
                    const Text(
                      'Нет доступа к контактам',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Разрешите доступ в настройках, чтобы найти друзей по телефонной книге',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.subtle),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _loadDeviceContacts,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
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
          title: 'Контакты (${deviceContacts.length})',
        ),
        if (deviceContacts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('Контакты не найдены',
                  style: TextStyle(color: AppColors.subtle)),
            ),
          )
        else
          ...deviceContacts.map((dc) => _deviceContactTile(dc)),
        if (appContacts.isNotEmpty) ...[
          _SectionHeader(
            title: 'В приложении (${appContacts.length})',
          ),
          ...appContacts.map((c) => _appContactTile(c)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAppContactsOnly(List<AppContact> contacts) {
    if (contacts.isEmpty) {
      return const Center(
        child:
            Text('Нет контактов', style: TextStyle(color: AppColors.subtle)),
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
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : AppColors.primary.withValues(alpha: 0.10),
                  child: Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold),
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
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary,
            child: Text(
              contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(contact.name),
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
