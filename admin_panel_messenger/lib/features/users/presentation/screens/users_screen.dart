import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/users_provider.dart';
import '../../../../shared/models/user.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Filters
  String _search = '';
  String _roleFilter = 'all'; // all / student / teacher
  String? _groupFilter;       // null = all groups

  // Pagination
  int _page = 1;
  int _pageSize = 20;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _search = value.trim().toLowerCase();
        _page = 1;
      });
    });
  }

  List<User> _filtered(List<User> users) {
    return users.where((u) {
      // Search
      if (_search.isNotEmpty) {
        final haystack =
            '${u.login} ${u.displayName}'.toLowerCase();
        if (!haystack.contains(_search)) return false;
      }
      // Role
      if (_roleFilter != 'all' &&
          u.role.toLowerCase() != _roleFilter) { return false; }
      // Group
      if (_groupFilter != null && u.group != _groupFilter) { return false; }
      return true;
    }).toList();
  }

  List<String> _uniqueGroups(List<User> users) {
    final groups = users
        .map((u) => u.group)
        .whereType<String>()
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return groups;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final asyncUsers = ref.watch(usersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        asyncUsers.when(
          data: (users) => _buildToolbar(users),
          loading: () => _buildToolbar([]),
          error: (_, __) => _buildToolbar([]),
        ),
        Expanded(
          child: asyncUsers.when(
            data: (users) => _buildContent(context, users),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildError(e.toString()),
          ),
        ),
      ],
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────

  Widget _buildToolbar(List<User> users) {
    final groups = _uniqueGroups(users);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: title + refresh
          Row(children: [
            const Text('Пользователи',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => ref.read(usersProvider.notifier).load(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label:
                  const Text('Обновить', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          // Row 2: search + role filter
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: 'Поиск по логину, имени...',
                    hintStyle:
                        const TextStyle(fontSize: 13, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 13),
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(value: 'all', label: Text('Все')),
                ButtonSegment(
                    value: 'student', label: Text('Студенты')),
                ButtonSegment(
                    value: 'teacher', label: Text('Преподаватели')),
              ],
              selected: {_roleFilter},
              onSelectionChanged: (v) =>
                  setState(() {
                    _roleFilter = v.first;
                    _page = 1;
                  }),
            ),
          ]),
          const SizedBox(height: 10),
          // Row 3: group + pageSize
          Row(children: [
            _ToolbarDropdown<String?>(
              icon: Icons.group_outlined,
              hint: 'Все группы',
              value: _groupFilter,
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Все группы')),
                ...groups.map((g) =>
                    DropdownMenuItem(value: g, child: Text(g))),
              ],
              onChanged: (v) =>
                  setState(() {
                    _groupFilter = v;
                    _page = 1;
                  }),
            ),
            const Spacer(),
            _ToolbarDropdown<int>(
              icon: Icons.format_list_numbered_rounded,
              hint: '20 / стр.',
              value: _pageSize,
              items: const [
                DropdownMenuItem(value: 20, child: Text('20 / стр.')),
                DropdownMenuItem(value: 50, child: Text('50 / стр.')),
                DropdownMenuItem(value: 100, child: Text('100 / стр.')),
              ],
              onChanged: (v) {
                if (v != null) setState(() { _pageSize = v; _page = 1; });
              },
            ),
          ]),
        ],
      ),
    );
  }

  // ── Content ───────────────────────────────────────────────────────────────

  Widget _buildContent(BuildContext context, List<User> allUsers) {
    final filtered = _filtered(allUsers);

    if (filtered.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.manage_accounts_outlined,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Пользователи не найдены',
              style:
                  TextStyle(fontSize: 16, color: Colors.grey.shade400)),
        ]),
      );
    }

    final total = filtered.length;
    final pageCount = (total / _pageSize).ceil().clamp(1, 99999);
    if (_page > pageCount) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _page = pageCount));
    }
    final start = (_page - 1) * _pageSize;
    final end = min(start + _pageSize, total);
    final pageItems = filtered.sublist(start, end);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  columnSpacing: 16,
                  horizontalMargin: 24,
                  headingRowHeight: 44,
                  dataRowMinHeight: 62,
                  dataRowMaxHeight: 62,
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  dividerThickness: 1,
                  columns: const [
                    DataColumn(label: _ColHeader('ID')),
                    DataColumn(label: _ColHeader('Участник')),
                    DataColumn(label: _ColHeader('Роль')),
                    DataColumn(label: _ColHeader('Группа')),
                    DataColumn(label: _ColHeader('Телефон')),
                    DataColumn(label: _ColHeader('Пароль')),
                    DataColumn(label: _ColHeader('Действия')),
                  ],
                  rows:
                      pageItems.map((u) => _buildRow(context, u)).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildPaginationBar(total, pageCount, start + 1, end),
        ],
      ),
    );
  }

  // ── Pagination bar ────────────────────────────────────────────────────────

  Widget _buildPaginationBar(
      int total, int pageCount, int rangeStart, int rangeEnd) {
    return Row(
      children: [
        Text(
          '$rangeStart–$rangeEnd из $total',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.first_page_rounded),
          iconSize: 20,
          color: _page > 1
              ? const Color(0xFF1E3A5F)
              : Colors.grey.shade300,
          tooltip: 'Первая страница',
          onPressed:
              _page > 1 ? () => setState(() => _page = 1) : null,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 20,
          color: _page > 1
              ? const Color(0xFF1E3A5F)
              : Colors.grey.shade300,
          tooltip: 'Предыдущая',
          onPressed:
              _page > 1 ? () => setState(() => _page--) : null,
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFFF8FAFC),
          ),
          child: Text(
            '$_page / $pageCount',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A5F)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          iconSize: 20,
          color: _page < pageCount
              ? const Color(0xFF1E3A5F)
              : Colors.grey.shade300,
          tooltip: 'Следующая',
          onPressed: _page < pageCount
              ? () => setState(() => _page++)
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.last_page_rounded),
          iconSize: 20,
          color: _page < pageCount
              ? const Color(0xFF1E3A5F)
              : Colors.grey.shade300,
          tooltip: 'Последняя страница',
          onPressed: _page < pageCount
              ? () => setState(() => _page = pageCount)
              : null,
        ),
      ],
    );
  }

  // ── Row ───────────────────────────────────────────────────────────────────

  DataRow _buildRow(BuildContext context, User user) {
    return DataRow(cells: [
      DataCell(Text('#${user.id}',
          style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 13,
              fontFamily: 'monospace'))),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 16,
          backgroundColor:
              const Color(0xFF1E3A5F).withValues(alpha: 0.1),
          child: Text(
            user.avatarLetter,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A5F)),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.displayName,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF111827)),
            ),
            Text(
              user.login,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ])),
      DataCell(_RoleBadge(role: user.role)),
      DataCell(Text(user.group ?? '—',
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF4B5563)))),
      DataCell(Text(user.phone ?? '—',
          style: const TextStyle(
              fontSize: 13, color: Color(0xFF6B7280)))),
      DataCell(
        TextButton.icon(
          onPressed: () => _showPasswordDialog(context, user),
          icon: const Icon(Icons.key_outlined, size: 16),
          label: const Text('Сменить', style: TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6B7280),
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
          ),
        ),
      ),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Редактировать',
          icon: const Icon(Icons.edit_outlined, size: 18),
          color: const Color(0xFF1E3A5F),
          onPressed: () => _showEditDialog(context, user),
        ),
        IconButton(
          tooltip: 'Удалить',
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          color: const Color(0xFFDC2626),
          onPressed: () => _showDeleteDialog(context, user),
        ),
      ])),
    ]);
  }

  // ── Edit dialog ───────────────────────────────────────────────────────────

  Future<void> _showEditDialog(BuildContext context, User user) async {
    final loginCtrl = TextEditingController(text: user.login);
    final groupCtrl = TextEditingController(text: user.group ?? '');
    final phoneCtrl = TextEditingController(text: user.phone ?? '');
    String selectedRole = user.role;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.edit_outlined, color: Color(0xFF1E3A5F)),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Редактировать: ${user.displayName}',
                    style: const TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _DialogField(
                  controller: loginCtrl,
                  label: 'Логин',
                  icon: Icons.person_outline),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: InputDecoration(
                  labelText: 'Роль',
                  prefixIcon:
                      const Icon(Icons.badge_outlined, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'student', child: Text('Студент')),
                  DropdownMenuItem(
                      value: 'teacher', child: Text('Преподаватель')),
                ],
                onChanged: (v) => setState(() => selectedRole = v!),
              ),
              const SizedBox(height: 14),
              _DialogField(
                  controller: groupCtrl,
                  label: 'Группа',
                  icon: Icons.group_outlined),
              const SizedBox(height: 14),
              _DialogField(
                  controller: phoneCtrl,
                  label: 'Телефон',
                  icon: Icons.phone_outlined),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        );
      }),
    );

    if (confirmed != true || !context.mounted) return;

    final ok = await ref.read(usersProvider.notifier).updateUser(
          user.id,
          login: loginCtrl.text.trim().isEmpty
              ? null
              : loginCtrl.text.trim(),
          role: selectedRole,
          group: groupCtrl.text.trim().isEmpty
              ? ''
              : groupCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty
              ? ''
              : phoneCtrl.text.trim(),
        );

    if (!context.mounted) return;
    _showSnack(
        context,
        ok ? 'Пользователь обновлён' : 'Ошибка при обновлении',
        ok);
  }

  // ── Password dialog ───────────────────────────────────────────────────────

  Future<void> _showPasswordDialog(BuildContext context, User user) async {
    final pwCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.lock_outline_rounded,
                color: Color(0xFF1E3A5F)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Смена пароля: ${user.displayName}',
                  style: const TextStyle(fontSize: 17)),
            ),
          ]),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: pwCtrl,
                obscureText: obscure1,
                onChanged: (_) => setState(() => errorText = null),
                decoration: InputDecoration(
                  labelText: 'Новый пароль',
                  prefixIcon:
                      const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure1
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18),
                    onPressed: () =>
                        setState(() => obscure1 = !obscure1),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure2,
                onChanged: (_) => setState(() => errorText = null),
                decoration: InputDecoration(
                  labelText: 'Подтвердите пароль',
                  prefixIcon:
                      const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure2
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18),
                    onPressed: () =>
                        setState(() => obscure2 = !obscure2),
                  ),
                  errorText: errorText,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Минимум 6 символов',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                final pw = pwCtrl.text;
                final confirm = confirmCtrl.text;
                if (pw.length < 6) {
                  setState(() => errorText = 'Минимум 6 символов');
                  return;
                }
                if (pw != confirm) {
                  setState(() => errorText = 'Пароли не совпадают');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        );
      }),
    );

    if (confirmed != true || !context.mounted) return;

    final ok = await ref
        .read(usersProvider.notifier)
        .changePassword(user.id, pwCtrl.text);

    if (!context.mounted) return;
    _showSnack(
        context,
        ok
            ? 'Пароль для "${user.login}" изменён'
            : 'Ошибка при смене пароля',
        ok);
  }

  // ── Delete dialog ─────────────────────────────────────────────────────────

  Future<void> _showDeleteDialog(BuildContext context, User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
          SizedBox(width: 10),
          Text('Удалить пользователя?',
              style: TextStyle(fontSize: 18)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF4B5563), height: 1.5),
            children: [
              const TextSpan(
                  text: 'Вы собираетесь удалить пользователя '),
              TextSpan(
                  text: '"${user.login}"',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(text: '. Это действие необратимо.'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final ok =
        await ref.read(usersProvider.notifier).deleteUser(user.id);
    if (!context.mounted) return;
    _showSnack(
        context,
        ok
            ? 'Пользователь "${user.login}" удалён'
            : 'Не удалось удалить',
        ok);
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError(String message) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            size: 52, color: Colors.red),
        const SizedBox(height: 12),
        Text(message,
            style: const TextStyle(color: Colors.red, fontSize: 14)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => ref.read(usersProvider.notifier).load(),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      ]),
    );
  }

  void _showSnack(BuildContext context, String text, bool ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }
}

// ── _ToolbarDropdown ──────────────────────────────────────────────────────────

class _ToolbarDropdown<T> extends StatelessWidget {
  final IconData icon;
  final String hint;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _ToolbarDropdown({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            hint: Text(hint,
                style: const TextStyle(
                    fontSize: 13, color: Colors.grey)),
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF111827)),
            icon: Icon(Icons.arrow_drop_down,
                color: Colors.grey.shade500, size: 20),
            isDense: true,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Color(0xFF374151)));
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _DialogField(
      {required this.controller, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isStudent = role.toLowerCase() == 'student';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isStudent
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isStudent
                ? const Color(0xFFBFDBFE)
                : const Color(0xFFDDD6FE)),
      ),
      child: Text(
        isStudent ? 'Студент' : 'Преподаватель',
        style: TextStyle(
            fontSize: 12,
            color: isStudent
                ? const Color(0xFF1D4ED8)
                : const Color(0xFF7C3AED),
            fontWeight: FontWeight.w500),
      ),
    );
  }
}
