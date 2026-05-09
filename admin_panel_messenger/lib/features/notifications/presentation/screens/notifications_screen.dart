import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notifications_provider.dart';
import '../../../../shared/models/admin_notification.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends ConsumerState<NotificationsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _target = 'all';
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(sendNotificationProvider.notifier).send(
          title: _titleCtrl.text.trim(),
          body: _bodyCtrl.text.trim(),
          target: _target,
        );
    final state = ref.read(sendNotificationProvider);
    if (state.status == SendStatus.success && mounted) {
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() => _target = 'all');
      ref.read(sendNotificationProvider.notifier).reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Row(
            children: [
              const Text('Уведомления',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827))),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(notificationsHistoryProvider.notifier)
                    .load(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Обновить',
                    style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ComposeCard(
                  formKey: _formKey,
                  titleCtrl: _titleCtrl,
                  bodyCtrl: _bodyCtrl,
                  target: _target,
                  onTargetChanged: (v) => setState(() => _target = v),
                  onSend: _send,
                ),
                const SizedBox(height: 28),
                const Text('История',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
                const SizedBox(height: 14),
                _HistorySection(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Compose card ───────────────────────────────────────────────────────────────

class _ComposeCard extends ConsumerWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final String target;
  final void Function(String) onTargetChanged;
  final VoidCallback onSend;

  const _ComposeCard({
    required this.formKey,
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.target,
    required this.onTargetChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendState = ref.watch(sendNotificationProvider);
    final loading = sendState.status == SendStatus.loading;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.send_rounded, color: Color(0xFF1E3A5F), size: 20),
                SizedBox(width: 10),
                Text('Новое уведомление',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827))),
              ]),
              const SizedBox(height: 20),
              TextFormField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Заголовок',
                  prefixIcon:
                      const Icon(Icons.title_rounded, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Введите заголовок'
                        : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: bodyCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Текст уведомления',
                  prefixIcon:
                      const Icon(Icons.message_outlined, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Введите текст'
                        : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Кому: ',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151))),
                  const SizedBox(width: 12),
                  SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 13),
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: 'all',
                          label: Text('Все'),
                          icon: Icon(Icons.people_alt_outlined, size: 16)),
                      ButtonSegment(
                          value: 'students',
                          label: Text('Студенты'),
                          icon: Icon(Icons.school_outlined, size: 16)),
                      ButtonSegment(
                          value: 'teachers',
                          label: Text('Преподаватели'),
                          icon: Icon(Icons.person_outlined, size: 16)),
                    ],
                    selected: {target},
                    onSelectionChanged: (v) => onTargetChanged(v.first),
                  ),
                  const Spacer(),
                  if (sendState.status == SendStatus.error)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(sendState.error ?? 'Ошибка',
                            style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12)),
                      ),
                    ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: loading ? null : onSend,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20),
                      ),
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(loading ? 'Отправка...' : 'Отправить',
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── History section ────────────────────────────────────────────────────────────

class _HistorySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncHistory = ref.watch(notificationsHistoryProvider);

    return asyncHistory.when(
      data: (list) => list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none_outlined,
                      size: 52, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('История пуста',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 14)),
                ]),
              ),
            )
          : Card(
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
                      DataColumn(label: _ColHeader('Заголовок')),
                      DataColumn(label: _ColHeader('Текст')),
                      DataColumn(label: _ColHeader('Кому')),
                      DataColumn(label: _ColHeader('Дата')),
                      DataColumn(label: _ColHeader('')),
                    ],
                    rows: list
                        .map((n) => _buildRow(context, ref, n))
                        .toList(),
                  ),
                ),
              ),
            ),
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(e.toString(),
            style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, WidgetRef ref,
      AdminNotification n) {
    return DataRow(cells: [
      DataCell(Text(n.title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827)))),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(n.body,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280))),
        ),
      ),
      DataCell(_TargetBadge(target: n.target)),
      DataCell(Text(n.formattedDate,
          style: const TextStyle(
              fontSize: 12, color: Color(0xFF9CA3AF)))),
      DataCell(
        IconButton(
          tooltip: 'Удалить из истории',
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          color: const Color(0xFFDC2626),
          onPressed: () async {
            final ok = await ref
                .read(notificationsHistoryProvider.notifier)
                .delete(n.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Запись удалена'
                    : 'Ошибка при удалении'),
                backgroundColor: ok
                    ? Colors.green.shade700
                    : Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ));
            }
          },
        ),
      ),
    ]);
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

class _TargetBadge extends StatelessWidget {
  final String target;
  const _TargetBadge({required this.target});

  @override
  Widget build(BuildContext context) {
    final (label, bg, border, text) = switch (target.toLowerCase()) {
      'students' => (
          'Студенты',
          const Color(0xFFEFF6FF),
          const Color(0xFFBFDBFE),
          const Color(0xFF1D4ED8),
        ),
      'teachers' => (
          'Преподаватели',
          const Color(0xFFF5F3FF),
          const Color(0xFFDDD6FE),
          const Color(0xFF7C3AED),
        ),
      _ => (
          'Все',
          const Color(0xFFF0FDF4),
          const Color(0xFFBBF7D0),
          const Color(0xFF16A34A),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: text,
              fontWeight: FontWeight.w500)),
    );
  }
}
