import 'package:flutter/material.dart';
import '../models.dart';

// ─── Секция выбора участников с поиском, фильтрацией по группам и
//     быстрым выбором всей группы.
//
// Используется в диалогах создания группы/сообщества (мобильный и desktop).
// ─────────────────────────────────────────────────────────────────────────────

class MemberPickerSection extends StatefulWidget {
  final List<AppContact> contacts;

  /// Текущий набор выбранных логинов. Снаружи передаётся Set, изменяется
  /// через [onToggle].
  final Set<String> selected;

  /// Вызывается при изменении выбора: (login, isSelected).
  final void Function(String login, bool selected) onToggle;

  const MemberPickerSection({
    super.key,
    required this.contacts,
    required this.selected,
    required this.onToggle,
  });

  @override
  State<MemberPickerSection> createState() => _MemberPickerSectionState();
}

class _MemberPickerSectionState extends State<MemberPickerSection> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Группы, выбранные в фильтре.  Пустой = все группы видны.
  final Set<String> _activeGroups = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Вычисляемые свойства ──────────────────────────────────────────────────

  List<String> get _allGroups {
    final groups = widget.contacts
        .map((c) => c.group)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return groups;
  }

  /// Возвращает true, если [c] соответствует поисковому запросу.
  bool _matchesQuery(AppContact c) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (c.name.toLowerCase().contains(q)) return true;
    if (c.displayName != null) {
      // Любое слово ФИО содержит запрос
      final words = c.displayName!.toLowerCase().split(RegExp(r'\s+'));
      if (words.any((w) => w.contains(q))) return true;
    }
    if (c.group?.toLowerCase().contains(q) ?? false) return true;
    return false;
  }

  /// Группы, которые показываются с учётом фильтра _activeGroups.
  List<String> get _visibleGroups {
    final all = _allGroups;
    if (_activeGroups.isEmpty) return all;
    return all.where((g) => _activeGroups.contains(g)).toList();
  }

  List<AppContact> _contactsInGroup(String group) =>
      widget.contacts
          .where((c) => c.group == group && _matchesQuery(c))
          .toList();

  List<AppContact> get _ungrouped =>
      widget.contacts
          .where((c) =>
              c.group == null &&
              (_activeGroups.isEmpty) &&
              _matchesQuery(c))
          .toList();

  bool _groupFullySelected(String group) {
    final cs = _contactsInGroup(group);
    return cs.isNotEmpty && cs.every((c) => widget.selected.contains(c.name));
  }

  bool _groupPartiallySelected(String group) {
    final cs = _contactsInGroup(group);
    return cs.any((c) => widget.selected.contains(c.name)) &&
        !_groupFullySelected(group);
  }

  void _toggleGroup(String group) {
    final cs = _contactsInGroup(group);
    if (_groupFullySelected(group)) {
      for (final c in cs) widget.onToggle(c.name, false);
    } else {
      for (final c in cs) widget.onToggle(c.name, true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final allGroups = _allGroups;
    final visibleGroups = _visibleGroups;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Заголовок + счётчик ──────────────────────────────────────────
        Row(
          children: [
            const Text(
              'Добавить участников',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            if (widget.selected.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${widget.selected.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // ── Строка поиска ────────────────────────────────────────────────
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: 'Поиск по ФИО или группе…',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 13,
            ),
            prefixIcon: Icon(Icons.search,
                size: 18, color: isDark ? Colors.white38 : Colors.black38),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        size: 16,
                        color: isDark ? Colors.white54 : Colors.black45),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    padding: EdgeInsets.zero,
                  )
                : null,
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFF2F2F2),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            isDense: true,
          ),
        ),

        // ── Фильтр по группам (горизонтальные chips) ─────────────────────
        if (allGroups.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                _GroupChip(
                  label: 'Все',
                  active: _activeGroups.isEmpty,
                  color: primary,
                  isDark: isDark,
                  onTap: () => setState(() => _activeGroups.clear()),
                ),
                const SizedBox(width: 6),
                ...allGroups.map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _GroupChip(
                      label: g,
                      active: _activeGroups.contains(g),
                      color: primary,
                      isDark: isDark,
                      onTap: () => setState(() {
                        if (_activeGroups.contains(g)) {
                          _activeGroups.remove(g);
                        } else {
                          _activeGroups.add(g);
                        }
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 6),

        // ── Список с группировкой ────────────────────────────────────────
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Группированные контакты
                ...visibleGroups.map((group) {
                  final cs = _contactsInGroup(group);
                  if (cs.isEmpty) return const SizedBox.shrink();
                  final full = _groupFullySelected(group);
                  final partial = _groupPartiallySelected(group);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок группы — тап выбирает/снимает всю группу
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() => _toggleGroup(group)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: full
                                      ? true
                                      : (partial ? null : false),
                                  tristate: true,
                                  activeColor: primary,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (_) =>
                                      setState(() => _toggleGroup(group)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                group,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: primary,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(${cs.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Участники группы
                      ...cs.map(
                        (c) => _ContactCheckTile(
                          contact: c,
                          selected: widget.selected.contains(c.name),
                          onToggle: (v) => widget.onToggle(c.name, v),
                          isDark: isDark,
                          primary: primary,
                          indent: true,
                        ),
                      ),
                    ],
                  );
                }),
                // Контакты без группы (показываются только при «Все»)
                ..._ungrouped.map(
                  (c) => _ContactCheckTile(
                    contact: c,
                    selected: widget.selected.contains(c.name),
                    onToggle: (v) => widget.onToggle(c.name, v),
                    isDark: isDark,
                    primary: primary,
                  ),
                ),
                // Пусто
                if (visibleGroups.every((g) => _contactsInGroup(g).isEmpty) &&
                    _ungrouped.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'Никого не найдено',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
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

// ─── Chip фильтра группы ──────────────────────────────────────────────────────

class _GroupChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _GroupChip({
    required this.label,
    required this.active,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.18)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                active ? color.withValues(alpha: 0.55) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active
                ? color
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }
}

// ─── Строка контакта с чекбоксом ─────────────────────────────────────────────

class _ContactCheckTile extends StatelessWidget {
  final AppContact contact;
  final bool selected;
  final void Function(bool) onToggle;
  final bool isDark;
  final Color primary;
  /// Добавляет отступ слева (для контактов внутри группы).
  final bool indent;

  const _ContactCheckTile({
    required this.contact,
    required this.selected,
    required this.onToggle,
    required this.isDark,
    required this.primary,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    // Показываем ФИО, если есть; иначе логин
    final displayName =
        (contact.displayName?.isNotEmpty == true) ? contact.displayName! : contact.name;
    final showLogin = contact.displayName?.isNotEmpty == true;

    return InkWell(
      onTap: () => onToggle(!selected),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent ? 14 : 2, 3, 2, 3),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: selected,
                activeColor: primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onToggle(v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showLogin)
                    Text(
                      contact.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
