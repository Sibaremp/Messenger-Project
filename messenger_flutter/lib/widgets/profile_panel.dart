import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../app_constants.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart' show ThemeProvider, AppThemeMode;
import '../profile_screen.dart' show UserProfile, ProfileRole, profileFromAuth, ProfileAvatar;
import '../services/auth_service.dart' as svc;
import '../services/api_config.dart' show ApiConfig;
import '../services/chat_service.dart' show ChatService;
import '../screens/devices_screen.dart';
import '../utils/app_snack.dart';

/// Панель профиля для desktop-режима (правая панель).
/// Объединяет просмотр и редактирование в одном виде, как на макете.
/// Смена темы применяется только при нажатии «Сохранить изменения».
class ProfilePanel extends StatefulWidget {
  final VoidCallback? onAvatarChanged;
  final VoidCallback? onLogout;
  final svc.AuthService auth;

  /// ChatService используется для передачи потока событий в [DevicesScreen].
  final ChatService? service;

  /// Вызывается после выхода из аккаунта (из экрана устройств). Совпадает с [onLogout].
  final VoidCallback? onForceLogout;

  const ProfilePanel({
    super.key,
    this.onAvatarChanged,
    this.onLogout,
    required this.auth,
    this.service,
    this.onForceLogout,
  });

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  UserProfile? _profile;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _loginCtrl;
  late final TextEditingController _roleCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _bioCtrl;
  String? _avatarPath;
  bool _saving = false;

  /// Показывать вкладку устройств поверх профиля (inline, без нового экрана).
  bool _showDevices = false;

  /// Локальный выбор темы — применяется только при сохранении
  AppThemeMode? _pendingTheme;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _loginCtrl = TextEditingController();
    _roleCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _groupCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _loginCtrl.dispose();
    _roleCtrl.dispose();
    _phoneCtrl.dispose();
    _groupCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _loadProfile() {
    final profile = profileFromAuth(widget.auth.currentUser);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _nameCtrl.text = profile.name;
      _loginCtrl.text = profile.login;
      _roleCtrl.text = profile.roleLabel;
      _phoneCtrl.text = profile.phone ?? '';
      _groupCtrl.text = profile.group ?? '';
      _bioCtrl.text = profile.bio;
      _avatarPath = profile.avatarPath;
    });
    // Обновляем с сервера чтобы сбросить устаревший кэш
    widget.auth.refreshCurrentUser().then((_) {
      if (!mounted) return;
      _loadProfileLocal();
    });
  }

  void _loadProfileLocal() {
    final profile = profileFromAuth(widget.auth.currentUser);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _nameCtrl.text = profile.name;
      _loginCtrl.text = profile.login;
      _roleCtrl.text = profile.roleLabel;
      _phoneCtrl.text = profile.phone ?? '';
      _groupCtrl.text = profile.group ?? '';
      _bioCtrl.text = profile.bio;
      _avatarPath = profile.avatarPath;
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _avatarPath = picked.path);
    }
  }

  Future<void> _save() async {
    if (_profile == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    // Если пользователь выбрал новый локальный аватар — заливаем его на сервер.
    String? serverAvatarUrl;
    try {
      if (_avatarPath != null &&
          _avatarPath!.isNotEmpty &&
          !ApiConfig.isServerMediaPath(_avatarPath!)) {
        serverAvatarUrl = await widget.auth.uploadAvatar(_avatarPath!);
      } else {
        serverAvatarUrl = _avatarPath;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
            AppSnack.error(context, context.l10n.avatarUploadError(e.toString()));
      return;
    }

    final phone = _phoneCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    final updated = _profile!.copyWith(
      name: name,
      bio: bio,
      avatarPath: serverAvatarUrl,
      clearAvatar: serverAvatarUrl == null,
      phone: phone.isEmpty ? null : phone,
      clearPhone: phone.isEmpty,
    );
    await widget.auth.updateProfile(
      bio: updated.bio,
      phone: updated.phone,
      avatarUrl: updated.avatarPath,
    );
    _avatarPath = serverAvatarUrl;

    // Применить тему только при сохранении
    if (_pendingTheme != null && mounted) {
      ThemeProvider.of(context).setMode(_pendingTheme!);
    }

    if (!mounted) return;
    setState(() {
      _profile = updated;
      _saving = false;
    });
    widget.onAvatarChanged?.call();
        AppSnack.info(context, context.l10n.profileSaved);
  }

  Future<void> _changeLogin() async {
    final loginCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    bool obscure = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
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
                  onPressed: () => setSt(() => obscure = !obscure),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final newLogin = loginCtrl.text.trim();
    final password = passCtrl.text;
    if (newLogin.isEmpty || password.isEmpty) return;
    try {
      await widget.auth.changeLogin(newLogin, password);
      if (!mounted) return;
      _loadProfileLocal();
            AppSnack.success(context, context.l10n.loginChanged);
    } on svc.AuthException catch (e) {
      if (!mounted) return;
            AppSnack.info(context, 'e.message');
    } catch (_) {
      if (!mounted) return;
            AppSnack.error(context, context.l10n.loginChangeError);
    }
  }

  void _openDevices() {
    if (widget.service == null) return;
    setState(() => _showDevices = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Встроенный экран управления устройствами (поверх профиля, без нового Route)
    if (_showDevices && widget.service != null) {
      return DevicesScreen(
        auth:      widget.auth,
        events:    widget.service!.events,
        onLogout:  widget.onForceLogout ?? widget.onLogout ?? () {},
        embedded:  true,
        onBack:    () => setState(() => _showDevices = false),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldColor = isDark ? Colors.white : Colors.black87;
    final labelColor = AppColors.subtle;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.withValues(alpha: 0.3);
    final currentTheme = _pendingTheme ?? ThemeProvider.of(context).mode;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              // ── Аватарка ────────────────────────────────────────────
              GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: ProfileAvatar(avatarPath: _avatarPath, radius: 52),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Бейдж роли
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _profile!.role == ProfileRole.teacher
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _profile!.roleLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _profile!.role == ProfileRole.teacher
                        ? Theme.of(context).colorScheme.primary
                        : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Имя
              Text(
                _nameCtrl.text.isNotEmpty ? _nameCtrl.text : context.l10n.usernameLabel,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: fieldColor,
                ),
              ),
              const SizedBox(height: 32),

              // ── Секция «Личные данные» ─────────────────────────────
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.personalDataHeader,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _UnderlineField(
                label: context.l10n.nameLabel,
                controller: _nameCtrl,
                readOnly: true,
                fieldColor: fieldColor,
                labelColor: labelColor,
                dividerColor: dividerColor,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _UnderlineField(
                      label: context.l10n.loginField,
                      controller: _loginCtrl,
                      readOnly: true,
                      fieldColor: fieldColor,
                      labelColor: labelColor,
                      dividerColor: dividerColor,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        tooltip: context.l10n.changeLogin,
                        color: AppColors.subtle,
                        onPressed: _changeLogin,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _UnderlineField(
                      label: context.l10n.roleLabel,
                      controller: _roleCtrl,
                      readOnly: true,
                      fieldColor: fieldColor,
                      labelColor: labelColor,
                      dividerColor: dividerColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _UnderlineField(
                      label: context.l10n.phoneLabel,
                      controller: _phoneCtrl,
                      readOnly: true,
                      fieldColor: fieldColor,
                      labelColor: labelColor,
                      dividerColor: dividerColor,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _UnderlineField(
                      label: context.l10n.academicGroup,
                      controller: _groupCtrl,
                      readOnly: true,
                      fieldColor: fieldColor,
                      labelColor: labelColor,
                      dividerColor: dividerColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Описание / О себе ──────────────────────────────────
              _UnderlineField(
                label: context.l10n.bio,
                controller: _bioCtrl,
                hint: context.l10n.bioHint,
                fieldColor: fieldColor,
                labelColor: labelColor,
                dividerColor: dividerColor,
                maxLines: 3,
              ),
              const SizedBox(height: 40),

              // ── Настройка интерфейса ────────────────────────────────
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.interfaceSettings,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _ProfileThemeChip(
                    label: 'Light',
                    selected: currentTheme == AppThemeMode.light,
                    onTap: () => setState(() => _pendingTheme = AppThemeMode.light),
                  ),
                  const SizedBox(width: 8),
                  _ProfileThemeChip(
                    label: 'Dark',
                    selected: currentTheme == AppThemeMode.dark,
                    onTap: () => setState(() => _pendingTheme = AppThemeMode.dark),
                  ),
                  const SizedBox(width: 8),
                  _ProfileThemeChip(
                    label: 'Auto',
                    selected: currentTheme == AppThemeMode.system,
                    onTap: () => setState(() => _pendingTheme = AppThemeMode.system),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ── Кнопка сохранить ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(context.l10n.saveChangesBtn,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              // ── Управление устройствами ──────────────────────────────
              if (widget.service != null)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _openDevices,
                    icon: Icon(Icons.devices_outlined,
                        color: Theme.of(context).colorScheme.primary),
                    label: Text(
                      context.l10n.manageDevices,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).colorScheme.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // ── Выйти ───────────────────────────────────────────────
              TextButton(
                onPressed: widget.onLogout,
                child: Text(
                  context.l10n.logoutTitle,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Поле с подчёркиванием (стиль макета) ───────────────────────────────────

class _UnderlineField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool readOnly;
  final String? hint;
  final Color fieldColor;
  final Color labelColor;
  final Color dividerColor;
  final int maxLines;
  final Widget? suffixIcon;

  const _UnderlineField({
    required this.label,
    required this.controller,
    this.readOnly = false,
    this.hint,
    required this.fieldColor,
    required this.labelColor,
    required this.dividerColor,
    this.maxLines = 1,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: labelColor,
          ),
        ),
        TextField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          style: TextStyle(fontSize: 15, color: fieldColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: labelColor.withValues(alpha: 0.5)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: suffixIcon,
            border: UnderlineInputBorder(
                borderSide: BorderSide(color: dividerColor)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: dividerColor)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

// ─── Чип темы в профиле ─────────────────────────────────────────────────────

class _ProfileThemeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileThemeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.subtle.withValues(alpha: 0.3),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.subtle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
