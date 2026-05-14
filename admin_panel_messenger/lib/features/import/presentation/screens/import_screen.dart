import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/import_provider.dart';
import '../../data/import_repository.dart';

class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: const Row(
            children: [
              Text(
                'Импорт участников',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _UploadCard(importState: state),
                    const SizedBox(height: 20),
                    const _JsonFormatCard(),
                    const SizedBox(height: 16),
                    const _ExcelFormatCard(),
                    if (state.status == ImportStatus.success &&
                        state.result != null) ...[
                      const SizedBox(height: 20),
                      _ResultCard(
                        result: state.result!,
                        onDismiss: () =>
                            ref.read(importProvider.notifier).reset(),
                      ),
                    ],
                    if (state.status == ImportStatus.error &&
                        state.error != null) ...[
                      const SizedBox(height: 20),
                      _ErrorCard(message: state.error!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadCard extends ConsumerWidget {
  final ImportState importState;

  const _UploadCard({required this.importState});

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    await ref
        .read(importProvider.notifier)
        .importFile(file.name, file.bytes!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = importState.status == ImportStatus.loading;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F).withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                size: 44,
                color: Color(0xFF1E3A5F),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Загрузка файла',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            Text(
              'Поддерживаемые форматы: JSON, XLSX, XLS',
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Файл будет обработан на сервере',
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            const SizedBox(height: 28),
            if (importState.fileName != null) ...[
              _FileNameChip(name: importState.fileName!),
              const SizedBox(height: 20),
            ],
            SizedBox(
              height: 48,
              width: 200,
              child: ElevatedButton.icon(
                onPressed:
                    loading ? null : () => _pick(context, ref),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF1E3A5F).withValues(alpha: 0.55),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.folder_open_outlined, size: 18),
                label: Text(
                  loading ? 'Загрузка...' : 'Выбрать файл',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── JSON format guide card ────────────────────────────────────────────────────

class _JsonFormatCard extends StatelessWidget {
  const _JsonFormatCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.data_object,
                  color: Color(0xFF1D4ED8), size: 20),
              SizedBox(width: 10),
              Text(
                'Структура JSON файла',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Файл должен содержать массив объектов',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                '[\n'
                '  {\n'
                '    "lastName": "Иванов",\n'
                '    "firstName": "Иван",\n'
                '    "middleName": "Иванович",  // необязательно\n'
                '    "role": "student",         // "student" или "teacher"\n'
                '    "group": "ПО 22-2"         // необязательно\n'
                '  }\n'
                ']',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF374151),
                    height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Excel format guide card ───────────────────────────────────────────────────

class _ExcelFormatCard extends StatelessWidget {
  const _ExcelFormatCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.table_chart,
                  color: Color(0xFF059669), size: 20),
              SizedBox(width: 10),
              Text(
                'Структура Excel файла',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              'Первая строка — заголовки колонок',
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Table(
                border: TableBorder.all(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(3),
                },
                children: [
                  // Header
                  const TableRow(
                    decoration: BoxDecoration(
                        color: Color(0xFFF8FAFC)),
                    children: [
                      _TableCell('Колонка', isHeader: true),
                      _TableCell('Обязательно', isHeader: true),
                      _TableCell('Значения', isHeader: true),
                    ],
                  ),
                  // Rows
                  _excelRow('lastName', '✓', 'Фамилия'),
                  _excelRow('firstName', '✓', 'Имя'),
                  _excelRow(
                      'middleName', '—', 'Отчество (необязательно)'),
                  _excelRow(
                      'role', '✓', 'student / teacher'),
                  _excelRow('group', '—', 'Название группы'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TableRow _excelRow(String col, String required, String values) {
    return TableRow(
      children: [
        _TableCell(col, mono: true),
        _TableCell(required,
            color: required == '✓'
                ? const Color(0xFF059669)
                : Colors.grey),
        _TableCell(values),
      ],
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool mono;
  final Color? color;

  const _TableCell(this.text,
      {this.isHeader = false, this.mono = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
          fontFamily: mono ? 'monospace' : null,
          color: color ??
              (isHeader
                  ? const Color(0xFF374151)
                  : const Color(0xFF4B5563)),
        ),
      ),
    );
  }
}

class _FileNameChip extends StatelessWidget {
  final String name;

  const _FileNameChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              size: 16, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 8),
          Text(
            name,
            style: const TextStyle(
                color: Color(0xFF1D4ED8),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ImportResult result;
  final VoidCallback onDismiss;

  const _ResultCard({required this.result, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF0FDF4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFBBF7D0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF16A34A)),
                const SizedBox(width: 10),
                const Text(
                  'Импорт выполнен успешно',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF166534)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close,
                      size: 18, color: Color(0xFF4B5563)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.add_circle_rounded,
                    iconColor: const Color(0xFF16A34A),
                    value: result.added.toString(),
                    label: 'Добавлено',
                    valueColor: const Color(0xFF166534),
                    bgColor: const Color(0xFFDCFCE7),
                    borderColor: const Color(0xFFBBF7D0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.skip_next_rounded,
                    iconColor: const Color(0xFFD97706),
                    value: result.skipped.toString(),
                    label: 'Пропущено',
                    valueColor: const Color(0xFF92400E),
                    bgColor: const Color(0xFFFEF3C7),
                    borderColor: const Color(0xFFFDE68A),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final Color valueColor;
  final Color bgColor;
  final Color borderColor;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.valueColor,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: valueColor),
              ),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: valueColor.withValues(alpha: 0.75))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFEF2F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFECACA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFDC2626), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ошибка импорта',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF991B1B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                        color: Color(0xFFB91C1C), fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
