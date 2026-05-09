import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/subjects_provider.dart';
import '../../data/subjects_repository.dart';
import '../../../../shared/models/subject.dart';
import '../../../../shared/models/person.dart';
import '../../../../shared/models/group_item.dart';
import '../../../../features/people/data/people_repository.dart';
import '../../../../features/groups/data/groups_repository.dart';

class SubjectsScreen extends ConsumerStatefulWidget {
  const SubjectsScreen({super.key});

  @override
  ConsumerState<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends ConsumerState<SubjectsScreen> {
  final _addCtrl = TextEditingController();

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncSubjects = ref.watch(subjectsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(),
        Expanded(
          child: asyncSubjects.when(
            data: (list) => _buildContent(context, list),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildError(e.toString()),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Row(
        children: [
          const Text('Предметы',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827))),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(subjectsProvider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Обновить', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Subject> subjects) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AddSubjectCard(addCtrl: _addCtrl),
          const SizedBox(height: 20),
          if (subjects.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.menu_book_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Предметы не добавлены',
                      style: TextStyle(
                          fontSize: 15, color: Colors.grey.shade400)),
                ]),
              ),
            )
          else
            Card(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    columnSpacing: 16,
                    horizontalMargin: 24,
                    headingRowHeight: 44,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 52,
                    headingRowColor:
                        WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    dividerThickness: 1,
                    columns: const [
                      DataColumn(
                          label: _ColHeader('Название')),
                      DataColumn(
                          label: _ColHeader('Назначений'),
                          numeric: true),
                      DataColumn(
                          label: _ColHeader('Действия')),
                    ],
                    rows: subjects
                        .map((s) => _buildRow(context, s))
                        .toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  DataRow _buildRow(BuildContext context, Subject subject) {
    return DataRow(cells: [
      DataCell(Text(subject.name,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827)))),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${subject.assignmentCount}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E3A5F))),
        ),
      ),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Назначить преподавателя',
          icon: const Icon(Icons.person_add_outlined, size: 18),
          color: const Color(0xFF059669),
          onPressed: () => _showAssignTeacherDialog(context, subject),
        ),
        IconButton(
          tooltip: 'Переименовать',
          icon: const Icon(Icons.edit_outlined, size: 18),
          color: const Color(0xFF1E3A5F),
          onPressed: () => _showRenameDialog(context, subject),
        ),
        IconButton(
          tooltip: 'Удалить',
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          color: const Color(0xFFDC2626),
          onPressed: () => _showDeleteDialog(context, subject),
        ),
      ])),
    ]);
  }

  Future<void> _showAssignTeacherDialog(
      BuildContext context, Subject subject) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 480,
          child: _AssignTeacherDialog(subject: subject),
        ),
      ),
    );
    ref.read(subjectsProvider.notifier).load();
  }

  Future<void> _showRenameDialog(
      BuildContext context, Subject subject) async {
    final ctrl = TextEditingController(text: subject.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.edit_outlined, color: Color(0xFF1E3A5F)),
          SizedBox(width: 10),
          Text('Переименовать предмет',
              style: TextStyle(fontSize: 17)),
        ]),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Название',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
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
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;

    final ok = await ref
        .read(subjectsProvider.notifier)
        .rename(subject.id, name);
    if (!context.mounted) return;
    _showSnack(context, ok ? 'Предмет переименован' : 'Ошибка', ok);
  }

  Future<void> _showDeleteDialog(
      BuildContext context, Subject subject) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
          SizedBox(width: 10),
          Text('Удалить предмет?', style: TextStyle(fontSize: 18)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF4B5563), height: 1.5),
            children: [
              const TextSpan(text: 'Предмет '),
              TextSpan(
                  text: '"${subject.name}"',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(
                  text: ' и все его назначения '
                      '(${subject.assignmentCount} шт.) будут удалены.'),
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
        await ref.read(subjectsProvider.notifier).delete(subject.id);
    if (!context.mounted) return;
    _showSnack(
        context, ok ? 'Предмет удалён' : 'Ошибка при удалении', ok);
  }

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
          onPressed: () =>
              ref.read(subjectsProvider.notifier).load(),
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

// ── Add card ──────────────────────────────────────────────────────────────────

class _AddSubjectCard extends ConsumerStatefulWidget {
  final TextEditingController addCtrl;

  const _AddSubjectCard({required this.addCtrl});

  @override
  ConsumerState<_AddSubjectCard> createState() => _AddSubjectCardState();
}

class _AddSubjectCardState extends ConsumerState<_AddSubjectCard> {
  bool _loading = false;

  Future<void> _submit() async {
    final name = widget.addCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    final ok =
        await ref.read(subjectsProvider.notifier).create(name);
    if (mounted) {
      setState(() => _loading = false);
      if (ok) {
        widget.addCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Предмет добавлен'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.addCtrl,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Название нового предмета',
                  prefixIcon:
                      const Icon(Icons.add_circle_outline, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 0),
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add, size: 18),
                label: const Text('Добавить',
                    style: TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Assign teacher dialog ─────────────────────────────────────────────────────

class _AssignTeacherDialog extends ConsumerStatefulWidget {
  final Subject subject;
  const _AssignTeacherDialog({required this.subject});

  @override
  ConsumerState<_AssignTeacherDialog> createState() =>
      _AssignTeacherDialogState();
}

class _AssignTeacherDialogState
    extends ConsumerState<_AssignTeacherDialog> {
  List<Person> _teachers = [];
  List<GroupItem> _groups = [];
  bool _loading = true;
  String? _error;

  Person? _selectedTeacher;
  GroupItem? _selectedGroup;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final peopleRepo = ref.read(peopleRepositoryProvider);
      final groupsRepo = ref.read(groupsRepositoryProvider);
      final teachers = await peopleRepo.fetchPeople(role: 'teacher');
      final groups   = await groupsRepo.fetchGroups();
      if (mounted) {
        setState(() {
          _teachers = teachers;
          _groups   = groups;
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save() async {
    if (_selectedTeacher == null || _selectedGroup == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(subjectsRepositoryProvider).addAssignment(
            _selectedTeacher!.id,
            widget.subject.id,
            _selectedGroup!.name,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Назначено: ${_selectedTeacher!.fullName} → ${widget.subject.name} (${_selectedGroup!.name})'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
        setState(() {
          _selectedTeacher = null;
          _selectedGroup   = null;
          _saving          = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.person_add_outlined,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Назначить преподавателя: ${widget.subject.name}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),
        // Body
        Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 36),
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Повторить'),
                      ),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButtonFormField<Person>(
                        initialValue: _selectedTeacher,
                        decoration: InputDecoration(
                          labelText: 'Преподаватель',
                          prefixIcon: const Icon(
                              Icons.person_outlined,
                              size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        items: _teachers
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.fullName,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedTeacher = v),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<GroupItem>(
                        initialValue: _selectedGroup,
                        decoration: InputDecoration(
                          labelText: 'Группа',
                          prefixIcon: const Icon(Icons.group_outlined,
                              size: 20),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
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
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: (_selectedTeacher == null ||
                                  _selectedGroup == null ||
                                  _saving)
                              ? null
                              : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.add, size: 18),
                          label: const Text('Назначить'),
                        ),
                      ),
                    ]),
        ),
      ],
    );
  }
}

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
