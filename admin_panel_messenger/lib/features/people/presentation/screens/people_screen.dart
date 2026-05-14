import 'dart:async';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/people_provider.dart';
import '../../../../shared/models/person.dart';
import '../../../../shared/models/subject.dart';
import '../../../../shared/models/group_item.dart';
import '../../../../features/subjects/data/subjects_repository.dart';
import '../../../../features/groups/data/groups_repository.dart';

enum _SortCol { name, role, group }

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Сортировка
  _SortCol? _sortCol;
  bool _sortAsc = true;

  // Пагинация (клиентская)
  int _page = 1;
  int _pageSize = 20;

  // Список групп для дропдауна фильтра
  List<String> _groupNames = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGroups());
  }

  Future<void> _loadGroups() async {
    try {
      final groups =
          await ref.read(groupsRepositoryProvider).fetchGroups();
      if (mounted) {
        setState(() =>
            _groupNames = groups.map((g) => g.name).toList()..sort());
      }
    } catch (_) {
      // молча — дропдаун просто будет пустым
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref
          .read(peopleFilterProvider.notifier)
          .update((s) => s.copyWith(search: value));
      setState(() => _page = 1);
    });
  }

  void _onSort(_SortCol col, bool asc) =>
      setState(() { _sortCol = col; _sortAsc = asc; });

  List<Person> _sorted(List<Person> people) {
    if (_sortCol == null) return people;
    final list = [...people];
    list.sort((a, b) {
      final cmp = switch (_sortCol!) {
        _SortCol.name  => a.fullName.compareTo(b.fullName),
        _SortCol.role  => a.role.compareTo(b.role),
        _SortCol.group => (a.group ?? '').compareTo(b.group ?? ''),
      };
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final asyncPeople = ref.watch(peopleProvider);
    final filter = ref.watch(peopleFilterProvider);

    // Сбрасываем страницу при смене фильтра с сервера
    ref.listen<PeopleFilter>(peopleFilterProvider, (prev, next) {
      if (prev != next) setState(() => _page = 1);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(filter),
        Expanded(
          child: asyncPeople.when(
            data: (list) => _buildContent(context, _sorted(list)),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildError(e.toString()),
          ),
        ),
      ],
    );
  }

  // ── Toolbar ─────────────────────────────────────────────────────────────

  Widget _buildToolbar(PeopleFilter filter) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Строка 1: заголовок + кнопка
            Row(children: [
              const Text('Участники',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827))),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(peopleProvider.notifier)
                    .applyFilter(ref.read(peopleFilterProvider)),
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
            // Строка 2: поиск + роль
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Поиск по ФИО...',
                      hintStyle: const TextStyle(
                          fontSize: 13, color: Colors.grey),
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
                      value: 'teacher',
                      label: Text('Преподаватели')),
                ],
                selected: {filter.role},
                onSelectionChanged: (v) {
                  ref.read(peopleFilterProvider.notifier).update(
                      (s) => s.copyWith(role: v.first));
                  setState(() => _page = 1);
                },
              ),
            ]),
            const SizedBox(height: 10),
            // Строка 3: группа + аккаунт + кол-во на странице
            Row(children: [
              // Группа
              _ToolbarDropdown<String?>(
                icon: Icons.group_outlined,
                hint: 'Все группы',
                value: filter.group,
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Все группы')),
                  ..._groupNames.map((g) =>
                      DropdownMenuItem(value: g, child: Text(g))),
                ],
                onChanged: (v) {
                  ref
                      .read(peopleFilterProvider.notifier)
                      .update((s) => s.copyWith(group: v));
                  setState(() => _page = 1);
                },
              ),
              const SizedBox(width: 10),
              // Аккаунт
              _ToolbarDropdown<bool?>(
                icon: Icons.account_circle_outlined,
                hint: 'Аккаунт: все',
                value: filter.hasUser,
                items: const [
                  DropdownMenuItem(
                      value: null, child: Text('Аккаунт: все')),
                  DropdownMenuItem(
                      value: true, child: Text('Есть аккаунт')),
                  DropdownMenuItem(
                      value: false, child: Text('Нет аккаунта')),
                ],
                onChanged: (v) {
                  ref
                      .read(peopleFilterProvider.notifier)
                      .update((s) => s.copyWith(hasUser: v));
                  setState(() => _page = 1);
                },
              ),
              const Spacer(),
              // Кол-во записей на странице
              _ToolbarDropdown<int>(
                icon: Icons.format_list_numbered_rounded,
                hint: '20 / стр.',
                value: _pageSize,
                items: const [
                  DropdownMenuItem(value: 20, child: Text('20 / стр.')),
                  DropdownMenuItem(value: 50, child: Text('50 / стр.')),
                  DropdownMenuItem(
                      value: 100, child: Text('100 / стр.')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() { _pageSize = v; _page = 1; });
                },
              ),
            ]),
          ]),
    );
  }

  // ── Контент + пагинация ──────────────────────────────────────────────────

  Widget _buildContent(BuildContext context, List<Person> sorted) {
    if (sorted.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.people_outline,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Участники не найдены',
              style: TextStyle(
                  fontSize: 16, color: Colors.grey.shade400)),
        ]),
      );
    }

    final total = sorted.length;
    final pageCount = (total / _pageSize).ceil().clamp(1, 99999);
    // Корректируем страницу если вышла за пределы
    if (_page > pageCount) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _page = pageCount));
    }
    final start = (_page - 1) * _pageSize;
    final end = min(start + _pageSize, total);
    final pageItems = sorted.sublist(start, end);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTable(context, pageItems),
          const SizedBox(height: 12),
          _buildPaginationBar(total, pageCount, start + 1, end),
        ],
      ),
    );
  }

  // ── Таблица ──────────────────────────────────────────────────────────────

  Widget _buildTable(BuildContext context, List<Person> people) {
    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            sortColumnIndex: _sortCol?.index,
            sortAscending: _sortAsc,
            columnSpacing: 16,
            horizontalMargin: 24,
            headingRowHeight: 44,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 52,
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            dividerThickness: 1,
            columns: [
              DataColumn(
                label: const _ColHeader('ФИО'),
                onSort: (_, asc) => _onSort(_SortCol.name, asc),
              ),
              DataColumn(
                label: const _ColHeader('Роль'),
                onSort: (_, asc) => _onSort(_SortCol.role, asc),
              ),
              DataColumn(
                label: const _ColHeader('Группа'),
                onSort: (_, asc) => _onSort(_SortCol.group, asc),
              ),
              const DataColumn(label: _ColHeader('Аккаунт')),
              const DataColumn(label: _ColHeader('Действия')),
            ],
            rows: people.map((p) => _buildRow(context, p)).toList(),
          ),
        ),
      ),
    );
  }

  // ── Строка таблицы ───────────────────────────────────────────────────────

  DataRow _buildRow(BuildContext context, Person person) {
    final isTeacher = person.role.toLowerCase() == 'teacher';
    return DataRow(cells: [
      DataCell(Text(person.fullName,
          style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: Color(0xFF111827)))),
      DataCell(_RoleBadge(role: person.role)),
      DataCell(Text(person.group ?? '—',
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF4B5563)))),
      DataCell(
        person.hasUser
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.green.shade500, size: 16),
                const SizedBox(width: 6),
                Text('Есть',
                    style: TextStyle(
                        color: Colors.green.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ])
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.remove_circle_outline,
                    color: Colors.grey.shade400, size: 16),
                const SizedBox(width: 6),
                Text('Нет',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13)),
              ]),
      ),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Редактировать',
          icon: const Icon(Icons.edit_outlined, size: 18),
          color: const Color(0xFF1E3A5F),
          onPressed: () => _showEditDialog(context, person),
        ),
        if (isTeacher)
          IconButton(
            tooltip: 'Предметы и группы',
            icon: const Icon(Icons.school_outlined, size: 18),
            color: const Color(0xFF059669),
            onPressed: () => _showSubjectsDialog(context, person),
          ),
        IconButton(
          tooltip: 'Удалить',
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          color: const Color(0xFFDC2626),
          onPressed: () => _showDeleteDialog(context, person),
        ),
      ])),
    ]);
  }

  // ── Пагинация ────────────────────────────────────────────────────────────

  Widget _buildPaginationBar(
      int total, int pageCount, int rangeStart, int rangeEnd) {
    return Row(
      children: [
        Text(
          '$rangeStart–$rangeEnd из $total',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const Spacer(),
        // Быстрый переход к первой
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
          onPressed: _page > 1
              ? () => setState(() => _page--)
              : null,
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
        // Быстрый переход к последней
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

  // ── Teacher subjects dialog ──────────────────────────────────────────────

  Future<void> _showSubjectsDialog(
      BuildContext context, Person person) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 580,
          child: _TeacherSubjectsDialog(person: person),
        ),
      ),
    );
  }

  // ── Edit dialog ──────────────────────────────────────────────────────────

  Future<void> _showEditDialog(
      BuildContext context, Person person) async {
    final lastCtrl = TextEditingController(text: person.lastName);
    final firstCtrl = TextEditingController(text: person.firstName);
    final middleCtrl =
        TextEditingController(text: person.middleName ?? '');
    final groupCtrl =
        TextEditingController(text: person.group ?? '');
    String selectedRole = person.role;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) =>
          StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.edit_outlined,
                color: Color(0xFF1E3A5F)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Редактировать: ${person.fullName}',
                  style: const TextStyle(fontSize: 16)),
            ),
          ]),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: _DialogField(
                      controller: lastCtrl,
                      label: 'Фамилия',
                      icon: Icons.person_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DialogField(
                      controller: firstCtrl,
                      label: 'Имя',
                      icon: Icons.person_outline),
                ),
              ]),
              const SizedBox(height: 14),
              _DialogField(
                  controller: middleCtrl,
                  label: 'Отчество (необязательно)',
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
                      value: 'teacher',
                      child: Text('Преподаватель')),
                ],
                onChanged: (v) =>
                    setState(() => selectedRole = v!),
              ),
              const SizedBox(height: 14),
              _DialogField(
                  controller: groupCtrl,
                  label: 'Группа (необязательно)',
                  icon: Icons.group_outlined),
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

    final ok = await ref.read(peopleProvider.notifier).updatePerson(
          person.id,
          firstName: firstCtrl.text.trim().isEmpty
              ? null
              : firstCtrl.text.trim(),
          lastName: lastCtrl.text.trim().isEmpty
              ? null
              : lastCtrl.text.trim(),
          middleName: middleCtrl.text.trim().isEmpty
              ? ''
              : middleCtrl.text.trim(),
          role: selectedRole,
          group: groupCtrl.text.trim().isEmpty
              ? ''
              : groupCtrl.text.trim(),
        );

    if (!context.mounted) return;
    _showSnack(context,
        ok ? 'Участник обновлён' : 'Ошибка при обновлении', ok);
  }

  // ── Delete dialog ────────────────────────────────────────────────────────

  Future<void> _showDeleteDialog(
      BuildContext context, Person person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B)),
          SizedBox(width: 10),
          Text('Удалить участника?',
              style: TextStyle(fontSize: 18)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF4B5563),
                height: 1.5),
            children: [
              const TextSpan(
                  text: 'Вы собираетесь удалить участника '),
              TextSpan(
                  text: '"${person.fullName}"',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(
                  text:
                      '. Аккаунт в мессенджере не будет удалён.'),
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
        await ref.read(peopleProvider.notifier).deletePerson(person.id);
    if (!context.mounted) return;
    _showSnack(context,
        ok ? '${person.fullName} удалён' : 'Ошибка при удалении',
        ok);
  }

  // ── Error / snack ────────────────────────────────────────────────────────

  Widget _buildError(String message) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded,
            size: 52, color: Colors.red),
        const SizedBox(height: 12),
        Text(message,
            style:
                const TextStyle(color: Colors.red, fontSize: 14)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => ref
              .read(peopleProvider.notifier)
              .applyFilter(ref.read(peopleFilterProvider)),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      ]),
    );
  }

  void _showSnack(BuildContext context, String text, bool ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor:
          ok ? Colors.green.shade700 : Colors.red.shade700,
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

// ── Teacher subjects dialog ───────────────────────────────────────────────────

class _TeacherSubjectsDialog extends ConsumerStatefulWidget {
  final Person person;

  const _TeacherSubjectsDialog({required this.person});

  @override
  ConsumerState<_TeacherSubjectsDialog> createState() =>
      _TeacherSubjectsDialogState();
}

class _TeacherSubjectsDialogState
    extends ConsumerState<_TeacherSubjectsDialog> {
  List<TeacherAssignment>? _assignments;
  List<Subject> _subjects = [];
  List<GroupItem> _groups = [];
  bool _loading = true;
  String? _error;

  Subject? _selectedSubject;
  GroupItem? _selectedGroup;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final subRepo = ref.read(subjectsRepositoryProvider);
      final grpRepo = ref.read(groupsRepositoryProvider);
      final assignments =
          await subRepo.fetchTeacherAssignments(widget.person.id);
      final subjects = await subRepo.fetchSubjects();
      final groups = await grpRepo.fetchGroups();
      if (mounted) {
        setState(() {
          _assignments = assignments;
          _subjects = subjects;
          _groups = groups;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  Future<void> _addAssignment() async {
    if (_selectedSubject == null || _selectedGroup == null) return;
    setState(() => _adding = true);
    try {
      await ref.read(subjectsRepositoryProvider).addAssignment(
            widget.person.id,
            _selectedSubject!.id,
            _selectedGroup!.name,
          );
      if (mounted) {
        setState(() {
          _selectedSubject = null;
          _selectedGroup = null;
          _adding = false;
        });
        final updated = await ref
            .read(subjectsRepositoryProvider)
            .fetchTeacherAssignments(widget.person.id);
        if (mounted) setState(() => _assignments = updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  Future<void> _removeAssignment(TeacherAssignment a) async {
    try {
      await ref
          .read(subjectsRepositoryProvider)
          .removeAssignment(widget.person.id, a.id);
      if (mounted) {
        setState(() => _assignments =
            _assignments!.where((x) => x.id != a.id).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xFF0F2440),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.school_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Предметы: ${widget.person.fullName}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close,
                  color: Colors.white70, size: 20),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        // Body
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 36),
                            const SizedBox(height: 8),
                            Text(_error!,
                                style: const TextStyle(
                                    color: Colors.red)),
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Повторить'),
                            ),
                          ]),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_assignments!.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius:
                                    BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.grey.shade200),
                              ),
                              child: const Text(
                                'Предметы не назначены',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 14),
                              ),
                            )
                          else ...[
                            const Text('Назначено:',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF374151))),
                            const SizedBox(height: 10),
                            ...(_assignments!.map((a) =>
                                _AssignmentTile(
                                  assignment: a,
                                  onDelete: () =>
                                      _removeAssignment(a),
                                ))),
                          ],
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 16),
                          const Text('Добавить назначение:',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151))),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<Subject>(
                            initialValue: _selectedSubject,
                            decoration: InputDecoration(
                              labelText: 'Предмет',
                              prefixIcon: const Icon(
                                  Icons.menu_book_outlined,
                                  size: 20),
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                            ),
                            items: _subjects
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s.name),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedSubject = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<GroupItem>(
                            initialValue: _selectedGroup,
                            decoration: InputDecoration(
                              labelText: 'Группа',
                              prefixIcon: const Icon(
                                  Icons.group_outlined,
                                  size: 20),
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                            ),
                            items: _groups
                                .map((g) => DropdownMenuItem(
                                      value: g,
                                      child: Text(g.name),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedGroup = v),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: (_selectedSubject == null ||
                                      _selectedGroup == null ||
                                      _adding)
                                  ? null
                                  : _addAssignment,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                              ),
                              icon: _adding
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Icon(Icons.add, size: 18),
                              label: const Text('Добавить назначение'),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  final TeacherAssignment assignment;
  final VoidCallback onDelete;

  const _AssignmentTile(
      {required this.assignment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(children: [
        const Icon(Icons.menu_book_rounded,
            size: 16, color: Color(0xFF059669)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(assignment.subjectName,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF065F46))),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Text(assignment.groupName,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF059669),
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          color: Colors.red.shade400,
          padding: EdgeInsets.zero,
          constraints:
              const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: onDelete,
        ),
      ]),
    );
  }
}

// ── Общие виджеты ─────────────────────────────────────────────────────────────

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
      {required this.controller,
      required this.label,
      required this.icon});

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
