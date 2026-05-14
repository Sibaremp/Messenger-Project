import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/api_config.dart' show ApiConfig;
import '../utils/app_snack.dart';

/// Позволяет редактировать имя, описание и аватар чата.
/// Возвращает обновлённый [Chat] через [Navigator.pop] при сохранении.
class ChatSettingsScreen extends StatefulWidget {
  final Chat chat;
  final ChatService service;

  const ChatSettingsScreen({
    super.key,
    required this.chat,
    required this.service,
  });

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  String? _avatarPath;
  bool _isSaving = false;
  // Мутабельная копия списка участников — для изменения ролей без немедленного сохранения.
  late List<ChatMember> _members;

  @override
  void initState() {
    super.initState();
    _nameController  = TextEditingController(text: widget.chat.name);
    _descController  = TextEditingController(text: widget.chat.description ?? '');
    _avatarPath      = widget.chat.avatarPath;
    _members         = List.from(widget.chat.members);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  /// Выбирает и изменяет размер аватарного изображения из указанного [source].
  /// Изображения ограничены 512×512 пикселей для экономии памяти.
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

  Future<void> _pickGif() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
    );
    if (result != null && result.files.single.path != null && mounted) {
      setState(() => _avatarPath = result.files.single.path);
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
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
              ),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.photo_library, color: Colors.white, size: 20),
              ),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.gif, color: Colors.white, size: 20),
              ),
              title: const Text('Выбрать GIF'),
              onTap: () {
                Navigator.pop(context);
                _pickGif();
              },
            ),
            if (_avatarPath != null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEEEEEE),
                  child: Icon(Icons.delete_outline, color: Colors.red, size: 20),
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

  /// Показывает диалог выбора роли для [member].
  /// Создатель не может менять свою роль — он всегда остаётся создателем.
  void _showRoleDialog(ChatMember member) {
    if (member.role == MemberRole.creator) return; // создатель неизменяем

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  member.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const Divider(height: 1),
            // Назначить / снять администратора
            ListTile(
              leading: CircleAvatar(
                backgroundColor: member.role == MemberRole.admin
                    ? Colors.orange.withValues(alpha: 0.15)
                    : Colors.blue.withValues(alpha: 0.15),
                child: Icon(
                  member.role == MemberRole.admin
                      ? Icons.person_remove_outlined
                      : Icons.admin_panel_settings_outlined,
                  color: member.role == MemberRole.admin
                      ? Colors.orange
                      : Colors.blue,
                  size: 20,
                ),
              ),
              title: Text(
                member.role == MemberRole.admin
                    ? 'Снять роль администратора'
                    : 'Назначить администратором',
              ),
              onTap: () {
                Navigator.pop(context);
                final newRole = member.role == MemberRole.admin
                    ? MemberRole.member
                    : MemberRole.admin;
                setState(() {
                  final idx = _members.indexOf(member);
                  if (idx != -1) {
                    _members[idx] = member.copyWith(role: newRole);
                  }
                });
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Диалог подтверждения удаления всего чата (группы / сообщества).
  /// После подтверждения удаляет чат через сервис и возвращает [true] —
  /// сигнал для [ChatScreen] закрыться и вернуться в список чатов.
  void _confirmDelete() {
    final label = widget.chat.type == ChatType.community
        ? 'сообщество'
        : 'группу';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить $label?'),
        content: Text(
          '«${widget.chat.name}» будет удалено навсегда вместе со всей перепиской.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.service.deleteChat(widget.chat.id);
              if (!mounted) return;
              // true — сигнал ChatScreen: вернуться в список чатов
              Navigator.pop(context, true);
            },
            child: const Text('Удалить',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Подтверждение удаления участника через диалог.
  void _confirmRemove(ChatMember member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('«${member.name}» будет исключён из чата.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
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

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
            AppSnack.info(context, 'Название не может быть пустым');
      return;
    }

    setState(() => _isSaving = true);

    final updated = widget.chat.copyWith(
      name: name,
      // Сохраняем null вместо пустой строки при отсутствии описания.
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      avatarPath: _avatarPath,
      members: _members,
    );

    if (!mounted) return;
    Navigator.pop(context, updated);
  }

  Widget _buildAvatar() {
    if (_avatarPath != null && _avatarPath!.isNotEmpty) {
      // Серверный путь — грузим через NetworkImage
      if (ApiConfig.isServerMediaPath(_avatarPath)) {
        final url = ApiConfig.resolveMediaUrl(_avatarPath);
        if (url != null) {
          return CircleAvatar(
            radius: 52,
            backgroundImage: NetworkImage(url),
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          );
        }
      }
      // Локальный файл (только на нативных платформах)
      if (!kIsWeb) {
        final file = File(_avatarPath!);
        if (file.existsSync()) {
          return CircleAvatar(
            radius: 52,
            backgroundImage: FileImage(file),
          );
        }
      }
    }

    // Плейсхолдер — инициалы из названия (или иконка для личных чатов)
    if (widget.chat.type != ChatType.direct) {
      final words = widget.chat.name
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final initials = words.length >= 2
          ? '${words[0][0]}${words[1][0]}'.toUpperCase()
          : widget.chat.name.isNotEmpty
              ? widget.chat.name[0].toUpperCase()
              : '?';
      return CircleAvatar(
        radius: 52,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 52,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: const Icon(Icons.person, size: 48, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final subtleColor = AppColors.subtle;
    final chatTypeName = switch (widget.chat.type) {
      ChatType.direct    => 'Личный чат',
      ChatType.group     => 'Группа',
      ChatType.community => 'Сообщество',
    };
    final memberLabel = widget.chat.type == ChatType.community
        ? 'Подписчики'
        : 'Участники';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Градиентная шапка с аватаром ──────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Theme.of(context).colorScheme.primary,
            leading: const BackButton(color: Colors.white),
            actions: [
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              else
                TextButton(
                  onPressed: _save,
                  child: const Text(
                    'Сохранить',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Theme.of(context).colorScheme.primary, Color(0xFF8B3A28)],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      GestureDetector(
                        onTap: _showPickerOptions,
                        child: Stack(
                          children: [
                            _buildAvatar(),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                width: 30, height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _nameController.text.isEmpty
                            ? widget.chat.name
                            : _nameController.text,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '$memberLabel · ${_members.length}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Редактирование: название + описание ─────────────
                  _SettingsCard(children: [
                    _SettingsField(
                      controller: _nameController,
                      label: widget.chat.type == ChatType.direct
                          ? 'Имя' : 'Название',
                      icon: Icons.edit_outlined,
                      onChanged: (_) => setState(() {}),
                    ),
                    const _CardDivider(),
                    _SettingsField(
                      controller: _descController,
                      label: 'Описание',
                      icon: Icons.info_outline,
                      maxLines: 3,
                      maxLength: 200,
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // ── Тип (только чтение) ─────────────────────────────
                  _SettingsCard(children: [
                    _SettingsReadRow(
                      icon: switch (widget.chat.type) {
                        ChatType.direct    => Icons.person_outline,
                        ChatType.group     => Icons.group_outlined,
                        ChatType.community => Icons.campaign_outlined,
                      },
                      label: 'Тип',
                      value: chatTypeName,
                    ),
                  ]),

                  // ── Удалить ─────────────────────────────────────────
                  if (widget.chat.type != ChatType.direct) ...[
                    const SizedBox(height: 12),
                    _SettingsCard(children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _confirmDelete,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.delete_forever_outlined,
                                  color: Colors.red, size: 22),
                              const SizedBox(width: 14),
                              Text(
                                widget.chat.type == ChatType.community
                                    ? 'Удалить сообщество'
                                    : 'Удалить группу',
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ],

                  // ── Участники ───────────────────────────────────────
                  if (_members.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        '$memberLabel · ${_members.length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    _SettingsCard(
                      children: _members.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final m   = entry.value;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (idx > 0) const _CardDivider(),
                            _MemberRow(
                              member: m,
                              onTap: m.role != MemberRole.creator
                                  ? () => _showRoleDialog(m)
                                  : null,
                              onRemove: m.role != MemberRole.creator
                                  ? () => _confirmRemove(m)
                                  : null,
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Небольшая цветная метка, отображающая роль участника (создатель, админ).
class _RoleBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _RoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Новые вспомогательные виджеты для переработанного UI ─────────────────────

/// Карточка-контейнер для группы настроек.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Тонкий разделитель внутри карточки.
class _CardDivider extends StatelessWidget {
  const _CardDivider();
  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 16);
}

/// Редактируемое поле внутри карточки.
class _SettingsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  const _SettingsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
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

/// Нередактируемая строка (например, Тип чата).
class _SettingsReadRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SettingsReadRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.subtle, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.subtle)),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, size: 15, color: AppColors.subtle),
        ],
      ),
    );
  }
}

/// Строка участника внутри карточки.
class _MemberRow extends StatelessWidget {
  final ChatMember member;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _MemberRow({
    required this.member,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final initial = member.name.isNotEmpty
        ? member.name[0].toUpperCase()
        : '?';

    // Цвет аватара по хешу имени
    const palette = [
      Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFEF5350),
      Color(0xFFAB47BC), Color(0xFF42A5F5), Color(0xFFFF7043),
    ];
    final avatarColor =
        palette[member.name.codeUnits.fold(0, (h, c) => h * 31 + c).abs() %
            palette.length];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: avatarColor,
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(member.name,
                  style: const TextStyle(fontSize: 15)),
            ),
            // Бейдж роли
            if (member.role == MemberRole.creator)
              _RoleBadge(
                  label: 'Создатель', color: Theme.of(context).colorScheme.primary)
            else if (member.role == MemberRole.admin)
              const _RoleBadge(label: 'Админ', color: Colors.blue),
            // Кнопка удалить
            if (onRemove != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.person_remove_outlined,
                    color: Colors.red, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
