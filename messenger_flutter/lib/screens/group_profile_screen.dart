import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/api_config.dart' show ApiConfig;
import '../services/chat_service.dart';

// ─── Экран профиля группы / сообщества (info + inline edit) ──────────────────

class GroupProfileScreen extends StatefulWidget {
  final Chat chat;
  /// Если true — встроен в панель (desktop).
  final bool embedded;
  final VoidCallback? onBack;
  /// Имя текущего авторизованного пользователя.
  final String? currentUserName;
  /// Если передан — доступно редактирование (для создателей/админов).
  final ChatService? service;
  /// Вызывается при сохранении в embedded-режиме (вместо Navigator.pop).
  final ValueChanged<Chat>? onSaved;

  const GroupProfileScreen({
    super.key,
    required this.chat,
    this.embedded = false,
    this.onBack,
    this.currentUserName,
    this.service,
    this.onSaved,
  });

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  // ── Display state ─────────────────────────────────────────────────────────
  bool _imageError = false;

  // ── Edit mode state ───────────────────────────────────────────────────────
  bool _isEditing = false;
  bool _isSaving  = false;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  String? _editAvatarPath;   // локальный путь нового аватара (выбранного в пикере)
  late List<ChatMember> _members;

  // ── Getters ───────────────────────────────────────────────────────────────
  Chat get chat => widget.chat;
  bool get embedded => widget.embedded;

  bool get _canEdit {
    final me = widget.currentUserName;
    if (me == null || me.isEmpty || widget.service == null) return false;
    return chat.isCreatorOrAdmin(me);
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: chat.name);
    _descCtrl = TextEditingController(text: chat.description ?? '');
    _editAvatarPath = chat.avatarPath;
    _members = List.from(chat.members);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GroupProfileScreen old) {
    super.didUpdateWidget(old);
    if (old.chat.avatarPath != widget.chat.avatarPath) {
      setState(() => _imageError = false);
    }
  }

  // ── Photo helpers ─────────────────────────────────────────────────────────

  bool get _hasPhoto {
    if (_imageError) return false;
    final p = _isEditing ? _editAvatarPath : chat.avatarPath;
    if (p == null || p.isEmpty) return false;
    if (ApiConfig.isServerMediaPath(p)) return true;
    if (kIsWeb) return false;
    return File(p).existsSync();
  }

  String get _heroTag => 'group_photo_${chat.id}';

  void _openFullPhoto(BuildContext context) {
    final p = _isEditing ? _editAvatarPath : chat.avatarPath;
    if (p == null || p.isEmpty) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, a, b) =>
            _FullScreenPhoto(path: p, heroTag: _heroTag),
        transitionsBuilder: (ctx, anim, a, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _editAvatarPath = picked.path);
    }
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          _PickerTile(
            icon: Icons.camera_alt_outlined, label: 'Сделать фото',
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.camera); },
          ),
          _PickerTile(
            icon: Icons.photo_library_outlined, label: 'Выбрать из галереи',
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.gallery); },
          ),
          if (_editAvatarPath != null)
            _PickerTile(
              icon: Icons.delete_outline, label: 'Удалить фото',
              color: Colors.red,
              onTap: () { Navigator.pop(context); setState(() => _editAvatarPath = null); },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Edit mode controls ────────────────────────────────────────────────────

  void _startEditing() => setState(() => _isEditing = true);

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _nameCtrl.text = chat.name;
      _descCtrl.text = chat.description ?? '';
      _editAvatarPath = chat.avatarPath;
      _members = List.from(chat.members);
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _isSaving = true);
    final updated = chat.copyWith(
      name: name,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      avatarPath: _editAvatarPath,
      members: _members,
    );
    if (!mounted) return;
    setState(() { _isSaving = false; _isEditing = false; });
    if (widget.embedded && widget.onSaved != null) {
      widget.onSaved!(updated);
    } else {
      Navigator.pop(context, updated);
    }
  }

  // ── Member management ─────────────────────────────────────────────────────

  void _showRoleDialog(ChatMember member) {
    if (member.role == MemberRole.creator) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(member.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: (member.role == MemberRole.admin
                  ? Colors.orange : Colors.blue).withValues(alpha: 0.12),
              child: Icon(
                member.role == MemberRole.admin
                    ? Icons.person_remove_outlined
                    : Icons.admin_panel_settings_outlined,
                color: member.role == MemberRole.admin ? Colors.orange : Colors.blue,
                size: 20,
              ),
            ),
            title: Text(member.role == MemberRole.admin
                ? 'Снять роль администратора'
                : 'Назначить администратором'),
            onTap: () {
              Navigator.pop(context);
              final newRole = member.role == MemberRole.admin
                  ? MemberRole.member : MemberRole.admin;
              setState(() {
                final idx = _members.indexOf(member);
                if (idx != -1) _members[idx] = member.copyWith(role: newRole);
              });
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _confirmRemove(ChatMember member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('«${member.name}» будет исключён из чата.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _members.remove(member));
            },
            child: const Text('Удалить',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    final label = chat.type == ChatType.community ? 'сообщество' : 'группу';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить $label?'),
        content: Text('«${chat.name}» будет удалено навсегда.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.service!.deleteChat(chat.id);
              if (!mounted) return;
              if (widget.embedded) {
                widget.onBack?.call();
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Удалить',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Member list helpers ───────────────────────────────────────────────────

  static const _memberColors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6),
    Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF4DD0E1),
    Color(0xFFF06292), Color(0xFFAED581),
  ];

  Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return _memberColors[hash % _memberColors.length];
  }

  List<ChatMember> get _allMembers {
    final me = widget.currentUserName;
    MemberRole myRole = MemberRole.member;
    if (me != null && me.isNotEmpty) {
      if (chat.isCreatorOrAdmin(me)) {
        myRole = MemberRole.creator;
      } else if (_members.any((m) => m.name == me)) {
        myRole = _members.firstWhere((m) => m.name == me).role;
      }
    }
    final others = me != null && me.isNotEmpty
        ? _members.where((m) => m.name != me).toList()
        : List<ChatMember>.from(_members);
    others.sort((a, b) {
      const order = {MemberRole.creator: 0, MemberRole.admin: 1, MemberRole.member: 2};
      return (order[a.role] ?? 2).compareTo(order[b.role] ?? 2);
    });
    final meEntry = ChatMember(name: 'Вы', role: myRole);
    if (myRole == MemberRole.creator || myRole == MemberRole.admin) {
      return [meEntry, ...others];
    } else {
      final leaders = others.where((m) => m.role != MemberRole.member).toList();
      final rest    = others.where((m) => m.role == MemberRole.member).toList();
      return [...leaders, meEntry, ...rest];
    }
  }

  String get _initials {
    final words = chat.name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) return '${words[0][0]}${words[1][0]}'.toUpperCase();
    return chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final isCommunity = chat.type == ChatType.community;
    final allMembers  = _allMembers;
    final memberLabel = isCommunity ? 'Подписчики' : 'Участники';
    final bgColor     = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);

    final scaffold = Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ── Шапка ────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            automaticallyImplyLeading: !embedded,
            leading: embedded
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _isEditing ? _cancelEditing : widget.onBack,
                  )
                : _isEditing
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _cancelEditing,
                      )
                    : null,
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : AppColors.primary,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            actions: [
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                )
              else if (_isEditing)
                TextButton(
                  onPressed: _save,
                  child: const Text('Сохранить',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w600, fontSize: 15)),
                )
              else if (_canEdit)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: 'Редактировать',
                  onPressed: _startEditing,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 48, 14),
              title: AnimatedBuilder(
                animation: _nameCtrl,
                builder: (_, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEditing
                          ? (_nameCtrl.text.isEmpty ? chat.name : _nameCtrl.text)
                          : chat.name,
                      style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                      ),
                    ),
                    Text(
                      '$memberLabel · ${allMembers.length}',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.normal,
                        color: Colors.white.withValues(alpha: 0.8),
                        shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                      ),
                    ),
                  ],
                ),
              ),
              background: _buildHeaderBackground(isCommunity, context),
            ),
          ),

          // ── Контент ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                // ── Редактирование: название + описание ─────────────
                if (_isEditing) ...[
                  _Card(isDark: isDark, children: [
                    _EditField(
                      controller: _nameCtrl,
                      label: 'Название',
                      icon: Icons.edit_outlined,
                      isDark: isDark,
                    ),
                    _divider(isDark),
                    _EditField(
                      controller: _descCtrl,
                      label: 'Описание',
                      icon: Icons.info_outline,
                      maxLines: 3,
                      maxLength: 200,
                      isDark: isDark,
                    ),
                  ]),
                  const SizedBox(height: 12),
                ],

                // ── Инфо-блок (read-only когда не редактируем) ───────
                if (!_isEditing)
                  _Card(isDark: isDark, children: [
                    _InfoRow(
                      icon: isCommunity
                          ? Icons.campaign_outlined
                          : Icons.group_outlined,
                      label: 'Тип',
                      value: isCommunity ? 'Сообщество' : 'Группа',
                      isDark: isDark,
                    ),
                    if (chat.description?.isNotEmpty == true) ...[
                      _divider(isDark),
                      _InfoRow(
                        icon: Icons.info_outline,
                        label: 'Описание',
                        value: chat.description!,
                        isDark: isDark,
                      ),
                    ],
                    if (chat.createdAt != null) ...[
                      _divider(isDark),
                      _InfoRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Создан',
                        value: _formatDate(chat.createdAt!),
                        isDark: isDark,
                      ),
                    ],
                  ]),

                // ── Тип чата (только чтение, при редактировании) ─────
                if (_isEditing) ...[
                  _Card(isDark: isDark, children: [
                    _InfoRow(
                      icon: isCommunity
                          ? Icons.campaign_outlined
                          : Icons.group_outlined,
                      label: 'Тип',
                      value: isCommunity ? 'Сообщество' : 'Группа',
                      isDark: isDark,
                      locked: true,
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // ── Удалить ─────────────────────────────────────────
                  _Card(isDark: isDark, children: [
                    InkWell(
                      onTap: _confirmDelete,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 15),
                        child: Row(children: [
                          const Icon(Icons.delete_forever_outlined,
                              color: Colors.red, size: 22),
                          const SizedBox(width: 14),
                          Text(
                            isCommunity
                                ? 'Удалить сообщество'
                                : 'Удалить группу',
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: 15,
                                fontWeight: FontWeight.w500),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ],

                const SizedBox(height: 12),

                // ── Участники ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                  child: Text(
                    '$memberLabel · ${allMembers.length}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  ),
                ),
                _Card(
                  isDark: isDark,
                  children: [
                    for (int i = 0; i < allMembers.length; i++) ...[
                      if (i > 0) _divider(isDark),
                      _MemberRow(
                        member: allMembers[i],
                        color: _colorFor(allMembers[i].name),
                        isDark: isDark,
                        isCurrentUser: allMembers[i].name == 'Вы',
                        // Управление доступно только в режиме редактирования
                        canManage: _isEditing &&
                            allMembers[i].name != 'Вы' &&
                            allMembers[i].role != MemberRole.creator,
                        onTap: _isEditing &&
                                allMembers[i].name != 'Вы' &&
                                allMembers[i].role != MemberRole.creator
                            ? () => _showRoleDialog(
                                _members.firstWhere(
                                    (m) => m.name == allMembers[i].name,
                                    orElse: () => allMembers[i]))
                            : null,
                        onRemove: _isEditing &&
                                allMembers[i].name != 'Вы' &&
                                allMembers[i].role != MemberRole.creator
                            ? () => _confirmRemove(
                                _members.firstWhere(
                                    (m) => m.name == allMembers[i].name,
                                    orElse: () => allMembers[i]))
                            : null,
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) return scaffold;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_isEditing) {
            _cancelEditing();
          } else {
            Navigator.of(context).pop();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: scaffold,
    );
  }

  // ── Header background (avatar / placeholder) ──────────────────────────────

  Widget _buildHeaderBackground(bool isCommunity, BuildContext context) {
    final avatarPath = _isEditing ? _editAvatarPath : chat.avatarPath;
    Widget background;

    if (_hasPhoto && avatarPath != null) {
      background = GestureDetector(
        onTap: _isEditing ? null : () => _openFullPhoto(context),
        child: Hero(
          tag: _heroTag,
          child: Stack(fit: StackFit.expand, children: [
            ApiConfig.isServerMediaPath(avatarPath)
                ? Image.network(
                    ApiConfig.resolveMediaUrl(avatarPath)!,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, e, s) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _imageError = true);
                      });
                      return _buildPlaceholder();
                    },
                  )
                : Image.file(
                    File(avatarPath),
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, e, s) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _imageError = true);
                      });
                      return _buildPlaceholder();
                    },
                  ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
          ]),
        ),
      );
    } else {
      background = _buildPlaceholder();
    }

    if (!_isEditing) return background;

    // В режиме редактирования — кликабельный оверлей с иконкой камеры
    return Stack(fit: StackFit.expand, children: [
      background,
      GestureDetector(
        onTap: _showAvatarPicker,
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt, color: Colors.white, size: 40),
                SizedBox(height: 8),
                Text('Изменить фото',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.85),
            const Color(0xFF8B4000),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: Center(
        child: Container(
          width: 96, height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          child: Center(
            child: Text(_initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _divider(bool isDark) => Padding(
        padding: const EdgeInsets.only(left: 60),
        child: Divider(
          height: 1,
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      );

  String _formatDate(DateTime dt) {
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Карточка-контейнер
// ═══════════════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _Card({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Строка информации (read-only)
// ═══════════════════════════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool locked;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black45)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
          ),
          if (locked)
            Icon(Icons.lock_outline, size: 15,
                color: isDark ? Colors.white24 : Colors.black26),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Редактируемое поле
// ═══════════════════════════════════════════════════════════════════════════════

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final int? maxLength;
  final bool isDark;

  const _EditField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: TextStyle(
          fontSize: 15, color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        counterStyle: const TextStyle(fontSize: 11, color: AppColors.subtle),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Строка участника
// ═══════════════════════════════════════════════════════════════════════════════

class _MemberRow extends StatelessWidget {
  final ChatMember member;
  final Color color;
  final bool isDark;
  final bool isCurrentUser;
  final bool canManage;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _MemberRow({
    required this.member,
    required this.color,
    required this.isDark,
    this.isCurrentUser = false,
    this.canManage = false,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isCurrentUser
                ? AppColors.primary
                : color.withValues(alpha: 0.18),
            child: isCurrentUser
                ? const Icon(Icons.person, color: Colors.white, size: 20)
                : Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isCurrentUser
                        ? AppColors.primary
                        : isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (member.role != MemberRole.member)
                  Text(
                    member.role == MemberRole.creator
                        ? 'создатель' : 'администратор',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38),
                  ),
              ],
            ),
          ),
          // Бейдж роли
          if (member.role != MemberRole.member && !canManage)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (member.role == MemberRole.creator
                        ? AppColors.primary : Colors.blue)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                member.role == MemberRole.creator ? 'Создатель' : 'Админ',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: member.role == MemberRole.creator
                        ? AppColors.primary : Colors.blue),
              ),
            ),
          // Кнопки управления (только в edit mode)
          if (canManage) ...[
            if (member.role == MemberRole.admin)
              const _SmallBadge(label: 'Админ', color: Colors.blue),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.person_remove_outlined,
                  color: Colors.red, size: 20),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onTap,
              child: Icon(Icons.manage_accounts_outlined,
                  color: Colors.blue.withValues(alpha: 0.8), size: 20),
            ),
          ],
        ]),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SmallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Строка в пикере фото
// ═══════════════════════════════════════════════════════════════════════════════

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _PickerTile(
      {required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: c.withValues(alpha: 0.12),
        child: Icon(icon, color: c, size: 20),
      ),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Просмотр фото на весь экран
// ═══════════════════════════════════════════════════════════════════════════════

class _FullScreenPhoto extends StatelessWidget {
  final String path;
  final String heroTag;
  const _FullScreenPhoto({required this.path, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6.0,
            child: Hero(
              tag: heroTag,
              child: ApiConfig.isServerMediaPath(path)
                  ? Image.network(ApiConfig.resolveMediaUrl(path)!,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, e, s) => const Icon(
                          Icons.broken_image, color: Colors.white38, size: 64))
                  : Image.file(File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, e, s) => const Icon(
                          Icons.broken_image, color: Colors.white38, size: 64)),
            ),
          ),
        ),
        SafeArea(
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ]),
    );
  }
}
