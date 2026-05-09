import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'theme.dart' show ThemeProvider, AppThemeMode;
import 'app_constants.dart' show AppColors;
import 'package:image_picker/image_picker.dart';
import 'services/auth_service.dart' as svc;
import 'services/api_config.dart' show ApiConfig;
import 'services/sim_service.dart';

// ─── Роль пользователя ────────────────────────────────────────────────────────

enum ProfileRole {
  student,  // студент
  teacher,  // преподаватель
}

// ─── Модель профиля ───────────────────────────────────────────────────────────

class UserProfile {
  final String name;
  final String login;
  final String bio;
  final String? avatarPath; // локальный путь к файлу
  final String? group;      // учебная группа
  final String? phone;      // номер телефона для поиска
  final ProfileRole role;   // студент или преподаватель

  const UserProfile({
    required this.name,
    required this.login,
    this.bio = '',
    this.avatarPath,
    this.group,
    this.phone,
    this.role = ProfileRole.student,
  });

  UserProfile copyWith({
    String? name,
    String? login,
    String? bio,
    String? avatarPath,
    bool clearAvatar = false,
    String? group,
    bool clearGroup = false,
    String? phone,
    bool clearPhone = false,
    ProfileRole? role,
  }) {
    return UserProfile(
      name: name ?? this.name,
      login: login ?? this.login,
      bio: bio ?? this.bio,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      group: clearGroup ? null : (group ?? this.group),
      phone: clearPhone ? null : (phone ?? this.phone),
      role: role ?? this.role,
    );
  }

  /// Отображаемое название роли
  String get roleLabel => switch (role) {
    ProfileRole.student => 'Студент',
    ProfileRole.teacher => 'Преподаватель',
  };
}

/// Загружает [UserProfile] из данных текущего авторизованного пользователя.
UserProfile profileFromAuth(svc.AuthUser? user) {
  if (user == null) {
    return const UserProfile(name: '', login: '');
  }
  return UserProfile(
    name:      user.displayName,   // «Фамилия Имя Отчество» или login как fallback
    login:     user.login,         // имя аккаунта, выбранное при регистрации
    bio:       user.bio ?? '',
    avatarPath: user.avatarUrl,
    group:     user.group,
    phone:     user.phone,
    role:      user.isTeacher ? ProfileRole.teacher : ProfileRole.student,
  );
}

// ─── Экран просмотра профиля ─────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    // Profile now comes from AuthService — no async needed
    // This screen is only used in desktop mode via responsive_shell
  }

  Future<void> _openEdit() async {
    if (_profile == null) return;
    final updated = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(profile: _profile!),
      ),
    );
    if (updated != null) {
      setState(() => _profile = updated);
    }
  }

  Future<void> _logout() async {
    // Возвращаем true — вызывающий экран выполнит навигацию к AuthScreen
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Редактировать',
            onPressed: _openEdit,
          ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            // ── Шапка профиля ──────────────────────────────────────
            Container(
              width: double.infinity,
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  ProfileAvatar(
                    avatarPath: profile.avatarPath,
                    radius: 52,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.login,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.subtle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: profile.role == ProfileRole.teacher
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      profile.roleLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: profile.role == ProfileRole.teacher
                            ? AppColors.primary
                            : Colors.blue,
                      ),
                    ),
                  ),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        profile.bio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            // ── Личные данные ─────────────────────────────────────
            const _SectionLabel('Личные данные'),
            _ProfileTile(
              icon: Icons.person_outline,
              title: 'Имя',
              value: profile.name,
            ),
            _ProfileTile(
              icon: Icons.alternate_email,
              title: 'Логин',
              value: profile.login,
            ),
            _ProfileTile(
              icon: profile.role == ProfileRole.teacher
                  ? Icons.school
                  : Icons.person_outline,
              title: 'Роль',
              value: profile.roleLabel,
            ),
            if (profile.phone != null && profile.phone!.isNotEmpty)
              _ProfileTile(
                icon: Icons.phone_outlined,
                title: 'Телефон',
                value: profile.phone!,
              ),
            if (profile.group != null && profile.group!.isNotEmpty)
              _ProfileTile(
                icon: Icons.school_outlined,
                title: 'Учебная группа',
                value: profile.group!,
              ),
            if (profile.bio.isNotEmpty)
              _ProfileTile(
                icon: Icons.info_outline,
                title: 'О себе',
                value: profile.bio,
              ),
            const SizedBox(height: 8),
            // ── Настройки интерфейса ──────────────────────────────
            const _SectionLabel('Настройка интерфейса'),
            const _ThemeSwitcher(),
            const SizedBox(height: 8),
            _ProfileTile(
              icon: Icons.logout,
              title: 'Выйти из аккаунта',
              value: '',
              iconColor: Colors.red,
              titleColor: Colors.red,
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Экран редактирования профиля ────────────────────────────────────────────

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;
  final svc.AuthService? auth;

  const EditProfileScreen({super.key, required this.profile, this.auth});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;

  String? _avatarPath;
  String? _selectedGroup;
  late ProfileRole _selectedRole;
  bool _isSaving = false;
  bool _simLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController  = TextEditingController(text: widget.profile.name);
    _bioController   = TextEditingController(text: widget.profile.bio);
    _phoneController = TextEditingController(text: widget.profile.phone ?? '');
    _avatarPath  = widget.profile.avatarPath;
    _selectedGroup = widget.profile.group;
    _selectedRole = widget.profile.role;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _avatarPath = picked.path);
    }
  }

  void _showPickerOptions() {
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
                child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.photo_library, color: Colors.white, size: 20),
              ),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_avatarPath != null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEEEEEE),
                  child: Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                ),
                title: const Text('Удалить фото',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _avatarPath = null);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Получить номер из SIM ────────────────────────────────────────────────
  Future<void> _fillFromSim() async {
    setState(() => _simLoading = true);
    final result = await SimService.fetchSimCards();
    if (!mounted) return;
    setState(() => _simLoading = false);

    switch (result.status) {
      case SimResult.unsupported:
        _snack('Определение номера SIM недоступно на этой платформе');
      case SimResult.permissionDenied:
        _snack('Нет доступа к данным телефона');
      case SimResult.permissionPermanentlyDenied:
        _snack(
          'Разрешение отклонено. Откройте настройки.',
          action: SnackBarAction(label: 'Настройки', onPressed: SimService.openSettings),
        );
      case SimResult.noSimFound:
        _snack('SIM-карта не обнаружена');
      case SimResult.error:
        _snack('Ошибка: ${result.errorMessage ?? "неизвестная"}');
      case SimResult.success:
        final sims = result.simCards;
        if (sims.length == 1) {
          _applySimCard(sims.first);
        } else {
          _showSimPicker(sims);
        }
    }
  }

  void _applySimCard(SimCard sim) {
    if (sim.phoneNumber?.isNotEmpty == true) {
      _phoneController.text = sim.phoneNumber!;
      _snack('Номер получен: ${sim.phoneNumber} (${sim.displayInfo})');
    } else {
      // iOS: Apple не предоставляет номер через публичный API
      _snack('Оператор: ${sim.displayInfo}. Введите номер вручную.');
    }
  }

  void _showSimPicker(List<SimCard> sims) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Выберите SIM-карту',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...sims.map((sim) => ListTile(
              leading: const Icon(Icons.sim_card_outlined, color: AppColors.primary),
              title: Text(sim.slotLabel),
              subtitle: Text(sim.displayInfo),
              trailing: sim.phoneNumber != null
                  ? Text(sim.phoneNumber!, style: const TextStyle(fontSize: 13))
                  : const Text('номер неизвестен',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () { Navigator.pop(context); _applySimCard(sim); },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      action: action,
    ));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Имя не может быть пустым'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Если выбран новый локальный аватар — заливаем его на сервер.
    // Если аватар убран → передаём явный пустой avatarUrl для очистки.
    String? serverAvatarUrl;
    final currentAvatar = _avatarPath;
    try {
      if (currentAvatar != null &&
          currentAvatar.isNotEmpty &&
          !ApiConfig.isServerMediaPath(currentAvatar) &&
          widget.auth != null) {
        // Локальный путь — нужна загрузка
        serverAvatarUrl = await widget.auth!.uploadAvatar(currentAvatar);
      } else {
        serverAvatarUrl = currentAvatar; // либо уже серверный путь, либо null
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить аватар: $e')),
      );
      return;
    }

    final phone = _phoneController.text.trim();
    final updated = widget.profile.copyWith(
      name: name,
      bio: _bioController.text.trim(),
      avatarPath: serverAvatarUrl,
      clearAvatar: serverAvatarUrl == null,
      group: _selectedGroup,
      clearGroup: _selectedGroup == null,
      phone: phone.isEmpty ? null : phone,
      clearPhone: phone.isEmpty,
      role: _selectedRole,
    );

    if (widget.auth != null) {
      await widget.auth!.updateProfile(
        name: updated.name,
        bio: updated.bio,
        phone: updated.phone,
        avatarUrl: updated.avatarPath,
      );
    }

    if (!mounted) return;
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать профиль'),
        actions: [
          _isSaving
              ? const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          )
              : TextButton(
            onPressed: _save,
            child: const Text(
              'Сохранить',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // ── Аватарка ──────────────────────────────────────────────
            Center(
              child: Stack(
                children: [
                  ProfileAvatar(avatarPath: _avatarPath, radius: 52),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _showPickerOptions,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border:
                          Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ── Роль ─────────────────────────────────────────────────
            _RoleSelector(
              value: _selectedRole,
              onChanged: (r) => setState(() => _selectedRole = r),
            ),
            const SizedBox(height: 16),
            // ── Поля ──────────────────────────────────────────────────
            _EditField(
              controller: _nameController,
              label: 'Имя',
              icon: Icons.person_outline,
              maxLength: 32,
            ),
            const SizedBox(height: 16),
            _EditField(
              controller: _bioController,
              label: 'О себе',
              icon: Icons.info_outline,
              maxLines: 4,
              maxLength: 120,
              hint: 'Расскажите немного о себе...',
            ),
            const SizedBox(height: 16),
            // ── Учебная группа ────────────────────────────────────────
            _GroupPickerField(
              value: _selectedGroup,
              onChanged: (g) => setState(() => _selectedGroup = g),
            ),
            // ── Телефон для поиска — Android (авто) и iOS (вручную) ──
            if (SimService.isSupported) ...[
              const SizedBox(height: 16),
              _EditField(
                controller: _phoneController,
                label: 'Телефон для поиска',
                icon: Icons.phone_outlined,
                // Android: заполняется из SIM автоматически (read-only)
                // iOS: Apple не даёт номер — вводится вручную
                hint: SimService.canReadNumber
                    ? 'Нажмите SIM для заполнения'
                    : '+7 (999) 000-00-00',
                keyboardType: TextInputType.phone,
                readOnly: SimService.canReadNumber,
                suffixWidget: _simLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.sim_card_outlined,
                            color: AppColors.primary),
                        tooltip: SimService.canReadNumber
                            ? 'Заполнить с SIM'
                            : 'Показать оператора',
                        onPressed: _fillFromSim,
                      ),
              ),
            ],
            const SizedBox(height: 8),
            // Логин — только для чтения
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alternate_email,
                      color: AppColors.subtle, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Логин',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.subtle),
                        ),
                        Text(
                          widget.profile.login,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.lock_outline,
                      size: 16, color: AppColors.subtle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Виджет аватарки профиля ─────────────────────────────────────────────────
// Используется и в профиле, и в пузырях сообщений

class ProfileAvatar extends StatelessWidget {
  final String? avatarPath;
  final double radius;

  const ProfileAvatar({
    super.key,
    required this.avatarPath,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final path = avatarPath;
    if (path != null && path.isNotEmpty) {
      // Серверный путь (/uploads/... или абсолютный URL) → NetworkImage
      if (ApiConfig.isServerMediaPath(path)) {
        final url = ApiConfig.resolveMediaUrl(path);
        if (url != null) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            backgroundImage: NetworkImage(url),
            onBackgroundImageError: (_, __) {},
          );
        }
      } else if (!kIsWeb) {
        // Локальный файл устройства (на web dart:io — stub).
        final file = File(path);
        if (file.existsSync()) {
          return CircleAvatar(
            radius: radius,
            backgroundImage: FileImage(file),
          );
        }
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      child: Icon(
        Icons.person,
        size: radius,
        color: AppColors.textLight,
      ),
    );
  }
}

// ─── Вспомогательные виджеты ─────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.subtle,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.value,
    this.iconColor,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor,
      child: ListTile(
        leading: Icon(icon,
            color: iconColor ?? AppColors.primary, size: 22),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: titleColor ?? AppColors.subtle,
          ),
        ),
        subtitle: value.isNotEmpty
            ? Text(value, style: const TextStyle(fontSize: 15))
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final int? maxLength;
  final String? hint;
  final TextInputType? keyboardType;
  final Widget? suffixWidget;
  final bool readOnly;

  const _EditField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.maxLength,
    this.hint,
    this.keyboardType,
    this.suffixWidget,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: suffixWidget,
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
          const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ─── Переключатель темы ──────────────────────────────────────────────────────

class _ThemeSwitcher extends StatefulWidget {
  const _ThemeSwitcher();

  @override
  State<_ThemeSwitcher> createState() => _ThemeSwitcherState();
}

class _ThemeSwitcherState extends State<_ThemeSwitcher> {
  @override
  Widget build(BuildContext context) {
    final provider = ThemeProvider.of(context);
    final current = provider.mode;

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.brightness_6_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              const Text(
                'Тема оформления',
                style: TextStyle(fontSize: 14, color: AppColors.subtle),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ThemeChip(
                label: 'Светлая',
                icon: Icons.light_mode,
                selected: current == AppThemeMode.light,
                onTap: () => provider.setMode(AppThemeMode.light),
              ),
              const SizedBox(width: 8),
              _ThemeChip(
                label: 'Тёмная',
                icon: Icons.dark_mode,
                selected: current == AppThemeMode.dark,
                onTap: () => provider.setMode(AppThemeMode.dark),
              ),
              const SizedBox(width: 8),
              _ThemeChip(
                label: 'Авто',
                icon: Icons.brightness_auto,
                selected: current == AppThemeMode.system,
                onTap: () => provider.setMode(AppThemeMode.system),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.label,
    required this.icon,
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
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFE0E0E0),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : AppColors.subtle,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.subtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Виджет выбора роли (студент / преподаватель) ─────────────────────────────

class _RoleSelector extends StatelessWidget {
  final ProfileRole value;
  final ValueChanged<ProfileRole> onChanged;

  const _RoleSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoleChip(
          label: 'Студент',
          icon: Icons.person_outline,
          selected: value == ProfileRole.student,
          onTap: () => onChanged(ProfileRole.student),
        ),
        const SizedBox(width: 8),
        _RoleChip(
          label: 'Преподаватель',
          icon: Icons.school,
          selected: value == ProfileRole.teacher,
          onTap: () => onChanged(ProfileRole.teacher),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.icon,
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFE0E0E0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : AppColors.subtle),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.subtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Виджет-поле выбора группы ───────────────────────────────────────────────

class _GroupPickerField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _GroupPickerField({required this.value, required this.onChanged});

  Future<void> _open(BuildContext context) async {
    final picked = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupPickerScreen(current: value),
        fullscreenDialog: true,
      ),
    );
    // picked == '' означает «очистить»
    if (picked != null) {
      onChanged(picked.isEmpty ? null : picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGroup = value != null && value!.isNotEmpty;
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.school_outlined,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Учебная группа',
                    style: TextStyle(fontSize: 11, color: AppColors.subtle),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasGroup ? value! : 'Не выбрана',
                    style: TextStyle(
                      fontSize: 15,
                      color: hasGroup
                          ? null
                          : AppColors.subtle,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.subtle, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Экран выбора группы ─────────────────────────────────────────────────────

class GroupPickerScreen extends StatefulWidget {
  final String? current;
  final List<String> groups;

  const GroupPickerScreen({super.key, this.current, this.groups = const []});

  @override
  State<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends State<GroupPickerScreen> {
  final _searchController = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.groups;
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchController.text.trim().toUpperCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.groups
          : widget.groups.where((g) => g.toUpperCase().contains(q)).toList();
    });
  }

  void _select(String group) => Navigator.pop(context, group);

  void _clear() => Navigator.pop(context, ''); // пустая строка = сброс

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Учебная группа'),
        actions: [
          if (widget.current != null && widget.current!.isNotEmpty)
            TextButton(
              onPressed: _clear,
              child: const Text(
                'Сбросить',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Поиск группы…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _filtered.isEmpty
          ? Center(
              child: Text(
                'Группа не найдена',
                style: TextStyle(color: AppColors.subtle),
              ),
            )
          : ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, i) {
                final group = _filtered[i];
                final isSelected = group == widget.current;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected
                        ? AppColors.primary
                        : Theme.of(context).cardColor,
                    child: Text(
                      group.split('-').first,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : AppColors.subtle,
                      ),
                    ),
                  ),
                  title: Text(
                    group,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle,
                          color: AppColors.primary)
                      : null,
                  onTap: () => _select(group),
                );
              },
            ),
    );
  }
}
