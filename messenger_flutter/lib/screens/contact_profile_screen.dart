import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_constants.dart';
import '../services/auth_service.dart' as svc;
import '../services/api_config.dart' show ApiConfig;

// ─── Экран профиля собеседника ────────────────────────────────────────────────

class ContactProfileScreen extends StatefulWidget {
  final String name;
  final String? avatarPath;
  final String? description;
  final String? phone;
  /// Учебная группа собеседника (для студентов).
  final String? group;
  /// Если true — встроен в панель (desktop).
  final bool embedded;
  final VoidCallback? onBack;
  final svc.AuthService? auth;

  const ContactProfileScreen({
    super.key,
    required this.name,
    this.avatarPath,
    this.description,
    this.phone,
    this.group,
    this.embedded = false,
    this.onBack,
    this.auth,
  });

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  bool _phoneInApp = false;

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

  static String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^\d+]'), '');

  bool get _hasPhoto {
    final p = widget.avatarPath;
    if (p == null || p.isEmpty) return false;
    if (ApiConfig.isServerMediaPath(p)) return true;
    if (kIsWeb) return false;
    return File(p).existsSync();
  }

  String get _heroTag => 'contact_photo_${widget.name}';

  void _openFullPhoto() {
    if (!_hasPhoto) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, a, b) =>
            _FullScreenPhoto(path: widget.avatarPath!, heroTag: _heroTag),
        transitionsBuilder: (ctx, anim, a, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDesc = widget.description?.isNotEmpty == true;
    final hasPhone = widget.phone?.isNotEmpty == true;
    final hasGroup = widget.group?.isNotEmpty == true;

    final scaffold = Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          // ── Шапка с аватаром ────────────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            automaticallyImplyLeading: !widget.embedded,
            leading: widget.embedded ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
            ) : null,
            backgroundColor:
                isDark ? const Color(0xFF1E1E1E) : AppColors.primary,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(16, 0, 48, 14),
                title: Text(
                  widget.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
                background: _hasPhoto
                    ? GestureDetector(
                        onTap: _openFullPhoto,
                        child: Hero(
                          tag: _heroTag,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Размытый фон (аватар растянут и заблюрен)
                              ApiConfig.isServerMediaPath(widget.avatarPath)
                                  ? Image.network(
                                      ApiConfig.resolveMediaUrl(
                                          widget.avatarPath)!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(color: Colors.black54),
                                    )
                                  : Image.file(
                                      File(widget.avatarPath!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(color: Colors.black54),
                                    ),
                              ClipRect(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                              // Чёткий аватар по центру
                              Center(
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: ApiConfig.isServerMediaPath(widget.avatarPath)
                                        ? Image.network(
                                            ApiConfig.resolveMediaUrl(widget.avatarPath)!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.person, color: Colors.white54, size: 48),
                                          )
                                        : Image.file(
                                            File(widget.avatarPath!),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                              ),
                              // Градиент внизу для текста
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black54,
                                    ],
                                    stops: [0.5, 1.0],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              child: Icon(
                                Icons.person,
                                size: 48,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            // ── Контент ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                  // ── Действия ──────────────────────────────────
                  _Card(
                    isDark: isDark,
                    children: [
                      _ActionRow(
                        icon: Icons.chat_outlined,
                        label: 'Написать сообщение',
                        isDark: isDark,
                        // В embedded-режиме (desktop split-layout) нельзя делать
                        // Navigator.pop — это схлопнет весь внешний роут и
                        // появится чёрный экран. Закрываем панель через onBack,
                        // возвращая пользователя в открытый чат.
                        onTap: () {
                          if (widget.embedded) {
                            widget.onBack?.call();
                          } else {
                            Navigator.pop(context);
                          }
                        },
                      ),
                      _divider(isDark),
                      _ActionRow(
                        icon: Icons.notifications_outlined,
                        label: 'Уведомления',
                        isDark: isDark,
                        trailing: Text('Вкл.',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white38 : Colors.black38,
                            )),
                        onTap: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Информация ────────────────────────────────
                  if (hasDesc || hasPhone || hasGroup) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                      child: Text('Информация',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          )),
                    ),
                    _Card(
                      isDark: isDark,
                      children: [
                        if (hasDesc)
                          _InfoRow(
                            icon: Icons.info_outline,
                            label: 'О себе',
                            value: widget.description!,
                            isDark: isDark,
                          ),
                        if (hasDesc && (hasPhone || hasGroup)) _divider(isDark),
                        if (hasPhone)
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Телефон',
                            value: widget.phone!,
                            isDark: isDark,
                            trailing: _phoneInApp
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            size: 12, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text('В приложении',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                            )),
                                      ],
                                    ),
                                  )
                                : null,
                          ),
                        if (hasPhone && hasGroup) _divider(isDark),
                        if (hasGroup)
                          _InfoRow(
                            icon: Icons.school_outlined,
                            label: 'Учебная группа',
                            value: widget.group!,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ],

                  if (!hasDesc && !hasPhone && !hasGroup) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                      child: Text('Информация',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          )),
                    ),
                    _Card(
                      isDark: isDark,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 24, horizontal: 16),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 36,
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.black26),
                                const SizedBox(height: 8),
                                Text(
                                  'Дополнительная информация не указана',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
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

  Widget _divider(bool isDark) => Padding(
        padding: const EdgeInsets.only(left: 60),
        child: Divider(
          height: 1,
          color:
              isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      );
}

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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
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
                      color: isDark ? Colors.white38 : Colors.black45,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    )),
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
}

// ═══════════════════════════════════════════════════════════════════════════════

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  )),
            ),
            if (trailing != null) trailing!,
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white24 : Colors.black26),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _FullScreenPhoto extends StatelessWidget {
  final String path;
  final String heroTag;

  const _FullScreenPhoto({required this.path, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
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
                        errorBuilder: (ctx, err, st) => const Icon(
                          Icons.broken_image,
                          color: Colors.white38,
                          size: 64,
                        ),
                      )
                    : Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, st) => const Icon(
                          Icons.broken_image,
                          color: Colors.white38,
                          size: 64,
                        ),
                      ),
              ),
            ),
          ),
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
