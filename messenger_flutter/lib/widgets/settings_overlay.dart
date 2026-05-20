import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_constants.dart';
import '../theme.dart' show ThemeProvider, AppThemeMode, AppThemePreset;
import '../profile_screen.dart' show ProfileAvatar;
import '../services/auth_service.dart' as svc;
import '../services/chat_service.dart' show ChatService;
import '../services/api_config.dart' show ApiConfig;
import '../services/notification_settings.dart';
import '../services/sim_service.dart';
import '../services/file_download_service.dart' show FileDownloadService;
import '../services/media_save_service.dart';
import '../screens/devices_screen.dart';
import '../utils/app_snack.dart';
import '../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the Telegram-style settings overlay above all content.
///
/// [profileOnly] — если true, открывает сразу страницу «Информация»
/// (нажатие на карточку профиля), иначе — главное меню настроек.
void showSettingsOverlay(
  BuildContext context, {
  required svc.AuthService auth,
  ChatService? service,
  VoidCallback? onAvatarChanged,
  VoidCallback? onLogout,
  bool profileOnly = false,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'settings',
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
    pageBuilder: (ctx, _, __) => _SettingsDialog(
      auth: auth,
      service: service,
      onAvatarChanged: onAvatarChanged,
      onLogout: onLogout,
      initialPage: profileOnly ? _Page.profile : _Page.main,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog shell
// ─────────────────────────────────────────────────────────────────────────────

enum _Page { main, profile, notifications, sessions, theme, storage, audioVideo, language }

class _SettingsDialog extends StatefulWidget {
  final svc.AuthService auth;
  final ChatService? service;
  final VoidCallback? onAvatarChanged;
  final VoidCallback? onLogout;
  final _Page initialPage;

  const _SettingsDialog({
    required this.auth,
    this.service,
    this.onAvatarChanged,
    this.onLogout,
    this.initialPage = _Page.main,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final List<_Page> _stack;

  @override
  void initState() {
    super.initState();
    _stack = [widget.initialPage];
  }

  _Page get _page => _stack.last;

  void _push(_Page p) => setState(() => _stack.add(p));
  void _pop() {
    if (_stack.length > 1) {
      setState(() => _stack.removeLast());
    } else {
      Navigator.of(context).pop(); // закрыть диалог если на корневой странице
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final screenH = MediaQuery.of(context).size.height;

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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _buildPage(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(bool isDark) {
    switch (_page) {
      case _Page.main:
        return _MainPage(
          key: const ValueKey(_Page.main),
          auth: widget.auth,
          onClose: () => Navigator.of(context).pop(),
          onPush: _push,
          onLogout: widget.onLogout,
        );
      case _Page.profile:
        return _ProfilePage(
          key: const ValueKey(_Page.profile),
          auth: widget.auth,
          onBack: _pop,
          onAvatarChanged: widget.onAvatarChanged,
        );
      case _Page.notifications:
        return _NotificationsPage(
          key: const ValueKey(_Page.notifications),
          onBack: _pop,
        );
      case _Page.sessions:
        return _SessionsPage(
          key: const ValueKey(_Page.sessions),
          auth: widget.auth,
          service: widget.service,
          onBack: _pop,
          onLogout: widget.onLogout ?? () {},
        );
      case _Page.theme:
        return _ThemePage(
          key: const ValueKey(_Page.theme),
          onBack: _pop,
        );
      case _Page.storage:
        return _StoragePage(
          key: const ValueKey(_Page.storage),
          onBack: _pop,
        );
      case _Page.audioVideo:
        return _AudioVideoPage(
          key: const ValueKey(_Page.audioVideo),
          onBack: _pop,
        );
      case _Page.language:
        return _LanguagePage(
          key: const ValueKey(_Page.language),
          onBack: _pop,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _PageHeader({required this.title, this.onBack, this.onClose});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 52,
      color: isDark ? const Color(0xFF222222) : const Color(0xFFF7F7F7),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: onBack,
              tooltip: context.l10n.back,
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: onClose,
              tooltip: context.l10n.close,
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.subtle.withValues(alpha: 0.7),
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? AppColors.subtle),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.subtle),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (onTap != null && trailing == null)
              const Icon(Icons.chevron_right, size: 18, color: AppColors.subtle),
          ],
        ),
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main settings page
// ─────────────────────────────────────────────────────────────────────────────

class _MainPage extends StatelessWidget {
  final svc.AuthService auth;
  final VoidCallback onClose;
  final void Function(_Page) onPush;
  final VoidCallback? onLogout;

  const _MainPage({
    super.key,
    required this.auth,
    required this.onClose,
    required this.onPush,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = ThemeProvider.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.settingsTitle, onClose: onClose),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Profile card ──────────────────────────────────────────
                InkWell(
                  onTap: () => onPush(_Page.profile),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: isDark
                        ? const Color(0xFF252525)
                        : const Color(0xFFF2F2F2),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            ProfileAvatar(
                                avatarPath: user?.avatarUrl, radius: 28),
                            Positioned(
                              right: 0, bottom: 0,
                              child: Container(
                                width: 16, height: 16,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4CAF50),
                                  shape: BoxShape.circle,
                                ),
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
                                user?.displayName ?? user?.name ?? context.l10n.profile,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (user?.bio != null && user!.bio!.isNotEmpty)
                                Text(
                                  user.bio!,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.subtle),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (user?.phone != null)
                                Text(
                                  user!.phone!,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.subtle),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18, color: AppColors.subtle),
                      ],
                    ),
                  ),
                ),

                // ── Scale slider ──────────────────────────────────────────
                _SectionLabel(context.l10n.textScaleLabel),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.text_fields,
                          size: 16, color: AppColors.subtle),
                      Expanded(
                        child: Slider(
                          value: provider.textScale,
                          min: 0.7,
                          max: 1.5,
                          divisions: 8,
                          activeColor: Theme.of(context).colorScheme.primary,
                          onChanged: (v) => provider.setTextScale(v),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${(provider.textScale * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.subtle),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Sections ──────────────────────────────────────────────
                const Divider(height: 1),
                _SettingsItem(
                  icon: Icons.notifications_outlined,
                  title: context.l10n.notifAndSounds,
                  iconColor: const Color(0xFFE91E63),
                  onTap: () => onPush(_Page.notifications),
                ),
                _SettingsItem(
                  icon: Icons.devices_outlined,
                  title: context.l10n.activeSessions,
                  subtitle: context.l10n.activeSessionsSub,
                  iconColor: const Color(0xFF2196F3),
                  onTap: () => onPush(_Page.sessions),
                ),
                _SettingsItem(
                  icon: Icons.palette_outlined,
                  title: context.l10n.appearance,
                  subtitle: context.l10n.appearanceSub,
                  iconColor: const Color(0xFF9C27B0),
                  onTap: () => onPush(_Page.theme),
                ),
                _SettingsItem(
                  icon: Icons.storage_outlined,
                  title: context.l10n.dataAndStorage,
                  subtitle: context.l10n.dataAndStorageSub,
                  iconColor: const Color(0xFF4CAF50),
                  onTap: () => onPush(_Page.storage),
                ),
                _SettingsItem(
                  icon: Icons.mic_outlined,
                  title: context.l10n.soundAndCamera,
                  subtitle: context.l10n.soundAndCameraSub,
                  iconColor: const Color(0xFFFF9800),
                  onTap: () => onPush(_Page.audioVideo),
                ),
                _SettingsItem(
                  icon: Icons.language_outlined,
                  title: context.l10n.languageTitle,
                  subtitle: context.l10n.languageSub,
                  iconColor: const Color(0xFF00BCD4),
                  onTap: () => onPush(_Page.language),
                ),

                const Divider(height: 1),
                _SettingsItem(
                  icon: Icons.logout,
                  title: context.l10n.logoutTitle,
                  iconColor: Colors.red,
                  onTap: () {
                    Navigator.of(context).pop();
                    onLogout?.call();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile info / edit page
// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePage extends StatefulWidget {
  final svc.AuthService auth;
  final VoidCallback onBack;
  final VoidCallback? onAvatarChanged;

  const _ProfilePage({
    super.key,
    required this.auth,
    required this.onBack,
    this.onAvatarChanged,
  });

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  late TextEditingController _bioCtrl;
  late TextEditingController _phoneCtrl;
  String? _avatarPath;
  bool _saving = false;
  bool _simLoading = false;

  @override
  void initState() {
    super.initState();
    final user = widget.auth.currentUser;
    _bioCtrl   = TextEditingController(text: user?.bio ?? '');
    _phoneCtrl = TextEditingController(text: user?.phone ?? '');
    _avatarPath = user?.avatarUrl;
  }

  @override
  void dispose() {
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── SIM-карта ───────────────────────────────────────────────────

  Future<void> _fillFromSim() async {
    if (_simLoading) return;
    setState(() => _simLoading = true);
    try {
      final result = await SimService.fetchSimCards();
      if (!mounted) return;
      switch (result.status) {
        case SimResult.success:
          if (result.simCards.isEmpty) {
            AppSnack.error(context, context.l10n.simCardNotFound);
          } else if (result.simCards.length == 1) {
            _applySimCard(result.simCards.first);
          } else {
            _showSimPicker(result.simCards);
          }
        case SimResult.permissionDenied:
          AppSnack.error(context, context.l10n.simPermissionDenied);
        case SimResult.permissionPermanentlyDenied:
          _showPermissionDialog();
        case SimResult.unsupported:
          AppSnack.error(context, context.l10n.simUnsupported);
        case SimResult.noSimFound:
          AppSnack.error(context, context.l10n.simCardNotFound);
        case SimResult.error:
          AppSnack.error(context, result.errorMessage ?? context.l10n.simReadError);
      }
    } finally {
      if (mounted) setState(() => _simLoading = false);
    }
  }

  void _applySimCard(SimCard card) {
    final number = card.phoneNumber;
    if (number != null && number.isNotEmpty) {
      setState(() => _phoneCtrl.text = number);
    } else {
      // На iOS номер не предоставляется — показываем оператора
      AppSnack.error(context, context.l10n.simNumberUnavailable(card.displayInfo));
    }
  }

  void _showSimPicker(List<SimCard> cards) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(context.l10n.selectSim,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            const Divider(height: 1),
            ...cards.map((card) => ListTile(
                  leading: const Icon(Icons.sim_card_outlined),
                  title: Text(card.slotLabel),
                  subtitle: Text(card.phoneNumber?.isNotEmpty == true
                      ? card.phoneNumber!
                      : card.displayInfo),
                  onTap: () {
                    Navigator.pop(ctx);
                    _applySimCard(card);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.permissionBlocked),
        content: Text(context.l10n.simPermissionBlockedDesc),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              SimService.openSettings();
            },
            child: Text(context.l10n.openSettingsBtn),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked != null && mounted) setState(() => _avatarPath = picked.path);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String? serverUrl;
      if (_avatarPath != null && !ApiConfig.isServerMediaPath(_avatarPath!)) {
        serverUrl = await widget.auth.uploadAvatar(_avatarPath!);
        _avatarPath = serverUrl;
      } else {
        serverUrl = _avatarPath;
      }
      final phone = _phoneCtrl.text.trim();
      await widget.auth.updateProfile(
        bio: _bioCtrl.text.trim(),
        avatarUrl: serverUrl,
        phone: phone.isNotEmpty ? phone : null,
      );
      widget.onAvatarChanged?.call();
      if (mounted) {
        setState(() => _saving = false);
        AppSnack.success(context, context.l10n.savedMsg);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppSnack.error(context, context.l10n.profileSaveError(e.toString()));
      }
    }
  }

  Future<void> _changeLogin() async {
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          title: Text(context.l10n.changeLogin),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: loginCtrl,
              autofocus: true,
              maxLength: 32,
              decoration: InputDecoration(labelText: context.l10n.newLoginLabel),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: context.l10n.currentPassword,
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => ss(() => obscure = !obscure),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.save)),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.auth.changeLogin(loginCtrl.text.trim(), passCtrl.text);
      if (mounted) setState(() {});
      if (mounted) {
        AppSnack.success(context, context.l10n.loginChanged);
      }
    } on svc.AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.profile, onBack: widget.onBack),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),
                // Avatar
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      ProfileAvatar(avatarPath: _avatarPath, radius: 44),
                      Positioned(
                        right: 0, bottom: 0,
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user?.displayName ?? user?.name ?? '',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.online,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF4CAF50)),
                ),

                // Bio
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(context.l10n.aboutLabel,
                              style: const TextStyle(fontSize: 13, color: AppColors.subtle)),
                          const Spacer(),
                          Text(
                            '${_bioCtrl.text.length}/70',
                            style: const TextStyle(fontSize: 12, color: AppColors.subtle),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _bioCtrl,
                        maxLength: 70,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: context.l10n.aboutHint,
                          hintStyle: TextStyle(color: AppColors.subtle),
                          border: UnderlineInputBorder(),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32),

                // Fields
                _InfoRow(
                  icon: Icons.person_outline,
                  label: context.l10n.nameLabel,
                  value: user?.displayName ?? user?.name ?? '—',
                ),
                _InfoRow(
                  icon: Icons.alternate_email,
                  label: context.l10n.username,
                  value: '@${user?.login ?? ''}',
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.subtle),
                    onPressed: _changeLogin,
                    tooltip: context.l10n.changeLogin,
                  ),
                ),
                // ── Редактируемый номер телефона ──────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.phone_outlined,
                          size: 20, color: AppColors.subtle),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.phone,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.subtle),
                            ),
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                hintText: '+7 (___) ___-__-__',
                                hintStyle:
                                    TextStyle(color: AppColors.subtle),
                                border: const UnderlineInputBorder(),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      width: 1.5),
                                ),
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.only(bottom: 6),
                              ),
                              style: TextStyle(
                                  fontSize: 15, color: textColor),
                            ),
                          ],
                        ),
                      ),
                      // ── Кнопка вставки из SIM ──────────────────────
                      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Tooltip(
                            message: context.l10n.insertFromSim,
                            child: _simLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.sim_card_outlined),
                                    color: Theme.of(context).colorScheme.primary,
                                    splashRadius: 20,
                                    onPressed: _fillFromSim,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(context.l10n.save),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.subtle)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications page
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationsPage extends StatefulWidget {
  final VoidCallback onBack;
  const _NotificationsPage({super.key, required this.onBack});

  @override
  State<_NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<_NotificationsPage> {
  final _s = NotificationSettings.instance;
  bool _sound = true, _vibration = true, _preview = true;
  bool _chats = true, _groups = true, _communities = true,
       _news = true, _calls = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _s.getSoundEnabled(), _s.getVibrationEnabled(), _s.getPreviewEnabled(),
      _s.getChatsEnabled(), _s.getGroupsEnabled(), _s.getCommunitiesEnabled(),
      _s.getNewsEnabled(), _s.getCallsEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _sound = results[0]; _vibration = results[1]; _preview = results[2];
      _chats = results[3]; _groups = results[4]; _communities = results[5];
      _news = results[6]; _calls = results[7];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _PageHeader(title: context.l10n.notifAndSounds, onBack: widget.onBack),
        Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        ),
      ]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.notifAndSounds, onBack: widget.onBack),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionLabel(context.l10n.generalSection),
                _ToggleItem(
                  icon: Icons.volume_up_outlined,
                  title: context.l10n.notifSoundLabel,
                  value: _sound,
                  onChanged: (v) { setState(() => _sound = v); _s.setSoundEnabled(v); },
                ),
                _ToggleItem(
                  icon: Icons.vibration,
                  title: context.l10n.vibrationLabel,
                  value: _vibration,
                  onChanged: (v) { setState(() => _vibration = v); _s.setVibrationEnabled(v); },
                ),
                _ToggleItem(
                  icon: Icons.preview_outlined,
                  title: context.l10n.previewLabel,
                  subtitle: context.l10n.previewSub,
                  value: _preview,
                  onChanged: (v) { setState(() => _preview = v); _s.setPreviewEnabled(v); },
                ),

                _SectionLabel(context.l10n.categoriesLabel),
                _ToggleItem(
                  icon: Icons.chat_outlined,
                  title: context.l10n.directChatsLabel,
                  value: _chats,
                  onChanged: (v) { setState(() => _chats = v); _s.setChatsEnabled(v); },
                ),
                _ToggleItem(
                  icon: Icons.group_outlined,
                  title: context.l10n.groupsLabel,
                  value: _groups,
                  onChanged: (v) { setState(() => _groups = v); _s.setGroupsEnabled(v); },
                ),
                _ToggleItem(
                  icon: Icons.campaign_outlined,
                  title: context.l10n.communitiesLabel,
                  value: _communities,
                  onChanged: (v) { setState(() => _communities = v); _s.setCommunitiesEnabled(v); },
                ),
                _ToggleItem(
                  icon: Icons.newspaper_outlined,
                  title: context.l10n.newsLabel,
                  value: _news,
                  onChanged: (v) { setState(() => _news = v); _s.setNewsEnabled(v); },
                ),

                _SectionLabel(context.l10n.callsLabel),
                _ToggleItem(
                  icon: Icons.call_outlined,
                  title: context.l10n.acceptCallsLabel,
                  subtitle: context.l10n.acceptCallsSub,
                  value: _calls,
                  onChanged: (v) { setState(() => _calls = v); _s.setCallsEnabled(v); },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active sessions page
// ─────────────────────────────────────────────────────────────────────────────

class _SessionsPage extends StatelessWidget {
  final svc.AuthService auth;
  final ChatService? service;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  const _SessionsPage({
    super.key,
    required this.auth,
    required this.service,
    required this.onBack,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    if (service == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _PageHeader(title: context.l10n.activeSessions, onBack: onBack),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(context.l10n.serviceUnavailable, style: const TextStyle(color: AppColors.subtle)),
        ),
      ]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.activeSessions, onBack: onBack),
        Flexible(
          child: DevicesScreen(
            auth: auth,
            events: service!.events,
            onLogout: onLogout,
            embedded: true,
            onBack: onBack,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme / appearance page
// ─────────────────────────────────────────────────────────────────────────────

class _ThemePage extends StatefulWidget {
  final VoidCallback onBack;
  const _ThemePage({super.key, required this.onBack});

  @override
  State<_ThemePage> createState() => _ThemePageState();
}

// ── Small card that represents one theme preset ───────────────────────────────
class _PresetCard extends StatelessWidget {
  final AppThemePreset preset;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;   // null for factory presets

  const _PresetCard({
    required this.preset,
    required this.isActive,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = preset.mode == AppThemeMode.dark ||
        (preset.mode == AppThemeMode.system &&
            Theme.of(context).brightness == Brightness.dark);
    final bg        = isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF5F5F5);
    final myBubble  = preset.myBubbleColor   ?? preset.primaryColor;
    final otherBub  = preset.otherBubbleColor ?? (isDark ? const Color(0xFF2A2A2A) : Colors.white);
    final primary   = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 90,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? primary : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? primary.withAlpha(60)
                  : Colors.black.withAlpha(18),
              blurRadius: isActive ? 8 : 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              // Background
              Container(color: bg),
              // Fake chat bubbles preview
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 40, height: 12,
                        decoration: BoxDecoration(
                          color: otherBub,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                            bottomRight: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 50, height: 12,
                        decoration: BoxDecoration(
                          color: myBubble,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                            bottomLeft: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Accent dot (primary color)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: preset.primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Name label at bottom
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
                  color: isDark
                      ? Colors.black.withAlpha(100)
                      : Colors.white.withAlpha(180),
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? primary : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Delete button (custom presets only)
              if (onDelete != null)
                Positioned(
                  top: 3, right: 3,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 11, color: Colors.white),
                    ),
                  ),
                ),
              // Active checkmark
              if (isActive)
                Positioned(
                  top: 3, left: 3,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePageState extends State<_ThemePage> {
  static const _primaryPresets = [
    Color(0xFFD4765B), Color(0xFF2196F3), Color(0xFF4CAF50), Color(0xFF9C27B0),
    Color(0xFFFF5722), Color(0xFF009688), Color(0xFFE91E63), Color(0xFF795548),
    Color(0xFF607D8B), Color(0xFFFFC107),
  ];
  static const _bubblePresets = [
    Color(0xFFD4765B), Color(0xFF2196F3), Color(0xFF4CAF50), Color(0xFF9C27B0),
    Color(0xFFFF5722), Color(0xFF009688), Color(0xFFE91E63), Color(0xFF66BB6A),
    Color(0xFF29B6F6), Color(0xFFFFCA28),
  ];
  static const _bgPresets = [
    Color(0xFFF5F5F5), Color(0xFFE8F5E9), Color(0xFFE3F2FD), Color(0xFFFCE4EC),
    Color(0xFFF3E5F5), Color(0xFFFFF8E1), Color(0xFFE0F2F1), Color(0xFFEFEBE9),
    Color(0xFF212121), Color(0xFF1A237E),
  ];
  static const _fonts = [
    'Системный', 'Roboto', 'Lato', 'Open Sans',
    'Montserrat', 'Nunito', 'Raleway', 'Source Sans Pro',
  ];

  bool _autoNight = false;
  int  _lightH = 8, _darkH = 21;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final p = ThemeProvider.of(context);
      _autoNight = p.autoNightEnabled;
      if (p.lightHour >= 0) _lightH = p.lightHour;
      if (p.darkHour  >= 0) _darkH  = p.darkHour;
    }
  }

  // ── Color picker ─────────────────────────────────────────────────────────────
  Future<Color?> _pickColor(Color current, List<Color> presets) async {
    Color picked = current;
    return showDialog<Color>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(context.l10n.colorPickerTitle, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 280,
          child: StatefulBuilder(
            builder: (_, ss) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: presets.map((c) {
                    final sel = picked.toARGB32() == c.toARGB32();
                    return GestureDetector(
                      onTap: () => ss(() => picked = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: c, shape: BoxShape.circle,
                          border: Border.all(
                            color: sel
                                ? (Theme.of(dCtx).brightness == Brightness.dark
                                    ? Colors.white : Colors.black87)
                                : Colors.transparent,
                            width: 2.5),
                          boxShadow: sel
                              ? [BoxShadow(color: c.withAlpha(120), blurRadius: 6)]
                              : null,
                        ),
                        child: sel
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: picked,
                    borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Text(
                    '#${picked.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: TextStyle(
                      color: picked.computeLuminance() > 0.5
                          ? Colors.black87 : Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, picked),
              child: Text(context.l10n.apply)),
        ],
      ),
    );
  }

  // ── Wallpaper picker ──────────────────────────────────────────────────────────
  Future<void> _pickWallpaper() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile != null && mounted) {
      await ThemeProvider.of(context).setWallpaper(xfile.path);
    }
  }

  // ── Save-as-preset dialog ─────────────────────────────────────────────────────
  Future<void> _saveAsPreset() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(context.l10n.saveTheme),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: context.l10n.themeNameHint),
          onSubmitted: (v) => Navigator.pop(dCtx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
              child: Text(context.l10n.save)),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      await ThemeProvider.of(context).saveCurrentAsPreset(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p       = ThemeProvider.of(context);
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    Widget colorTile({
      required String label,
      required Color  current,
      required List<Color> presets,
      required ValueChanged<Color> onPicked,
      VoidCallback? onReset,
    }) =>
        InkWell(
          onTap: () async {
            final c = await _pickColor(current, presets);
            if (c != null) onPicked(c);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: current, shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withAlpha(40)
                        : Colors.black.withAlpha(30),
                    width: 1.5),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
              if (onReset != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  color: AppColors.subtle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onReset,
                ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.subtle),
            ]),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.appearance, onBack: widget.onBack),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // ── Preset themes row ────────────────────────────────────
                _SectionLabel(context.l10n.themeLabel),
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      ...p.allPresets.map((preset) => _PresetCard(
                        preset:   preset,
                        isActive: p.activePresetId == preset.id,
                        onTap:    () => p.applyPreset(preset),
                        onDelete: preset.isFactory
                            ? null
                            : () => p.deleteCustomPreset(preset.id),
                      )),
                      // "+" Save current as new preset
                      GestureDetector(
                        onTap: _saveAsPreset,
                        child: Container(
                          width: 70,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withAlpha(40)
                                  : Colors.black.withAlpha(25),
                              width: 1.5),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline, size: 28, color: primary),
                              const SizedBox(height: 4),
                              Text(context.l10n.save,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 9, color: primary)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Auto night ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(context.l10n.autoDayNight,
                          style: const TextStyle(fontSize: 14))),
                    Switch(
                      value: _autoNight,
                      onChanged: (v) {
                        setState(() => _autoNight = v);
                        if (v) {
                          p.setAutoNight(lightHour: _lightH, darkHour: _darkH);
                        } else {
                          p.disableAutoNight();
                        }
                      },
                    ),
                  ]),
                ),
                if (_autoNight) ...[
                  _TimeSelector(
                    label: context.l10n.lightFrom, hour: _lightH,
                    onChanged: (h) {
                      setState(() => _lightH = h);
                      p.setAutoNight(lightHour: h, darkHour: _darkH);
                    },
                  ),
                  _TimeSelector(
                    label: context.l10n.darkFrom, hour: _darkH,
                    onChanged: (h) {
                      setState(() => _darkH = h);
                      p.setAutoNight(lightHour: _lightH, darkHour: h);
                    },
                  ),
                ],

                // ── Primary color ────────────────────────────────────────
                _SectionLabel(context.l10n.primaryColorLabel),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Wrap(
                    spacing: 10, runSpacing: 10,
                    children: [
                      ..._primaryPresets.map((c) {
                        final sel = p.primaryColor.toARGB32() == c.toARGB32();
                        return GestureDetector(
                          onTap: () => p.setPrimaryColor(c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: c, shape: BoxShape.circle,
                              border: sel
                                  ? Border.all(
                                      color: isDark ? Colors.white : Colors.black87,
                                      width: 3)
                                  : null,
                              boxShadow: sel
                                  ? [BoxShadow(color: c.withAlpha(100), blurRadius: 6)]
                                  : null,
                            ),
                            child: sel
                                ? const Icon(Icons.check, color: Colors.white, size: 18)
                                : null,
                          ),
                        );
                      }),
                      // Custom color picker
                      GestureDetector(
                        onTap: () async {
                          final c =
                              await _pickColor(p.primaryColor, _primaryPresets);
                          if (c != null) p.setPrimaryColor(c);
                        },
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const SweepGradient(colors: [
                              Colors.red, Colors.yellow, Colors.green,
                              Colors.cyan, Colors.blue, Colors.purple, Colors.red,
                            ]),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withAlpha(60)
                                  : Colors.black.withAlpha(40),
                              width: 2),
                          ),
                          child:
                              const Icon(Icons.colorize, size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Chat colors ──────────────────────────────────────────
                _SectionLabel(context.l10n.chatColorsLabel),
                colorTile(
                  label: context.l10n.chatBg,
                  current: p.chatBgColor ??
                      (isDark
                          ? const Color(0xFF121212)
                          : const Color(0xFFF5F5F5)),
                  presets: _bgPresets,
                  onPicked: (c) => p.setChatBgColor(c),
                  onReset: p.chatBgColor != null ? () => p.setChatBgColor(null) : null,
                ),
                colorTile(
                  label: context.l10n.myMessages,
                  current: p.effectiveMyBubble,
                  presets: _bubblePresets,
                  onPicked: (c) => p.setMyBubbleColor(c),
                  onReset:
                      p.myBubbleColor != null ? () => p.setMyBubbleColor(null) : null,
                ),
                colorTile(
                  label: context.l10n.theirMessages,
                  current: p.effectiveOtherBubble,
                  presets: _bubblePresets,
                  onPicked: (c) => p.setOtherBubbleColor(c),
                  onReset: p.otherBubbleColor != null
                      ? () => p.setOtherBubbleColor(null)
                      : null,
                ),
                colorTile(
                  label: context.l10n.sendButton,
                  current: p.effectiveSendButton,
                  presets: _primaryPresets,
                  onPicked: (c) => p.setSendButtonColor(c),
                  onReset: p.sendButtonColor != null
                      ? () => p.setSendButtonColor(null)
                      : null,
                ),

                // Bubble preview
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.chatBgColor ??
                          (isDark
                              ? const Color(0xFF121212)
                              : const Color(0xFFF0F0F0)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isDark
                              ? Colors.white.withAlpha(15)
                              : Colors.black.withAlpha(12)),
                    ),
                    child: Column(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: p.effectiveOtherBubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                              bottomRight: Radius.circular(12)),
                          ),
                          child: Text(context.l10n.bubblePreviewOther,
                              style: TextStyle(
                                fontSize: 13,
                                color: p.effectiveOtherBubble.computeLuminance() > 0.5
                                    ? Colors.black87
                                    : Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: p.effectiveMyBubble,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                              bottomLeft: Radius.circular(12)),
                          ),
                          child: Text(context.l10n.bubblePreviewMe,
                              style: TextStyle(
                                fontSize: 13,
                                color: p.effectiveMyBubble.computeLuminance() > 0.5
                                    ? Colors.black87
                                    : Colors.white)),
                        ),
                      ),
                    ]),
                  ),
                ),

                // ── Wallpaper ────────────────────────────────────────────
                _SectionLabel(context.l10n.chatWallpaper),
                InkWell(
                  onTap: _pickWallpaper,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    child: Row(children: [
                      Container(
                        width: 48, height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFEEEEEE),
                          image: p.wallpaperPath != null
                              ? DecorationImage(
                                  image: FileImage(File(p.wallpaperPath!)),
                                  fit: BoxFit.cover,
                                  onError: (_, __) {},
                                )
                              : null,
                        ),
                        child: p.wallpaperPath == null
                            ? const Icon(Icons.wallpaper, size: 20,
                                color: AppColors.subtle)
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(context.l10n.wallpaperPick,
                            style: const TextStyle(fontSize: 14)),
                      ),
                      if (p.wallpaperPath != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: AppColors.subtle,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => p.setWallpaper(null),
                        ),
                      const Icon(Icons.chevron_right, size: 18,
                          color: AppColors.subtle),
                    ]),
                  ),
                ),

                // ── Font ─────────────────────────────────────────────────
                _SectionLabel(context.l10n.fontLabel),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _fonts.map((f) {
                      final fv  = f == 'Системный' ? null : f;
                      final fl  = f == 'Системный' ? context.l10n.systemFont : f;
                      final sel = p.fontFamily == fv;
                      return GestureDetector(
                        onTap: () => p.setFontFamily(fv),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: sel
                                ? primary
                                : (isDark
                                    ? Colors.white.withAlpha(12)
                                    : Colors.black.withAlpha(8)),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: sel
                                    ? primary
                                    : AppColors.subtle.withValues(alpha: 0.25)),
                          ),
                          child: Text(fl,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: fv,
                                color: sel ? Colors.white : null,
                                fontWeight:
                                    sel ? FontWeight.w600 : FontWeight.normal)),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // ── Text scale ───────────────────────────────────────────
                _SectionLabel(context.l10n.textSizeLabel),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Text('А',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.subtle)),
                    Expanded(
                      child: Slider(
                        value: p.textScale,
                        min: 0.7, max: 1.5, divisions: 8,
                        label: '${(p.textScale * 100).round()}%',
                        onChanged: (v) => p.setTextScale(v),
                      ),
                    ),
                    const Text('А',
                        style:
                            TextStyle(fontSize: 20, color: AppColors.subtle)),
                  ]),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
class _TimeSelector extends StatelessWidget {
  final String label;
  final int hour;
  final ValueChanged<int> onChanged;

  const _TimeSelector({
    required this.label,
    required this.hour,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
        );
        if (t != null) onChanged(t.hour);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: 38),
            Text(label, style: const TextStyle(fontSize: 14)),
            const Spacer(),
            Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.subtle),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage page
// ─────────────────────────────────────────────────────────────────────────────

class _StoragePage extends StatefulWidget {
  final VoidCallback onBack;
  const _StoragePage({super.key, required this.onBack});

  @override
  State<_StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<_StoragePage> {
  static const _kMaxStorage = 'storage_max_mb';
  double _maxMb = 1024;

  // ── Размеры двух независимых хранилищ ────────────────────────────────────────
  /// Временный кэш: OS temp + внутренние загрузки FileDownloadService
  int _cacheBytes = 0;
  /// Сохранённые файлы: папка CaspianMessenger (пользовательские)
  int _savedBytes = 0;

  bool _loading = true;
  bool _clearingCache = false;
  bool _clearingSaved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    _maxMb = (prefs.getInt(_kMaxStorage) ?? 1024).toDouble();

    int cacheSize = 0;
    int savedSize = 0;

    if (!kIsWeb) {
      // 1. OS временная директория (аудиозаписи, системный кэш)
      try {
        final tmp = await getTemporaryDirectory();
        cacheSize += await _dirSize(tmp);
      } catch (_) {}

      // 2. Внутренние загрузки FileDownloadService → {AppDocuments}/downloads/
      try {
        final docs = await getApplicationDocumentsDirectory();
        cacheSize += await _dirSize(Directory('${docs.path}/downloads'));
      } catch (_) {}

      // 3. Папка CaspianMessenger (явно сохранённые пользователем файлы)
      try {
        savedSize = await MediaSaveService.instance.defaultFolderSizeBytes;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _cacheBytes = cacheSize;
        _savedBytes = savedSize;
        _loading = false;
      });
    }
  }

  Future<int> _dirSize(Directory dir) async {
    if (!dir.existsSync()) return 0;
    int total = 0;
    try {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  /// Очищает временный кэш приложения (OS temp + загрузки FileDownloadService).
  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      if (!kIsWeb) {
        // OS temp
        final tmp = await getTemporaryDirectory();
        await tmp.delete(recursive: true);
        await tmp.create();
        // Загрузки FileDownloadService (сбрасывает состояние стримов)
        await FileDownloadService.instance.clearAll();
      }
    } catch (_) {}
    await _load();
    if (mounted) AppSnack.info(context, context.l10n.cacheCleared);
    setState(() => _clearingCache = false);
  }

  /// Очищает папку CaspianMessenger (явно сохранённые пользователем файлы).
  Future<void> _clearSaved() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteSavedTitle),
        content: Text(context.l10n.deleteSavedDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearingSaved = true);
    try {
      await MediaSaveService.instance.clearDefaultFolder();
    } catch (_) {}
    await _load();
    if (mounted) AppSnack.info(context, context.l10n.savedFilesCleared);
    setState(() => _clearingSaved = false);
  }

  Widget _clearButton({
    required bool clearing,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: clearing ? null : onPressed,
      child: clearing
          ? SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : Text(
              context.l10n.clearBtn,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.dataAndStorage, onBack: widget.onBack),
        Flexible(
          child: _loading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Использование ──────────────────────────────────────
                      _SectionLabel(context.l10n.usageSection),

                      // Временный кэш (загрузки + OS temp)
                      _SettingsItem(
                        icon: Icons.cached_outlined,
                        title: context.l10n.tempCache,
                        subtitle: _cacheBytes == 0
                            ? context.l10n.empty
                            : _fmt(_cacheBytes),
                        trailing: _clearButton(
                          clearing: _clearingCache,
                          onPressed: _clearCache,
                        ),
                      ),

                      // Сохранённые файлы (папка CaspianMessenger)
                      _SettingsItem(
                        icon: Icons.folder_outlined,
                        title: context.l10n.savedFiles,
                        subtitle: _savedBytes == 0
                            ? context.l10n.empty
                            : context.l10n.savedFilesSub(_fmt(_savedBytes)),
                        trailing: _savedBytes > 0
                            ? _clearButton(
                                clearing: _clearingSaved,
                                onPressed: _clearSaved,
                              )
                            : null,
                      ),

                      // ── Лимит кэша ─────────────────────────────────────────
                      _SectionLabel(context.l10n.dataLimitSection),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.dataLimitMax(_maxMb.round()),
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.subtle),
                            ),
                            Slider(
                              value: _maxMb,
                              min: 128,
                              max: 8192,
                              divisions: 14,
                              activeColor:
                                  Theme.of(context).colorScheme.primary,
                              label: '${_maxMb.round()} МБ',
                              onChanged: (v) => setState(() => _maxMb = v),
                              onChangeEnd: (v) async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setInt(_kMaxStorage, v.round());
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio / Video page
// ─────────────────────────────────────────────────────────────────────────────

class _AudioVideoPage extends StatefulWidget {
  final VoidCallback onBack;
  const _AudioVideoPage({super.key, required this.onBack});

  @override
  State<_AudioVideoPage> createState() => _AudioVideoPageState();
}

class _AudioVideoPageState extends State<_AudioVideoPage> {
  static const _kMic      = 'av_mic_id';
  static const _kSpeaker  = 'av_speaker_id';
  static const _kCamera   = 'av_camera_id';

  List<_MediaDevice> _mics = [], _speakers = [], _cameras = [];
  String? _selMic, _selSpeaker, _selCamera;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _selMic     = prefs.getString(_kMic);
    _selSpeaker = prefs.getString(_kSpeaker);
    _selCamera  = prefs.getString(_kCamera);

    // Enumerate via flutter_webrtc
    try {
      final devices = await _enumerateDevices();
      if (mounted) {
        setState(() {
          _mics     = devices.where((d) => d.kind == 'audioinput').toList();
          _speakers = devices.where((d) => d.kind == 'audiooutput').toList();
          _cameras  = devices.where((d) => d.kind == 'videoinput').toList();
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_MediaDevice>> _enumerateDevices() async {
    return _rtcEnumerateDevices();
  }

  Future<List<_MediaDevice>> _rtcEnumerateDevices() async {
    try {
      final devices = await rtc.navigator.mediaDevices.enumerateDevices();
      return devices.map((d) => _MediaDevice(
        deviceId: d.deviceId,
        label: d.label.isNotEmpty ? d.label : d.deviceId,
        kind: d.kind ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(String key, String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, id);
  }

  Widget _deviceSection(
    String label, IconData icon, List<_MediaDevice> devices,
    String? selected, String prefsKey, ValueChanged<String> onSelect,
  ) {
    if (devices.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label),
        ...devices.map((d) {
          return RadioListTile<String>(
            value: d.deviceId,
            groupValue: selected ?? devices.first.deviceId,
            activeColor: Theme.of(context).colorScheme.primary,
            title: Text(d.label, style: const TextStyle(fontSize: 14)),
            dense: true,
            onChanged: (v) {
              if (v != null) {
                onSelect(v);
                _save(prefsKey, v);
              }
            },
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.soundAndCamera, onBack: widget.onBack),
        Flexible(
          child: _loading
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                  ))
              : (_mics.isEmpty && _cameras.isEmpty && _speakers.isEmpty)
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mic_off_outlined, size: 48, color: AppColors.subtle),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.micCamPermission,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.subtle, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _deviceSection(context.l10n.microphoneLabel, Icons.mic_outlined,
                              _mics, _selMic, _kMic,
                              (v) => setState(() => _selMic = v)),
                          _deviceSection(context.l10n.speakerLabel, Icons.headphones,
                              _speakers, _selSpeaker, _kSpeaker,
                              (v) => setState(() => _selSpeaker = v)),
                          _deviceSection(context.l10n.cameraLabel, Icons.videocam_outlined,
                              _cameras, _selCamera, _kCamera,
                              (v) => setState(() => _selCamera = v)),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

class _MediaDevice {
  final String deviceId, label, kind;
  const _MediaDevice({required this.deviceId, required this.label, required this.kind});
}

// ─────────────────────────────────────────────────────────────────────────────
// Language page
// ─────────────────────────────────────────────────────────────────────────────

class _LanguagePage extends StatefulWidget {
  final VoidCallback onBack;
  const _LanguagePage({super.key, required this.onBack});

  @override
  State<_LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<_LanguagePage> {
  static const _langs = [
    ('ru', 'Русский', '🇷🇺'),
    ('en', 'English', '🇬🇧'),
    ('kk', 'Қазақша', '🇰🇿'),
  ];
  String _current = 'ru';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final locale = ThemeProvider.of(context).locale;
      if (locale != null) {
        _current = locale.languageCode;
      }
    }
  }

  void _select(String code) {
    setState(() => _current = code);
    // Применяется немедленно через ThemeProvider → MaterialApp.locale
    ThemeProvider.of(context).setLocale(code);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageHeader(title: context.l10n.languageTitle, onBack: widget.onBack),
        ..._langs.map(((String, String, String) l) {
          final (code, name, flag) = l;
          return RadioListTile<String>(
            value: code,
            groupValue: _current,
            activeColor: Theme.of(context).colorScheme.primary,
            title: Row(
              children: [
                Text(flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Text(name, style: const TextStyle(fontSize: 15)),
              ],
            ),
            onChanged: (v) { if (v != null) _select(v); },
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public full-screen Settings page for mobile (mirrors desktop overlay)
// ─────────────────────────────────────────────────────────────────────────────

class MobileSettingsPage extends StatefulWidget {
  final svc.AuthService auth;
  final ChatService? service;
  final VoidCallback? onAvatarChanged;
  final VoidCallback? onLogout;

  const MobileSettingsPage({
    super.key,
    required this.auth,
    this.service,
    this.onAvatarChanged,
    this.onLogout,
  });

  /// Открывает страницу профиля поверх текущего маршрута.
  static void openProfilePage(
    BuildContext context, {
    required svc.AuthService auth,
    VoidCallback? onAvatarChanged,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          body: SafeArea(
            child: _ProfilePage(
              auth: auth,
              onBack: () => Navigator.of(ctx).pop(),
              onAvatarChanged: onAvatarChanged,
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  void _openPage(BuildContext context, _Page page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) {
          Widget body;
          switch (page) {
            case _Page.profile:
              body = _ProfilePage(
                auth: widget.auth,
                onBack: () => Navigator.of(ctx).pop(),
                onAvatarChanged: widget.onAvatarChanged,
              );
            case _Page.notifications:
              body = _NotificationsPage(onBack: () => Navigator.of(ctx).pop());
            case _Page.sessions:
              body = _SessionsPage(
                auth: widget.auth,
                service: widget.service,
                onBack: () => Navigator.of(ctx).pop(),
                onLogout: widget.onLogout ?? () {},
              );
            case _Page.theme:
              body = _ThemePage(onBack: () => Navigator.of(ctx).pop());
            case _Page.storage:
              body = _StoragePage(onBack: () => Navigator.of(ctx).pop());
            case _Page.audioVideo:
              body = _AudioVideoPage(onBack: () => Navigator.of(ctx).pop());
            case _Page.language:
              body = _LanguagePage(onBack: () => Navigator.of(ctx).pop());
            default:
              body = const SizedBox.shrink();
          }
          return Scaffold(
            body: SafeArea(child: body),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user     = widget.auth.currentUser;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final primary  = Theme.of(context).colorScheme.primary;
    final provider = ThemeProvider.of(context);
    final pageBg   = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final cardBg   = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      color: pageBg,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Шапка: лого + «Настройки» в одной строке ────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/images/logo.png', width: 32, height: 32),
                const SizedBox(width: 10),
                Text(
                  context.l10n.settingsTitle,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

          // ── Карточка профиля ──────────────────────────────────────
          InkWell(
            onTap: () => _openPage(context, _Page.profile),
            child: Container(
              color: cardBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Stack(
                    children: [
                      ProfileAvatar(avatarPath: user?.avatarUrl, radius: 30),
                      Positioned(
                        right: 0, bottom: 0,
                        child: Container(
                          width: 14, height: 14,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                          ),
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
                          user?.displayName ?? user?.name ?? context.l10n.profile,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        if (user?.bio != null && user!.bio!.isNotEmpty)
                          Text(
                            user.bio!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 13, color: AppColors.subtle),
                          ),
                        Text(
                          '@${user?.login ?? ''}',
                          style: TextStyle(fontSize: 13, color: primary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.subtle),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Масштаб текста ────────────────────────────────────────
          Container(
            color: cardBg,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF607D8B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.text_fields_rounded,
                          size: 19, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        context.l10n.textSizeLabel,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${(provider.textScale * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.subtle),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4, top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.text_fields, size: 14, color: AppColors.subtle),
                      Expanded(
                        child: Slider(
                          value: provider.textScale,
                          min: 0.7,
                          max: 1.5,
                          divisions: 8,
                          activeColor: primary,
                          onChanged: (v) => provider.setTextScale(v),
                        ),
                      ),
                      const Icon(Icons.text_fields, size: 22, color: AppColors.subtle),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Основные секции настроек ──────────────────────────────
          _MobileSettingsSection(
            cardBg: cardBg,
            isDark: isDark,
            items: [
              _MobileSettingsTile(
                icon: Icons.notifications_outlined,
                iconBg: const Color(0xFFE91E63),
                title: context.l10n.notifAndSounds,
                onTap: () => _openPage(context, _Page.notifications),
              ),
              _MobileSettingsTile(
                icon: Icons.devices_outlined,
                iconBg: const Color(0xFF2196F3),
                title: context.l10n.activeSessions,
                subtitle: context.l10n.activeSessionsSub,
                onTap: () => _openPage(context, _Page.sessions),
              ),
              _MobileSettingsTile(
                icon: Icons.palette_outlined,
                iconBg: const Color(0xFF9C27B0),
                title: context.l10n.appearance,
                subtitle: context.l10n.appearanceSub,
                onTap: () => _openPage(context, _Page.theme),
              ),
              _MobileSettingsTile(
                icon: Icons.storage_outlined,
                iconBg: const Color(0xFF4CAF50),
                title: context.l10n.dataAndStorage,
                subtitle: context.l10n.dataAndStorageSub,
                onTap: () => _openPage(context, _Page.storage),
              ),
              _MobileSettingsTile(
                icon: Icons.mic_outlined,
                iconBg: const Color(0xFFFF9800),
                title: context.l10n.soundAndCamera,
                subtitle: context.l10n.soundAndCameraSub,
                onTap: () => _openPage(context, _Page.audioVideo),
              ),
              _MobileSettingsTile(
                icon: Icons.language_outlined,
                iconBg: const Color(0xFF00BCD4),
                title: context.l10n.languageTitle,
                subtitle: context.l10n.languageSub,
                onTap: () => _openPage(context, _Page.language),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Выход ─────────────────────────────────────────────────
          _MobileSettingsSection(
            cardBg: cardBg,
            isDark: isDark,
            items: [
              _MobileSettingsTile(
                icon: Icons.logout_rounded,
                iconBg: Colors.red,
                title: context.l10n.logoutTitle,
                titleColor: Colors.red,
                showChevron: false,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(context.l10n.logoutConfirm),
                      content: Text(context.l10n.logoutQuestion),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(context.l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(context.l10n.logoutBtn,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) widget.onLogout?.call();
                },
              ),
            ],
          ),

          // ── Версия приложения ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                const Text(
                  'Caspian Messenger',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.subtle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.appVersion,
                  style: const TextStyle(fontSize: 12, color: AppColors.subtle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _MobileSettingsSection extends StatelessWidget {
  final Color cardBg;
  final bool isDark;
  final List<_MobileSettingsTile> items;

  const _MobileSettingsSection({
    required this.cardBg,
    required this.isDark,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cardBg,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 62),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MobileSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool showChevron;
  final VoidCallback? onTap;

  const _MobileSettingsTile({
    required this.icon,
    required this.iconBg,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: titleColor ??
                          (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.subtle),
                    ),
                ],
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.subtle),
          ],
        ),
      ),
    );
  }
}

// ── Брендовая плашка настроек ──────────────────────────────────────────────────

/// Небольшая иконка + "Caspian Messenger" в шапке страницы настроек.
class _SettingsBrandRow extends StatelessWidget {
  const _SettingsBrandRow();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0088CC), Color(0xFF00C8C8)],
            ),
          ),
          child: const Icon(Icons.waves_rounded, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 8),
        Text(
          'Caspian Messenger',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ],
    );
  }
}
