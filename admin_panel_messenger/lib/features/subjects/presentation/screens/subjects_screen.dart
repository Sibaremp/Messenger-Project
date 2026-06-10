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

  // Inline expansion state
  final Set<int> _expanded = {};
  final Map<int, List<SubjectAssignment>> _cache = {};
  final Map<int, bool> _loadingMap = {};
  final Map<int, String?> _errorMap = {};

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments(int subjectId) async {
    if (_cache.containsKey(subjectId)) return;
    setState(() => _loadingMap[subjectId] = true);
    try {
      final assignments = await ref
          .read(subjectsRepositoryProvider)
          .fetchSubjectAssignments(subjectId);
      if (mounted) {
        setState(() {
          _cache[subjectId] = assignments;
          _loadingMap.remove(subjectId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMap[subjectId] = e.toString();
          _loadingMap.remove(subjectId);
        });
      }
    }
  }

  void _toggle(int subjectId) {
    setState(() {
      if (_expanded.contains(subjectId)) {
        _expanded.remove(subjectId);
      } else {
        _expanded.add(subjectId);
        _loadAssignments(subjectId);
      }
    });
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
            data: (list) => _buildContent(list),
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
      child: Row(children: [
        const Text('Предметы',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => ref.read(subjectsProvider.notifier).load(),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Обновить', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ]),
    );
  }

  Widget _buildContent(List<Subject> subjects) {
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
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    _buildTableHeader(),
                    ...subjects.map((s) => _buildSubjectRow(s)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
      child: Row(children: [
        const Expanded(
          child: Text('Название',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
        ),
        SizedBox(
          width: 120,
          child: Text('Назначений',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
        ),
        const SizedBox(width: 160),
      ]),
    );
  }

  Widget _buildSubjectRow(Subject subject) {
    final isExpanded = _expanded.contains(subject.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border:
                Border(top: BorderSide(color: Colors.grey.shade100)),
          ),
          child: InkWell(
            onTap: () => _toggle(subject.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              child: Row(children: [
                // Название
                Expanded(
                  child: Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.menu_book_rounded,
                          size: 17, color: Color(0xFFD97706)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(subject.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827))),
                    ),
                  ]),
                ),
                // Назначений
                SizedBox(
                  width: 120,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
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
                ),
                // Действия
                SizedBox(
                  width: 160,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: IconButton(
                          tooltip: isExpanded
                              ? 'Свернуть'
                              : 'Показать преподавателей',
                          icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 22),
                          color: const Color(0xFF1D4ED8),
                          onPressed: () => _toggle(subject.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Назначить преподавателя',
                        icon: const Icon(Icons.person_add_outlined,
                            size: 18),
                        color: const Color(0xFF059669),
                        onPressed: () =>
                            _showAssignTeacherDialog(context, subject),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                      IconButton(
                        tooltip: 'Переименовать',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: const Color(0xFF1E3A5F),
                        onPressed: () =>
                            _showRenameDialog(context, subject),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18),
                        color: const Color(0xFFDC2626),
                        onPressed: () =>
                            _showDeleteDialog(context, subject),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
        // Inline expanded content
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: isExpanded
              ? _buildExpandedContent(subject)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildExpandedContent(Subject subject) {
    final isLoading = _loadingMap[subject.id] == true;
    final error = _errorMap[subject.id];
    final assignments = _cache[subject.id];

    Widget body;

    if (isLoading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(error,
                  style: const TextStyle(
                      color: Colors.red, fontSize: 13))),
          TextButton(
              onPressed: () {
                _errorMap.remove(subject.id);
                _loadAssignments(subject.id);
              },
              child: const Text('Повторить')),
        ]),
      );
    } else if (assignments == null || assignments.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Text('Преподаватели не назначены',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      );
    } else {
      final sorted = [...assignments]
        ..sort((a, b) => a.teacherName.compareTo(b.teacherName));

      body = Column(
        children: sorted.map((a) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.orange.shade50)),
            ),
            child: Row(children: [
              // Аватар
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                child: Text(
                  a.teacherName.isNotEmpty ? a.teacherName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A5F)),
                ),
              ),
              const SizedBox(width: 10),
              // ФИО преподавателя
              Expanded(
                flex: 3,
                child: Text(a.teacherName,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111827))),
              ),
              // Стрелка
              const Icon(Icons.arrow_right_alt_rounded,
                  size: 18, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 8),
              // Группа
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.group_outlined,
                      size: 12, color: Color(0xFF059669)),
                  const SizedBox(width: 4),
                  Text(a.groupName,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF059669),
                          fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(width: 8),
              // Кнопка редактировать
              IconButton(
                tooltip: 'Изменить назначение',
                icon: const Icon(Icons.edit_outlined, size: 16),
                color: const Color(0xFF1E3A5F),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () =>
                    _showEditAssignmentDialog(context, subject, a),
              ),
              // Кнопка удалить
              IconButton(
                tooltip: 'Снять назначение',
                icon: const Icon(Icons.person_remove_outlined, size: 16),
                color: const Color(0xFFDC2626),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () =>
                    _confirmRemoveAssignment(context, subject, a),
              ),
            ]),
          );
        }).toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF5),
        border: Border(
          top: BorderSide(color: Colors.orange.shade50),
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: body,
    );
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  Future<void> _showEditAssignmentDialog(
      BuildContext context, Subject subject, SubjectAssignment assignment) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 480,
          child: _EditAssignmentDialog(subject: subject, assignment: assignment),
        ),
      ),
    );
    // Обновляем только если было реальное сохранение
    if (saved == true) {
      setState(() => _cache.remove(subject.id));
      ref.read(subjectsProvider.notifier).load();
    }
  }

  Future<void> _confirmRemoveAssignment(
      BuildContext context, Subject subject, SubjectAssignment assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.person_remove_outlined, color: Color(0xFFF59E0B)),
          SizedBox(width: 10),
          Text('Снять назначение?', style: TextStyle(fontSize: 18)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF4B5563), height: 1.5),
            children: [
              TextSpan(
                  text: assignment.teacherName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(text: ' будет снят с группы '),
              TextSpan(
                  text: assignment.groupName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(
                  text: '.\n\nПреподаватель будет удалён из чата группы, '
                      'студенты и история сообщений останутся.'),
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
            child: const Text('Снять'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(subjectsRepositoryProvider)
          .removeAssignment(assignment.personId, assignment.id);
      setState(() => _cache.remove(subject.id));
      ref.read(subjectsProvider.notifier).load();
      if (context.mounted) _showSnack(context, 'Назначение снято', true);
    } catch (e) {
      if (context.mounted) _showSnack(context, e.toString(), false);
    }
  }

  Future<void> _showAssignTeacherDialog(
      BuildContext context, Subject subject) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 480,
          child: _AssignTeacherDialog(subject: subject),
        ),
      ),
    );
    // Сбрасываем кэш чтобы перезагрузить назначения
    setState(() => _cache.remove(subject.id));
    ref.read(subjectsProvider.notifier).load();
  }

  Future<void> _showRenameDialog(
      BuildContext context, Subject subject) async {
    final ctrl = TextEditingController(text: subject.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
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
    setState(() {
      _cache.remove(subject.id);
      _expanded.remove(subject.id);
    });
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
      backgroundColor:
          ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }
}

// ── Add subject card ──────────────────────────────────────────────────────────

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
        child: Row(children: [
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
              label:
                  const Text('Добавить', style: TextStyle(fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Edit assignment dialog ────────────────────────────────────────────────────

class _EditAssignmentDialog extends ConsumerStatefulWidget {
  final Subject subject;
  final SubjectAssignment assignment;
  const _EditAssignmentDialog(
      {required this.subject, required this.assignment});

  @override
  ConsumerState<_EditAssignmentDialog> createState() =>
      _EditAssignmentDialogState();
}

class _EditAssignmentDialogState
    extends ConsumerState<_EditAssignmentDialog> {
  List<Person> _teachers = [];
  List<GroupItem> _groups = [];
  bool _loading = true;
  String? _loadError;

  late Person? _selectedTeacher;
  late GroupItem? _selectedGroup;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final teachers = await ref.read(peopleRepositoryProvider).fetchPeople(role: 'teacher');
      final groups   = await ref.read(groupsRepositoryProvider).fetchGroups();
      if (mounted) {
        setState(() {
          _teachers = teachers;
          _groups   = groups;
          // Предвыбираем текущие значения
          _selectedTeacher = teachers.where(
              (t) => t.id == widget.assignment.personId).firstOrNull;
          _selectedGroup = groups.where(
              (g) => g.name == widget.assignment.groupName).firstOrNull;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _loading = false; });
    }
  }

  bool get _hasChanges =>
      _selectedTeacher?.id != widget.assignment.personId ||
      _selectedGroup?.name != widget.assignment.groupName;

  Future<void> _save() async {
    if (!_hasChanges || _selectedTeacher == null || _selectedGroup == null) return;
    setState(() { _saving = true; _saveError = null; });
    try {
      await ref.read(subjectsRepositoryProvider).updateAssignment(
        widget.assignment.personId,
        widget.assignment.id,
        newPersonId: _selectedTeacher!.id != widget.assignment.personId
            ? _selectedTeacher!.id
            : null,
        newGroupName: _selectedGroup!.name != widget.assignment.groupName
            ? _selectedGroup!.name
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Назначение обновлено'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
        Navigator.pop(context, true); // true = сохранение произошло
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _saveError = e.toString(); });
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
            const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Изменить назначение',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    widget.subject.name,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
              : _loadError != null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 36),
                      const SizedBox(height: 8),
                      Text(_loadError!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить')),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      // Текущее → новое (визуальная подсказка)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 15, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Сейчас: ${widget.assignment.teacherName} → ${widget.assignment.groupName}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      // Преподаватель
                      DropdownButtonFormField<Person>(
                        value: _selectedTeacher,
                        decoration: InputDecoration(
                          labelText: 'Преподаватель',
                          prefixIcon: const Icon(Icons.person_outlined, size: 20),
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
                      // Группа
                      DropdownButtonFormField<GroupItem>(
                        value: _selectedGroup,
                        decoration: InputDecoration(
                          labelText: 'Группа',
                          prefixIcon: const Icon(Icons.group_outlined, size: 20),
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
                      if (_saveError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade600, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_saveError!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red.shade700)),
                            ),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: (!_hasChanges || _saving) ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.grey.shade300,
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
                              : const Icon(Icons.save_outlined, size: 18),
                          label: Text(_saving ? 'Сохранение...' : 'Сохранить'),
                        ),
                      ),
                    ]),
        ),
      ],
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
      final groups = await groupsRepo.fetchGroups();
      if (mounted) {
        setState(() {
          _teachers = teachers;
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ));
        setState(() {
          _selectedTeacher = null;
          _selectedGroup = null;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
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
              icon: const Icon(Icons.close,
                  color: Colors.white70, size: 20),
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
                              borderRadius:
                                  BorderRadius.circular(10)),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                        ),
                        items: _teachers
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.fullName,
                                      overflow:
                                          TextOverflow.ellipsis),
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
                            backgroundColor:
                                const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
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
