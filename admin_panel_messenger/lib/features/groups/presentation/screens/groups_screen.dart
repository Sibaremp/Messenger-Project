import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/groups_provider.dart';
import '../../../../shared/models/group_item.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGroups = ref.watch(groupsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(ref),
        Expanded(
          child: asyncGroups.when(
            data: (groups) => _buildContent(context, ref, groups),
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildError(context, ref, e.toString()),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(WidgetRef ref) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Row(
        children: [
          const Text('Группы',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827))),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(groupsProvider.notifier).load(),
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

  Widget _buildContent(
      BuildContext context, WidgetRef ref, List<GroupItem> groups) {
    if (groups.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.group_outlined,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Группы не найдены',
              style:
                  TextStyle(fontSize: 16, color: Colors.grey.shade400)),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Card(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            child: DataTable(
              columnSpacing: 16,
              horizontalMargin: 24,
              headingRowHeight: 44,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 56,
              headingRowColor:
                  WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              dividerThickness: 1,
              columns: const [
                DataColumn(label: _ColHeader('Группа')),
                DataColumn(
                    label: _ColHeader('Участники'), numeric: true),
                DataColumn(
                    label: _ColHeader('Аккаунты'), numeric: true),
                DataColumn(label: _ColHeader('Действия')),
              ],
              rows: groups
                  .map((g) => _buildRow(context, ref, g))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(
      BuildContext context, WidgetRef ref, GroupItem group) {
    return DataRow(cells: [
      DataCell(
        Row(mainAxisSize: MainAxisSize.min, children: [
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
      DataCell(_CountChip(count: group.peopleCount, color: Colors.blue)),
      DataCell(_CountChip(
          count: group.userCount,
          color: group.userCount > 0 ? Colors.green : Colors.grey)),
      DataCell(
        TextButton.icon(
          onPressed: () => _showDeleteDialog(context, ref, group),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Удалить', style: TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      ),
    ]);
  }

  Future<void> _showDeleteDialog(
      BuildContext context, WidgetRef ref, GroupItem group) async {
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
                      text: ' будет удалена вместе со всеми данными:'),
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

    final ok =
        await ref.read(groupsProvider.notifier).delete(group.name);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Группа "${group.name}" удалена'
          : 'Ошибка при удалении'),
      backgroundColor:
          ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  Widget _buildError(
      BuildContext context, WidgetRef ref, String message) {
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
              ref.read(groupsProvider.notifier).load(),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      ]),
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
