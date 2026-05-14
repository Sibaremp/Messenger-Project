import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/groups_provider.dart';
import '../../../../shared/models/group_item.dart';
import '../../../../shared/models/person.dart';
import '../../../../features/people/data/people_repository.dart';

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  // Inline expansion state
  final Set<String> _expanded = {};
  final Map<String, List<Person>> _cache = {};
  final Map<String, bool> _loadingMap = {};
  final Map<String, String?> _errorMap = {};

  Future<void> _loadMembers(String groupName) async {
    if (_cache.containsKey(groupName)) return;
    setState(() => _loadingMap[groupName] = true);
    try {
      final people = await ref
          .read(peopleRepositoryProvider)
          .fetchPeople(group: groupName);
      // Показываем только студентов — у преподавателей нет группы как участников
      final students = people
          .where((p) => p.role.toLowerCase() == 'student')
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
      if (mounted) {
        setState(() {
          _cache[groupName] = students;
          _loadingMap.remove(groupName);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMap[groupName] = e.toString();
          _loadingMap.remove(groupName);
        });
      }
    }
  }

  void _toggle(String groupName) {
    setState(() {
      if (_expanded.contains(groupName)) {
        _expanded.remove(groupName);
      } else {
        _expanded.add(groupName);
        _loadMembers(groupName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncGroups = ref.watch(groupsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(),
        Expanded(
          child: asyncGroups.when(
            data: (groups) => _buildContent(groups),
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
        const Text('Группы',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => ref.read(groupsProvider.notifier).load(),
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

  Widget _buildContent(List<GroupItem> groups) {
    if (groups.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.group_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Группы не найдены',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Container(
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
              ...groups.map((g) => _buildGroupRow(g)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
      child: Row(children: [
        const Expanded(
          child: Text('Группа',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
        ),
        SizedBox(
          width: 110,
          child: Text('Участники',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
        ),
        SizedBox(
          width: 110,
          child: Text('Аккаунты',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
        ),
        const SizedBox(width: 100),
      ]),
    );
  }

  Widget _buildGroupRow(GroupItem group) {
    final isExpanded = _expanded.contains(group.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey.shade100)),
          ),
          child: InkWell(
            onTap: () => _toggle(group.name),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(children: [
                // Группа
                Expanded(
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.group_outlined,
                          size: 18, color: Color(0xFF1E3A5F)),
                    ),
                    const SizedBox(width: 12),
                    Text(group.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111827))),
                  ]),
                ),
                // Участники
                SizedBox(
                  width: 110,
                  child: Center(
                    child: _CountChip(
                        count: group.peopleCount, color: Colors.blue),
                  ),
                ),
                // Аккаунты
                SizedBox(
                  width: 110,
                  child: Center(
                    child: _CountChip(
                        count: group.userCount,
                        color: group.userCount > 0
                            ? Colors.green
                            : Colors.grey),
                  ),
                ),
                // Действия
                SizedBox(
                  width: 100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: IconButton(
                          tooltip: isExpanded ? 'Свернуть' : 'Показать участников',
                          icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 22),
                          color: const Color(0xFF1D4ED8),
                          onPressed: () => _toggle(group.name),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18),
                        color: const Color(0xFFDC2626),
                        onPressed: () =>
                            _showDeleteDialog(context, group),
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
              ? _buildExpandedContent(group)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildExpandedContent(GroupItem group) {
    final isLoading = _loadingMap[group.name] == true;
    final error = _errorMap[group.name];
    final members = _cache[group.name];

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
                  style: const TextStyle(color: Colors.red, fontSize: 13))),
          TextButton(
              onPressed: () {
                _errorMap.remove(group.name);
                _loadMembers(group.name);
              },
              child: const Text('Повторить')),
        ]),
      );
    } else if (members == null || members.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Text('Студенты в группе не найдены',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(44),
                1: FlexColumnWidth(1),
                2: IntrinsicColumnWidth(),
              },
              children: [
                // Header
                TableRow(
                  decoration:
                      const BoxDecoration(color: Color(0xFFF0F4F8)),
                  children: [
                    const SizedBox.shrink(),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 0, vertical: 9),
                      child: Text('ФИО',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280))),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      child: Text('Аккаунт',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280))),
                    ),
                  ],
                ),
                ...members.map(_buildStudentRow),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFF),
        border: Border(
          top: BorderSide(color: Colors.blue.shade50),
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: body,
    );
  }

  TableRow _buildStudentRow(Person p) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: CircleAvatar(
            radius: 13,
            backgroundColor:
                const Color(0xFF1E3A5F).withValues(alpha: 0.1),
            child: Text(
              p.fullName.isNotEmpty ? p.fullName[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E3A5F)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(p.fullName,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF111827))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: p.hasUser
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text('Есть',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500)),
                ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.radio_button_unchecked,
                      size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Нет',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500)),
                ]),
        ),
      ],
    );
  }

  Future<void> _showDeleteDialog(
      BuildContext context, GroupItem group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
          SizedBox(width: 10),
          Text('Удалить группу?', style: TextStyle(fontSize: 18)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4B5563),
                    height: 1.6),
                children: [
                  const TextSpan(text: 'Группа '),
                  TextSpan(
                      text: '"${group.name}"',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                  const TextSpan(
                      text:
                          ' будет удалена вместе со всеми данными:'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _DeleteInfoRow(
                icon: Icons.person,
                color: Colors.blue,
                text: '${group.peopleCount} участников'),
            const SizedBox(height: 6),
            _DeleteInfoRow(
                icon: Icons.manage_accounts,
                color: Colors.orange,
                text: '${group.userCount} аккаунтов'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.red.shade600),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Это действие необратимо. Чаты и сессии будут удалены.',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF991B1B)),
                  ),
                ),
              ]),
            ),
          ],
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
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Убираем из кэша при удалении
    setState(() {
      _cache.remove(group.name);
      _expanded.remove(group.name);
    });

    final ok = await ref.read(groupsProvider.notifier).delete(group.name);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Группа "${group.name}" удалена'
          : 'Ошибка при удалении'),
      backgroundColor:
          ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
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
          onPressed: () => ref.read(groupsProvider.notifier).load(),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      ]),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  final int count;
  final MaterialColor color;

  const _CountChip({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Text('$count',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color.shade700)),
    );
  }
}

class _DeleteInfoRow extends StatelessWidget {
  final IconData icon;
  final MaterialColor color;
  final String text;

  const _DeleteInfoRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: color.shade600),
      const SizedBox(width: 8),
      Text(text,
          style: TextStyle(
              fontSize: 13,
              color: color.shade700,
              fontWeight: FontWeight.w500)),
    ]);
  }
}
