import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../l10n/app_localizations.dart';
import '../services/api_config.dart' show ApiConfig;
import '../services/chat_service.dart';
import 'contact_profile_screen.dart';

// ─── Экран профиля группы / сообщества (Telegram-style) ──────────────────────

class GroupProfileScreen extends StatefulWidget {
  final Chat chat;
  /// Если true — встроен в панель (desktop).
  final bool embedded;
  final VoidCallback? onBack;
  /// Имя текущего авторизованного пользователя.
  final String? currentUserName;
  /// Аватарка текущего пользователя (для строки «Вы»).
  final String? currentUserAvatarPath;
  /// Если передан — доступно редактирование (для создателей/админов).
  final ChatService? service;
  /// Вызывается при сохранении в embedded-режиме (вместо Navigator.pop).
  final ValueChanged<Chat>? onSaved;
  /// Вызывается когда пользователь хочет открыть личный чат с участником группы.
  /// Передаёт логин (name) участника.
  final ValueChanged<String>? onChatWithMember;

  const GroupProfileScreen({
    super.key,
    required this.chat,
    this.embedded = false,
    this.onBack,
    this.currentUserName,
    this.currentUserAvatarPath,
    this.service,
    this.onSaved,
    this.onChatWithMember,
  });

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  bool _imageError = false;
  bool _isEditing  = false;
  bool _isSaving   = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  String? _editAvatarPath;
  late List<ChatMember> _members;

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

  // ── Avatar helpers ─────────────────────────────────────────────────────────

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
        pageBuilder: (ctx, a, b) => _FullScreenPhoto(path: p, heroTag: _heroTag),
        transitionsBuilder: (ctx, anim, a, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85,
    );
    if (picked != null && mounted) setState(() => _editAvatarPath = picked.path);
  }

  void _showAvatarPicker() {
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
          _PickerTile(icon: Icons.camera_alt_outlined, label: context.l10n.takePhoto,
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.camera); }),
          _PickerTile(icon: Icons.photo_library_outlined, label: context.l10n.chooseGallery,
            onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.gallery); }),
          if (_editAvatarPath != null)
            _PickerTile(icon: Icons.delete_outline, label: context.l10n.deletePhoto,
              color: Colors.red,
              onTap: () { Navigator.pop(context); setState(() => _editAvatarPath = null); }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Edit mode ──────────────────────────────────────────────────────────────

  void _startEditing() => setState(() => _isEditing = true);

  void _cancelEditing() => setState(() {
    _isEditing = false;
    _nameCtrl.text = chat.name;
    _descCtrl.text = chat.description ?? '';
    _editAvatarPath = chat.avatarPath;
    _members = List.from(chat.members);
  });

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

  // ── Member management ──────────────────────────────────────────────────────

  void _openMemberProfile(ChatMember member) {
    if (member.name == 'Вы') return; // собственный профиль
    showContactProfileOverlay(
      context,
      name: member.displayName ?? member.name,
      username: member.displayName != null ? member.name : null,
      avatarPath: member.avatarPath,
      group: member.group,
      isOnline: member.isOnline,
      // Переход в личный чат через колбэк родителя.
      onChat: widget.onChatWithMember != null
          ? () => widget.onChatWithMember!(member.name)
          : null,
    );
  }

  void _showRoleDialog(ChatMember member) {
    if (member.role == MemberRole.creator) return;
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
              child: Text(member.displayName ?? member.name,
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
                ? context.l10n.removeAdmin
                : context.l10n.makeAdmin),
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
    final l = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeMemberTitle),
        content: Text(l.removeMemberDesc(member.displayName ?? member.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          TextButton(
            onPressed: () { Navigator.pop(ctx); setState(() => _members.remove(member)); },
            child: Text(l.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    final l = context.l10n;
    final title = chat.type == ChatType.community ? l.deleteCommunity : l.deleteGroup;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(l.deleteChatForever(chat.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.service!.deleteChat(chat.id);
              if (!mounted) return;
              if (widget.embedded) { widget.onBack?.call(); }
              else { Navigator.pop(context, true); }
            },
            child: Text(l.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Members ordering ───────────────────────────────────────────────────────

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
    final meEntry = ChatMember(
      name: 'Вы',
      role: myRole,
      avatarPath: widget.currentUserAvatarPath,
    );
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final isCommunity = chat.type == ChatType.community;
    final allMembers  = _allMembers;
    final memberLabel = isCommunity ? context.l10n.subscribersLabel : context.l10n.membersLabel;

    final scaffold = Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEFEFF4),
      body: CustomScrollView(
        slivers: [
          // ── Шапка ─────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
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
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
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
                  child: Text(context.l10n.save,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w600, fontSize: 15)),
                )
              else if (_canEdit)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: context.l10n.edit,
                  onPressed: _startEditing,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _buildHeaderBackground(isCommunity, context),
              // Название в collapsed состоянии
              title: Padding(
                padding: const EdgeInsets.only(right: 48),
                child: Text(
                  _isEditing
                      ? (_nameCtrl.text.isEmpty ? chat.name : _nameCtrl.text)
                      : chat.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 0, 34),
            ),
          ),

          // ── Контент ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // ── Редактирование: имя + описание ─────────────────────────
                if (_isEditing) ...[
                  _Section(isDark: isDark, children: [
                    _EditField(controller: _nameCtrl, label: context.l10n.chatNameLabel,
                        icon: Icons.edit_outlined, isDark: isDark),
                    _Divider(isDark: isDark),
                    _EditField(controller: _descCtrl, label: context.l10n.descriptionLabel,
                        icon: Icons.info_outline, maxLines: 3,
                        maxLength: 200, isDark: isDark),
                  ]),
                  const SizedBox(height: 8),
                ],

                // ── Инфо-блок (read-only) ───────────────────────────────────
                if (!_isEditing)
                  _Section(isDark: isDark, children: [
                    _InfoRow(
                      icon: isCommunity
                          ? Icons.campaign_outlined : Icons.group_outlined,
                      label: context.l10n.typeLabel,
                      value: isCommunity ? context.l10n.communityType : context.l10n.groupType,
                      isDark: isDark,
                    ),
                    if (chat.description?.isNotEmpty == true) ...[
                      _Divider(isDark: isDark),
                      _InfoRow(
                        icon: Icons.info_outline,
                        label: context.l10n.descriptionLabel,
                        value: chat.description!,
                        isDark: isDark,
                      ),
                    ],
                    if (chat.createdAt != null) ...[
                      _Divider(isDark: isDark),
                      _InfoRow(
                        icon: Icons.calendar_today_outlined,
                        label: context.l10n.createdLabel,
                        value: _formatDate(context, chat.createdAt!),
                        isDark: isDark,
                      ),
                    ],
                  ]),

                if (_isEditing) ...[
                  _Section(isDark: isDark, children: [
                    _InfoRow(
                      icon: isCommunity
                          ? Icons.campaign_outlined : Icons.group_outlined,
                      label: context.l10n.typeLabel,
                      value: isCommunity ? context.l10n.communityType : context.l10n.groupType,
                      isDark: isDark, locked: true,
                    ),
                  ]),
                  const SizedBox(height: 8),

                  _Section(isDark: isDark, children: [
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
                            isCommunity ? context.l10n.deleteCommunity : context.l10n.deleteGroup,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 15,
                                fontWeight: FontWeight.w500),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ],

                const SizedBox(height: 16),

                // ── Заголовок участников ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(
                    '$memberLabel · ${allMembers.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),

                // ── Список участников ──────────────────────────────────────
                _Section(
                  isDark: isDark,
                  padding: EdgeInsets.zero,
                  children: [
                    for (int i = 0; i < allMembers.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 72),
                          child: Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                      _MemberTile(
                        member: allMembers[i],
                        isDark: isDark,
                        isCurrentUser: allMembers[i].name == 'Вы',
                        canManage: _isEditing &&
                            allMembers[i].name != 'Вы' &&
                            allMembers[i].role != MemberRole.creator,
                        onTap: _isEditing
                            ? (allMembers[i].name != 'Вы' &&
                                    allMembers[i].role != MemberRole.creator
                                ? () => _showRoleDialog(
                                    _members.firstWhere(
                                        (m) => m.name == allMembers[i].name,
                                        orElse: () => allMembers[i]))
                                : null)
                            : allMembers[i].name != 'Вы'
                                ? () => _openMemberProfile(allMembers[i])
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
          if (_isEditing) { _cancelEditing(); }
          else { Navigator.of(context).pop(); }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: scaffold,
    );
  }

  // ── Header background ──────────────────────────────────────────────────────

  Widget _buildHeaderBackground(bool isCommunity, BuildContext context) {
    // Используем локальный non-null для type promotion
    final rawPath = _isEditing ? _editAvatarPath : chat.avatarPath;
    final primary = Theme.of(context).colorScheme.primary;

    Widget background;

    if (_hasPhoto && rawPath != null) {
      // Dart продвигает rawPath → String здесь (прямая null-проверка)
      final imgPath = rawPath; // non-null String
      // Блюр-фон + чёткий аватар по центру (как в Telegram)
      background = Stack(fit: StackFit.expand, children: [
        // Размытый фон
        _NetworkOrFileImage(
          path: imgPath,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(color: primary),
        ),
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),
        ),
        // Круглый аватар
        if (!_isEditing)
          Center(
            child: GestureDetector(
              onTap: () => _openFullPhoto(context),
              child: Hero(
                tag: _heroTag,
                child: _CirclePhoto(path: imgPath, radius: 56),
              ),
            ),
          ),
        if (_isEditing)
          Center(child: _CirclePhoto(path: imgPath, radius: 56)),
      ]);
    } else {
      // Градиент с инициалами
      background = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primary.withValues(alpha: 0.95),
              HSLColor.fromColor(primary)
                  .withLightness(
                      (HSLColor.fromColor(primary).lightness - 0.2).clamp(0.05, 0.95))
                  .toColor(),
            ],
          ),
        ),
        child: _isEditing ? null : Center(
          child: Container(
            width: 112, height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
            ),
            child: Center(
              child: Text(_initials,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 42,
                    fontWeight: FontWeight.bold, letterSpacing: 1,
                  )),
            ),
          ),
        ),
      );
    }

    // Нижний градиент для читаемости текста
    final overlay = Stack(fit: StackFit.expand, children: [
      background,
      const Positioned(
        bottom: 0, left: 0, right: 0, height: 100,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),
      ),
      // Счётчик участников (имя отображается через FlexibleSpaceBar.title)
      Positioned(
        bottom: 14, left: 16, right: 64,
        child: Text(
          '${isCommunity ? "Подписчики" : "Участники"} · ${_allMembers.length}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13,
            shadows: const [Shadow(blurRadius: 6, color: Colors.black38)],
          ),
        ),
      ),
    ]);

    if (!_isEditing) return overlay;

    return Stack(fit: StackFit.expand, children: [
      overlay,
      GestureDetector(
        onTap: _showAvatarPicker,
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.camera_alt, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(context.l10n.changePhoto,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatDate(BuildContext context, DateTime dt) {
    return context.l10n.fullDate(dt.day, dt.month, dt.year);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section container (Telegram-style card)
// ═══════════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const _Section({required this.isDark, required this.children, this.padding});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 0),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
    ),
    padding: padding,
    child: Column(children: children),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Divider
// ═══════════════════════════════════════════════════════════════════════════════

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 56),
    child: Divider(
      height: 1,
      color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Info row (read-only)
// ═══════════════════════════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool locked;

  const _InfoRow({
    required this.icon, required this.label,
    required this.value, required this.isDark, this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black45)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87)),
          ]),
        ),
        if (locked)
          Icon(Icons.lock_outline, size: 15,
              color: isDark ? Colors.white24 : Colors.black26),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Edit field
// ═══════════════════════════════════════════════════════════════════════════════

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final int? maxLength;
  final bool isDark;

  const _EditField({
    required this.controller, required this.label,
    required this.icon, required this.isDark,
    this.maxLines = 1, this.maxLength,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLines: maxLines,
    maxLength: maxLength,
    style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      filled: true,
      fillColor: Colors.transparent,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      counterStyle: const TextStyle(fontSize: 11, color: AppColors.subtle),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Member tile — Telegram-style
// ═══════════════════════════════════════════════════════════════════════════════

class _MemberTile extends StatelessWidget {
  final ChatMember member;
  final bool isDark;
  final bool isCurrentUser;
  final bool canManage;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _MemberTile({
    required this.member, required this.isDark,
    this.isCurrentUser = false, this.canManage = false,
    this.onTap, this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          // ── Аватар с индикатором онлайн ─────────────────────────────────
          SizedBox(
            width: 48, height: 48,
            child: Stack(
              children: [
                MemberAvatar(
                  member: member,
                  isCurrentUser: isCurrentUser,
                  radius: 24,
                  primaryColor: primary,
                ),
                if (member.isOnline && !isCurrentUser)
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      width: 13, height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1C1C1E)
                              : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // ── Имя + логин / статус ─────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrentUser ? context.l10n.you : (member.displayName ?? member.name),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isCurrentUser
                        ? primary
                        : isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  isCurrentUser
                      ? context.l10n.you
                      : (member.displayName != null && member.displayName != member.name
                          ? member.name
                          : (member.group ?? (member.isOnline ? context.l10n.online : ''))),
                  style: TextStyle(
                    fontSize: 13,
                    color: member.isOnline && !isCurrentUser
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.85)
                        : (isDark ? Colors.white38 : Colors.black38),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ── Правая часть: роль или кнопки управления ─────────────────────
          if (canManage) ...[
            if (member.role == MemberRole.admin)
              _RoleBadge(label: context.l10n.adminRole, color: Colors.blue),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.manage_accounts_outlined,
                    color: Colors.blue.withValues(alpha: 0.8), size: 20),
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.person_remove_outlined,
                    color: Colors.red, size: 20),
              ),
            ),
          ] else if (member.role != MemberRole.member) ...[
            _RoleBadge(
              label: member.role == MemberRole.creator ? context.l10n.creatorRole : context.l10n.adminRole,
              color: member.role == MemberRole.creator ? primary : Colors.blue,
            ),
          ],
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Member avatar — сеть / файл / инициалы
// ═══════════════════════════════════════════════════════════════════════════════

/// Публичный виджет аватарки участника — переиспользуется в других местах.
class MemberAvatar extends StatelessWidget {
  final ChatMember member;
  final bool isCurrentUser;
  final double radius;
  final Color primaryColor;

  const MemberAvatar({
    super.key,
    required this.member,
    this.isCurrentUser = false,
    this.radius = 20,
    required this.primaryColor,
  });

  static const _colors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6),
    Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF4DD0E1),
    Color(0xFFF06292), Color(0xFFAED581),
  ];

  Color _bgColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return _colors[hash % _colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final p = member.avatarPath;
    final hasNet = p != null && p.isNotEmpty && ApiConfig.isServerMediaPath(p);
    final hasFile = p != null && p.isNotEmpty && !kIsWeb && File(p).existsSync();

    if (isCurrentUser && !hasNet && !hasFile) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: primaryColor,
        child: Icon(Icons.person, color: Colors.white, size: radius * 0.9),
      );
    }

    // Dart-3 flow analysis promotes p → String inside these blocks
    // (p != null is part of hasNet/hasFile definitions)
    if (hasNet) {
      final url = ApiConfig.resolveMediaUrl(p);
      if (url != null) {
        return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(url),
          onBackgroundImageError: (_, _) {},
          backgroundColor: _bgColor(member.name),
          child: null,
        );
      }
    }

    if (hasFile) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(p)),
        backgroundColor: _bgColor(member.name),
      );
    }

    // Инициалы
    final label = isCurrentUser ? context.l10n.you : (member.displayName ?? member.name);
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    final bg = isCurrentUser ? primaryColor : _bgColor(member.name);

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg.withValues(alpha: 0.18),
      child: Text(
        initial,
        style: TextStyle(
          color: isCurrentUser ? primaryColor : bg,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.75,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Role badge
// ═══════════════════════════════════════════════════════════════════════════════

class _RoleBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _RoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Circular photo (network or file)
// ═══════════════════════════════════════════════════════════════════════════════

class _CirclePhoto extends StatelessWidget {
  final String path;
  final double radius;
  const _CirclePhoto({required this.path, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2, height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16),
        ],
      ),
      child: ClipOval(child: _NetworkOrFileImage(path: path, fit: BoxFit.cover)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Image: network or file
// ═══════════════════════════════════════════════════════════════════════════════

class _NetworkOrFileImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const _NetworkOrFileImage({required this.path, this.fit = BoxFit.cover, this.errorBuilder});

  @override
  Widget build(BuildContext context) {
    if (ApiConfig.isServerMediaPath(path)) {
      return Image.network(
        ApiConfig.resolveMediaUrl(path)!,
        fit: fit,
        errorBuilder: errorBuilder ?? (_, _, _) => const SizedBox(),
      );
    }
    if (!kIsWeb && File(path).existsSync()) {
      return Image.file(File(path), fit: fit,
          errorBuilder: errorBuilder ?? (_, _, _) => const SizedBox());
    }
    return const SizedBox();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Picker tile
// ═══════════════════════════════════════════════════════════════════════════════

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _PickerTile({required this.icon, required this.label,
      required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
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
// Full-screen photo viewer
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
            minScale: 0.5, maxScale: 6.0,
            child: Hero(
              tag: heroTag,
              child: ApiConfig.isServerMediaPath(path)
                  ? Image.network(ApiConfig.resolveMediaUrl(path)!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image, color: Colors.white38, size: 64))
                  : Image.file(File(path), fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image, color: Colors.white38, size: 64)),
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
