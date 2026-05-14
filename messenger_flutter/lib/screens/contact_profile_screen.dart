import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart' as svc;
import '../services/api_config.dart' show ApiConfig;
import '../utils/app_snack.dart';

// ─── Публичная точка входа: показать профиль поверх текущего экрана ───────────

void showContactProfileOverlay(
  BuildContext context, {
  required String name,
  String? username,
  String? avatarPath,
  String? description,
  String? phone,
  String? group,
  bool isOnline = false,
  svc.AuthService? auth,
  /// Вызывается после закрытия оверлея — открыть прямой чат с пользователем.
  VoidCallback? onChat,
  /// Вызывается после закрытия оверлея — начать аудио звонок.
  VoidCallback? onCall,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'contact_profile',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOut),
        ),
        child: child,
      ),
    ),
    pageBuilder: (ctx, _, _) => _ContactProfileDialog(
      name: name,
      username: username,
      avatarPath: avatarPath,
      description: description,
      phone: phone,
      group: group,
      isOnline: isOnline,
      auth: auth,
      onChat: onChat,
      onCall: onCall,
    ),
  );
}

// ─── Диалог-оверлей ────────────────────────────────────────────────────────────

class _ContactProfileDialog extends StatefulWidget {
  final String name;
  final String? username;
  final String? avatarPath;
  final String? description;
  final String? phone;
  final String? group;
  final bool isOnline;
  final svc.AuthService? auth;
  final VoidCallback? onChat;
  final VoidCallback? onCall;

  const _ContactProfileDialog({
    required this.name,
    this.username,
    this.avatarPath,
    this.description,
    this.phone,
    this.group,
    this.isOnline = false,
    this.auth,
    this.onChat,
    this.onCall,
  });

  @override
  State<_ContactProfileDialog> createState() => _ContactProfileDialogState();
}

class _ContactProfileDialogState extends State<_ContactProfileDialog> {
  bool _phoneInApp = false;
  bool _imgError   = false;
  bool _muted      = false;

  @override
  void initState() {
    super.initState();
    if (widget.phone?.isNotEmpty == true && widget.auth != null) _checkPhone();
  }

  Future<void> _checkPhone() async {
    try {
      final contacts = await widget.auth!.loadContacts();
      final normalized = _normalizePhone(widget.phone!);
      final phones = contacts
          .map((c) => c['phone'] as String?)
          .where((p) => p != null)
          .map((p) => _normalizePhone(p!))
          .toSet();
      if (mounted) setState(() => _phoneInApp = phones.contains(normalized));
    } catch (_) {}
  }

  static String _normalizePhone(String p) =>
      p.replaceAll(RegExp(r'[^\d+]'), '');

  bool get _hasPhoto {
    if (_imgError) return false;
    final p = widget.avatarPath;
    if (p == null || p.isEmpty) return false;
    if (ApiConfig.isServerMediaPath(p)) return true;
    if (kIsWeb) return false;
    return File(p).existsSync();
  }

  String get _initials {
    final w = widget.name
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (w.length >= 2) return '${w[0][0]}${w[1][0]}'.toUpperCase();
    return widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';
  }

  static const List<Color> _colors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6),
    Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF4DD0E1),
  ];

  Color get _avatarColor {
    final h = widget.name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _colors[h % _colors.length];
  }

  String get _heroTag => 'contact_photo_overlay_${widget.name}';

  void _openFullPhoto() {
    if (!_hasPhoto) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, a, _) =>
            _FullScreenPhoto(path: widget.avatarPath!, heroTag: _heroTag),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _toggleMute() => setState(() => _muted = !_muted);

  /// Закрывает оверлей и сразу переходит в чат.
  void _handleChat() {
    final cb = widget.onChat;
    Navigator.of(context).pop();
    cb?.call();
  }

  /// Закрывает оверлей и сразу начинает звонок.
  void _handleCall() {
    final cb = widget.onCall;
    if (cb == null) {
      // Нет прямого чата — показываем подсказку
            AppSnack.info(context, 'Откройте личный чат для звонка');
      return;
    }
    Navigator.of(context).pop();
    cb();
  }

  void _handleBlock() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Заблокировать ${widget.name}?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Пользователь не сможет отправлять вам сообщения.',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              Navigator.of(context).pop(); // закрыть оверлей
            },
            child: const Text(
              'Заблокировать',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final bg      = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final screenH = MediaQuery.of(context).size.height;

    final hasDesc  = widget.description?.isNotEmpty == true;
    final hasPhone = widget.phone?.isNotEmpty == true;
    final hasGroup = widget.group?.isNotEmpty == true;

    // Показывать ник только если он отличается от отображаемого имени
    final showUsername = widget.username?.isNotEmpty == true &&
        widget.username != widget.name;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          constraints: BoxConstraints(maxHeight: screenH * 0.9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Фиксированная шапка ─────────────────────────────────
              _buildHeader(context, isDark, primary, bg, showUsername),

              // ── Скроллируемый контент ───────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Инфо-раздел
                      if (hasPhone || hasDesc || hasGroup) ...[
                        const SizedBox(height: 8),
                        _InfoBlock(
                          isDark: isDark,
                          children: [
                            if (hasPhone) ...[
                              _InfoRow(
                                icon: Icons.phone_outlined,
                                value: widget.phone!,
                                label: 'Телефон',
                                primary: primary,
                                isDark: isDark,
                                trailing: _phoneInApp
                                    ? const _InAppBadge()
                                    : null,
                              ),
                              if (hasDesc || hasGroup)
                                _Divider(isDark: isDark, left: 52),
                            ],
                            if (hasDesc) ...[
                              _InfoRow(
                                icon: Icons.info_outline,
                                value: widget.description!,
                                label: 'О себе',
                                primary: primary,
                                isDark: isDark,
                              ),
                              if (hasGroup)
                                _Divider(isDark: isDark, left: 52),
                            ],
                            if (hasGroup)
                              _InfoRow(
                                icon: Icons.school_outlined,
                                value: widget.group!,
                                label: 'Учебная группа',
                                primary: primary,
                                isDark: isDark,
                              ),
                          ],
                        ),
                      ],

                      // Действия
                      const SizedBox(height: 8),
                      _InfoBlock(
                        isDark: isDark,
                        children: [
                          _ActionRow(
                            icon: _muted
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_outlined,
                            label: 'Уведомления',
                            primary: primary,
                            isDark: isDark,
                            trailing: Switch(
                              value: !_muted,
                              onChanged: (_) => _toggleMute(),
                              activeThumbColor: primary,
                              activeTrackColor: primary.withValues(alpha: 0.3),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            onTap: _toggleMute,
                          ),
                          _Divider(isDark: isDark, left: 52),
                          _ActionRow(
                            icon: Icons.block_outlined,
                            label: 'Заблокировать',
                            primary: Colors.red,
                            isDark: isDark,
                            textColor: Colors.red,
                            onTap: _handleBlock,
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, Color primary,
      Color bg, bool showUsername) {
    return Container(
      color: bg,
      child: Column(
        children: [
          // ── Кнопка закрыть ───────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                color: isDark ? Colors.white54 : Colors.black38,
                splashRadius: 18,
              ),
            ),
          ),

          // ── Аватар ───────────────────────────────────────────────────
          GestureDetector(
            onTap: _hasPhoto ? _openFullPhoto : null,
            child: Hero(
              tag: _heroTag,
              child: _buildAvatar(primary),
            ),
          ),
          const SizedBox(height: 10),

          // ── Имя ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // ── Ник ─────────────────────────────────────────────────────
          if (showUsername) ...[
            const SizedBox(height: 2),
            Text(
              '@${widget.username}',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],

          // ── Статус ──────────────────────────────────────────────────
          const SizedBox(height: 4),
          Text(
            widget.isOnline ? 'в сети' : 'последний раз недавно',
            style: TextStyle(
              fontSize: 13,
              color: widget.isOnline
                  ? const Color(0xFF4CAF50)
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),

          // ── Кнопки действий ─────────────────────────────────────────
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _QuickButton(
                  icon: Icons.chat_outlined,
                  label: 'Чат',
                  primary: primary,
                  isDark: isDark,
                  onTap: _handleChat,
                ),
                _QuickButton(
                  icon: _muted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  label: _muted ? 'Включить' : 'Звук',
                  primary: _muted ? Colors.grey : primary,
                  isDark: isDark,
                  onTap: _toggleMute,
                ),
                _QuickButton(
                  icon: Icons.call_outlined,
                  label: 'Звонок',
                  primary: widget.onCall != null ? primary : Colors.grey,
                  isDark: isDark,
                  onTap: _handleCall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAvatar(Color primary) {
    if (_hasPhoto) {
      final p = widget.avatarPath!;
      final isNet = ApiConfig.isServerMediaPath(p);
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
            ),
          ],
        ),
        child: ClipOval(
          child: isNet
              ? Image.network(
                  ApiConfig.resolveMediaUrl(p)!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _imgError = true);
                    });
                    return _initialsCircle(primary);
                  },
                )
              : Image.file(File(p), fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _imgError = true);
                    });
                    return _initialsCircle(primary);
                  }),
        ),
      );
    }
    return _initialsCircle(primary);
  }

  Widget _initialsCircle(Color primary) => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _avatarColor,
        ),
        child: Center(
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
}

// ─── Полноэкранный экран профиля (для embedded-режима) ────────────────────────

class ContactProfileScreen extends StatefulWidget {
  final String name;
  final String? username;
  final String? avatarPath;
  final String? description;
  final String? phone;
  /// Учебная группа собеседника.
  final String? group;
  /// Показывать зелёную точку «в сети».
  final bool isOnline;
  /// Если true — встроен в боковую панель (desktop).
  final bool embedded;
  final VoidCallback? onBack;
  final svc.AuthService? auth;

  const ContactProfileScreen({
    super.key,
    required this.name,
    this.username,
    this.avatarPath,
    this.description,
    this.phone,
    this.group,
    this.isOnline = false,
    this.embedded = false,
    this.onBack,
    this.auth,
  });

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  bool _phoneInApp = false;
  bool _imgError   = false;
  bool _muted      = false;

  @override
  void initState() {
    super.initState();
    if (widget.phone?.isNotEmpty == true && widget.auth != null) _checkPhone();
  }

  Future<void> _checkPhone() async {
    try {
      final contacts = await widget.auth!.loadContacts();
      final normalized = _normalizePhone(widget.phone!);
      final phones = contacts
          .map((c) => c['phone'] as String?)
          .where((p) => p != null)
          .map((p) => _normalizePhone(p!))
          .toSet();
      if (mounted) setState(() => _phoneInApp = phones.contains(normalized));
    } catch (_) {}
  }

  static String _normalizePhone(String p) =>
      p.replaceAll(RegExp(r'[^\d+]'), '');

  bool get _hasPhoto {
    if (_imgError) return false;
    final p = widget.avatarPath;
    if (p == null || p.isEmpty) return false;
    if (ApiConfig.isServerMediaPath(p)) return true;
    if (kIsWeb) return false;
    return File(p).existsSync();
  }

  String get _initials {
    final w = widget.name
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (w.length >= 2) return '${w[0][0]}${w[1][0]}'.toUpperCase();
    return widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';
  }

  static const List<Color> _colors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6),
    Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF4DD0E1),
  ];

  Color get _avatarColor {
    final h = widget.name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _colors[h % _colors.length];
  }

  String get _heroTag => 'contact_photo_${widget.name}';

  void _openFullPhoto() {
    if (!_hasPhoto) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, a, _) =>
            _FullScreenPhoto(path: widget.avatarPath!, heroTag: _heroTag),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _toggleMute() => setState(() => _muted = !_muted);

  void _handleBlock() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Заблокировать ${widget.name}?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Пользователь не сможет отправлять вам сообщения.',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!widget.embedded) Navigator.of(context).pop();
            },
            child: const Text(
              'Заблокировать',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final primary  = Theme.of(context).colorScheme.primary;
    final bg       = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFEFEFF4);
    final cardBg   = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final hasDesc  = widget.description?.isNotEmpty == true;
    final hasPhone = widget.phone?.isNotEmpty == true;
    final hasGroup = widget.group?.isNotEmpty == true;
    final showUsername = widget.username?.isNotEmpty == true &&
        widget.username != widget.name;

    final scaffold = Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          _buildHeader(context, isDark, primary, cardBg, showUsername),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (hasPhone || hasDesc || hasGroup) ...[
                    const SizedBox(height: 8),
                    _InfoBlock(
                      isDark: isDark,
                      children: [
                        if (hasPhone) ...[
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            value: widget.phone!,
                            label: 'Телефон',
                            primary: primary,
                            isDark: isDark,
                            trailing: _phoneInApp ? const _InAppBadge() : null,
                          ),
                          if (hasDesc || hasGroup)
                            _Divider(isDark: isDark, left: 52),
                        ],
                        if (hasDesc) ...[
                          _InfoRow(
                            icon: Icons.info_outline,
                            value: widget.description!,
                            label: 'О себе',
                            primary: primary,
                            isDark: isDark,
                          ),
                          if (hasGroup) _Divider(isDark: isDark, left: 52),
                        ],
                        if (hasGroup)
                          _InfoRow(
                            icon: Icons.school_outlined,
                            value: widget.group!,
                            label: 'Учебная группа',
                            primary: primary,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  _InfoBlock(
                    isDark: isDark,
                    children: [
                      _ActionRow(
                        icon: _muted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_outlined,
                        label: 'Уведомления',
                        primary: primary,
                        isDark: isDark,
                        trailing: Switch(
                          value: !_muted,
                          onChanged: (_) => _toggleMute(),
                          activeThumbColor: primary,
                          activeTrackColor: primary.withValues(alpha: 0.3),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        onTap: _toggleMute,
                      ),
                      _Divider(isDark: isDark, left: 52),
                      _ActionRow(
                        icon: Icons.block_outlined,
                        label: 'Заблокировать',
                        primary: Colors.red,
                        isDark: isDark,
                        textColor: Colors.red,
                        onTap: _handleBlock,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return scaffold;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: scaffold,
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, Color primary,
      Color cardBg, bool showUsername) {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      color: cardBg,
      padding: EdgeInsets.only(
          top: topPad > 0 ? topPad : (widget.embedded ? 0 : 16)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 22),
                  onPressed: widget.embedded
                      ? widget.onBack
                      : () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                if (!widget.embedded)
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _hasPhoto ? _openFullPhoto : null,
            child: Hero(
              tag: _heroTag,
              child: _buildAvatar(primary),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showUsername) ...[
            const SizedBox(height: 2),
            Text(
              '@${widget.username}',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            widget.isOnline ? 'в сети' : 'последний раз недавно',
            style: TextStyle(
              fontSize: 13,
              color: widget.isOnline
                  ? const Color(0xFF4CAF50)
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _QuickButton(
                  icon: Icons.chat_outlined,
                  label: 'Чат',
                  primary: primary,
                  isDark: isDark,
                  onTap: widget.embedded
                      ? widget.onBack
                      : () => Navigator.pop(context),
                ),
                _QuickButton(
                  icon: _muted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  label: _muted ? 'Включить' : 'Звук',
                  primary: _muted ? Colors.grey : primary,
                  isDark: isDark,
                  onTap: _toggleMute,
                ),
                _QuickButton(
                  icon: Icons.call_outlined,
                  label: 'Звонок',
                  primary: primary,
                  isDark: isDark,
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAvatar(Color primary) {
    if (_hasPhoto) {
      final p = widget.avatarPath!;
      final isNet = ApiConfig.isServerMediaPath(p);
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
            ),
          ],
        ),
        child: ClipOval(
          child: isNet
              ? Image.network(
                  ApiConfig.resolveMediaUrl(p)!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _imgError = true);
                    });
                    return _initialsCircle(primary);
                  },
                )
              : Image.file(File(p), fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _imgError = true);
                    });
                    return _initialsCircle(primary);
                  }),
        ),
      );
    }
    return _initialsCircle(primary);
  }

  Widget _initialsCircle(Color primary) => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _avatarColor,
        ),
        child: Center(
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Info block container
// ═══════════════════════════════════════════════════════════════════════════════

class _InfoBlock extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _InfoBlock({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        child: Column(children: children),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Info row: value (top, larger) + label (bottom, smaller gray)
// ═══════════════════════════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color primary;
  final bool isDark;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.value,
    required this.label,
    required this.primary,
    required this.isDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Action row (tappable, optional trailing widget)
// ═══════════════════════════════════════════════════════════════════════════════

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color primary;
  final bool isDark;
  final Color? textColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.primary,
    required this.isDark,
    this.textColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: primary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: textColor ??
                        (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
              if (trailing != null)
                trailing!
              else
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
            ],
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Quick-action button (icon + label, shown in header row)
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color primary;
  final bool isDark;
  final VoidCallback? onTap;

  const _QuickButton({
    required this.icon,
    required this.label,
    required this.primary,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: primary, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Divider helper
// ═══════════════════════════════════════════════════════════════════════════════

class _Divider extends StatelessWidget {
  final bool isDark;
  final double left;
  const _Divider({required this.isDark, this.left = 0});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: left),
        child: Divider(
          height: 1,
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// «В приложении» badge
// ═══════════════════════════════════════════════════════════════════════════════

class _InAppBadge extends StatelessWidget {
  const _InAppBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 12, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'В приложении',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full-screen photo viewer
// ═══════════════════════════════════════════════════════════════════════════════

class _FullScreenPhoto extends StatelessWidget {
  final String path;
  final String heroTag;
  const _FullScreenPhoto({required this.path, required this.heroTag});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,
              child: Hero(
                tag: heroTag,
                child: ApiConfig.isServerMediaPath(path)
                    ? Image.network(
                        ApiConfig.resolveMediaUrl(path)!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image,
                            color: Colors.white38,
                            size: 64))
                    : Image.file(File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image,
                            color: Colors.white38,
                            size: 64)),
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
