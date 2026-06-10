import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../features/people/data/people_repository.dart';
import '../../../../features/users/data/users_repository.dart';
import '../../../../features/groups/data/groups_repository.dart';
import '../../../../features/subjects/data/subjects_repository.dart';
import '../../../../features/dashboard/data/stats_repository.dart';
import '../../../../shared/models/person.dart';
import '../../../../shared/models/subject.dart';

// ── Data models ───────────────────────────────────────────────────────────────

/// На широких экранах раскладывает детей в ряд (с заданными flex-весами),
/// на узких — переключается в колонку (для мобильного браузера/окна).
class _ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final List<int>? flexes;
  final double spacing;
  final double breakpoint;

  const _ResponsiveRow({
    required this.children,
    this.flexes,
    this.spacing = 16,
    this.breakpoint = 720,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < breakpoint;
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(
              flex: flexes != null ? flexes![i] : 1,
              child: children[i],
            ),
          ],
        ],
      );
    });
  }
}

class _DashboardStats {
  final int people;
  final int students;
  final int teachers;
  final int users;
  final int groups;
  final int subjects;
  final List<Subject> topSubjects;

  const _DashboardStats({
    required this.people,
    required this.students,
    required this.teachers,
    required this.users,
    required this.groups,
    required this.subjects,
    required this.topSubjects,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _dashboardStatsProvider =
    FutureProvider.autoDispose<_DashboardStats>((ref) async {
  final peopleRepo   = ref.watch(peopleRepositoryProvider);
  final usersRepo    = ref.watch(usersRepositoryProvider);
  final groupsRepo   = ref.watch(groupsRepositoryProvider);
  final subjectsRepo = ref.watch(subjectsRepositoryProvider);

  final r = await Future.wait([
    peopleRepo.fetchPeople(),
    usersRepo.fetchUsers(),
    groupsRepo.fetchGroups(),
    subjectsRepo.fetchSubjects(),
  ]);

  final people   = r[0] as List<Person>;
  final users    = r[1];
  final groups   = r[2];
  final subjects = r[3] as List<Subject>;

  final students = people.where((p) => p.role.toLowerCase() == 'student').length;
  final teachers = people.length - students;

  final topSubjects = List<Subject>.from(subjects)
    ..sort((a, b) => b.groupsPerTeacher.compareTo(a.groupsPerTeacher));

  return _DashboardStats(
    people:      people.length,
    students:    students,
    teachers:    teachers,
    users:       users.length,
    groups:      groups.length,
    subjects:    subjects.length,
    topSubjects: topSubjects,
  );
});

// ── Stats providers ───────────────────────────────────────────────────────────

final _activityProvider =
    FutureProvider.autoDispose<List<ActivityPoint>>((ref) =>
        ref.watch(statsRepositoryProvider).fetchActivity(days: 14));

final _notifStatsProvider =
    FutureProvider.autoDispose<List<NotificationWeek>>((ref) =>
        ref.watch(statsRepositoryProvider).fetchNotificationStats(weeks: 8));

final _growthProvider =
    FutureProvider.autoDispose<List<GrowthPoint>>((ref) =>
        ref.watch(statsRepositoryProvider).fetchGrowth(days: 30));

// ── Screen ────────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        ref.invalidate(_dashboardStatsProvider);
        ref.invalidate(_activityProvider);
        ref.invalidate(_notifStatsProvider);
        ref.invalidate(_growthProvider);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncStats = ref.watch(_dashboardStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Row(children: [
            const Text('Главная',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
            const Spacer(),
            asyncStats.isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Tooltip(
                    message: 'Авто-обновление каждые 30 сек',
                    child: Icon(Icons.sync_rounded,
                        size: 18, color: Colors.grey.shade400),
                  ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {
                ref.invalidate(_dashboardStatsProvider);
                ref.invalidate(_activityProvider);
                ref.invalidate(_notifStatsProvider);
                ref.invalidate(_growthProvider);
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Обновить',
                  style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ]),
        ),
        // Content
        Expanded(
          child: asyncStats.when(
            data: (stats) => _buildBody(stats),
            loading: () => _buildLoadingBody(),
            error: (e, _) => _buildError(e.toString()),
          ),
        ),
      ],
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(_DashboardStats stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat cards
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(
                icon: Icons.people_alt_rounded,
                label: 'Участники',
                value: stats.people,
                color: const Color(0xFF2563EB),
                bg: const Color(0xFFEFF6FF),
              ),
              _StatCard(
                icon: Icons.manage_accounts_rounded,
                label: 'Пользователи',
                value: stats.users,
                color: const Color(0xFF7C3AED),
                bg: const Color(0xFFF5F3FF),
              ),
              _StatCard(
                icon: Icons.group_rounded,
                label: 'Группы',
                value: stats.groups,
                color: const Color(0xFF059669),
                bg: const Color(0xFFF0FDF4),
              ),
              _StatCard(
                icon: Icons.menu_book_rounded,
                label: 'Предметы',
                value: stats.subjects,
                color: const Color(0xFFD97706),
                bg: const Color(0xFFFFFBEB),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Summary table
          _buildSummaryTable(stats),
          const SizedBox(height: 32),

          // Statistics section header
          const Text('Статистика',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text('Данные на основе текущего состояния системы',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 16),

          // Real statistics row
          _ResponsiveRow(
            spacing: 16,
            children: [
              _CompositionCard(stats: stats),
              _TopSubjectsCard(subjects: stats.topSubjects),
            ],
            flexes: const [2, 3],
          ),
          const SizedBox(height: 16),

          // Real statistics row (from API)
          _ResponsiveRow(
            spacing: 16,
            children: [
              ref.watch(_activityProvider).when(
                data: (pts) => _ActivityCard(points: pts),
                loading: () => const _StatsCardSkeleton(height: 200),
                error: (e, _) => _StatsCardError(
                  title: 'Активность пользователей',
                  icon: Icons.bar_chart_rounded,
                  error: e.toString(),
                  onRetry: () => ref.invalidate(_activityProvider),
                ),
              ),
              ref.watch(_notifStatsProvider).when(
                data: (weeks) => _NotificationsCard(weeks: weeks),
                loading: () => const _StatsCardSkeleton(height: 200),
                error: (e, _) => _StatsCardError(
                  title: 'Уведомления',
                  icon: Icons.notifications_active_rounded,
                  error: e.toString(),
                  onRetry: () => ref.invalidate(_notifStatsProvider),
                ),
              ),
              ref.watch(_growthProvider).when(
                data: (pts) => _GrowthCard(points: pts),
                loading: () => const _StatsCardSkeleton(height: 200),
                error: (e, _) => _StatsCardError(
                  title: 'Новые участники',
                  icon: Icons.group_add_rounded,
                  error: e.toString(),
                  onRetry: () => ref.invalidate(_growthProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTable(_DashboardStats stats) {
    final rows = [
      (
        Icons.people_alt_rounded,
        'Участники',
        stats.people,
        const Color(0xFF2563EB),
        const Color(0xFFEFF6FF),
        'Студентов: ${stats.students} · Преподавателей: ${stats.teachers}. '
            'Всего зарегистрированных людей в системе.',
      ),
      (
        Icons.manage_accounts_rounded,
        'Пользователи',
        stats.users,
        const Color(0xFF7C3AED),
        const Color(0xFFF5F3FF),
        'Активные аккаунты мобильного приложения. '
            '${stats.people > 0 ? ((stats.users / stats.people * 100).round()) : 0}% участников имеют аккаунт.',
      ),
      (
        Icons.group_rounded,
        'Группы',
        stats.groups,
        const Color(0xFF059669),
        const Color(0xFFF0FDF4),
        'Учебные группы — в среднем '
            '${stats.groups > 0 ? (stats.students / stats.groups).toStringAsFixed(1) : "—"} студентов на группу.',
      ),
      (
        Icons.menu_book_rounded,
        'Предметы',
        stats.subjects,
        const Color(0xFFD97706),
        const Color(0xFFFFFBEB),
        'Учебные дисциплины. Всего назначений: '
            '${stats.topSubjects.fold(0, (s, x) => s + x.assignmentCount)}.',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(1),
            2: IntrinsicColumnWidth(),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  child: Text('Раздел',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280))),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Text('Описание',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280))),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  child: Text('Кол-во',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280))),
                ),
              ],
            ),
            ...rows.map((r) => TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: Colors.grey.shade100)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: r.$5,
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Icon(r.$1,
                                  size: 16, color: r.$4),
                            ),
                            const SizedBox(width: 10),
                            Text(r.$2,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827))),
                          ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Text(r.$6,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              height: 1.4)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Text('${r.$3}',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: r.$4)),
                    ),
                  ],
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(4, (_) => const _StatCardSkeleton()),
          ),
          const SizedBox(height: 20),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
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
          onPressed: () => ref.invalidate(_dashboardStatsProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      ]),
    );
  }
}

// ── Real stat cards ───────────────────────────────────────────────────────────

/// Состав участников: визуальная разбивка студенты / преподаватели
class _CompositionCard extends StatelessWidget {
  final _DashboardStats stats;
  const _CompositionCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.people;
    final studentFrac = total > 0 ? stats.students / total : 0.0;
    final teacherFrac = total > 0 ? stats.teachers / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.pie_chart_rounded,
                size: 18, color: Color(0xFF1E3A5F)),
            const SizedBox(width: 8),
            const Text('Состав участников',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827))),
          ]),
          const SizedBox(height: 4),
          Text('Соотношение студентов и преподавателей',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 20),
          if (total == 0)
            Center(
              child: Text('Нет данных',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade400)),
            )
          else ...[
            // Stacked bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Row(children: [
                  Flexible(
                    flex: (studentFrac * 100).round(),
                    child: Container(color: const Color(0xFF2563EB)),
                  ),
                  Flexible(
                    flex: (teacherFrac * 100).round(),
                    child: Container(color: const Color(0xFF7C3AED)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            // Legend
            _LegendRow(
              color: const Color(0xFF2563EB),
              bg: const Color(0xFFEFF6FF),
              label: 'Студенты',
              count: stats.students,
              percent: (studentFrac * 100).round(),
            ),
            const SizedBox(height: 10),
            _LegendRow(
              color: const Color(0xFF7C3AED),
              bg: const Color(0xFFF5F3FF),
              label: 'Преподаватели',
              count: stats.teachers,
              percent: (teacherFrac * 100).round(),
            ),
            const SizedBox(height: 16),
            // Account coverage
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(children: [
                const Icon(Icons.verified_user_rounded,
                    size: 16, color: Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Зарегистрировано: ${stats.users} из ${stats.people} '
                    '(${total > 0 ? (stats.users / total * 100).round() : 0}%)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final Color bg;
  final String label;
  final int count;
  final int percent;

  const _LegendRow({
    required this.color,
    required this.bg,
    required this.label,
    required this.count,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF374151))),
      ),
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$count',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 38,
        child: Text('$percent%',
            textAlign: TextAlign.right,
            style:
                TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ),
    ]);
  }
}

/// Нагрузка предметов: групп и студентов на одного преподавателя
class _TopSubjectsCard extends StatelessWidget {
  final List<Subject> subjects;
  const _TopSubjectsCard({required this.subjects});

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final shown = subjects.take(6).toList();
    final maxRatio = shown.isEmpty
        ? 1.0
        : shown.map((s) => s.groupsPerTeacher).reduce((a, b) => a > b ? a : b).clamp(0.01, double.infinity);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.school_rounded,
                size: 18, color: Color(0xFF1E3A5F)),
            const SizedBox(width: 8),
            const Text('Нагрузка предметов',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827))),
            const Spacer(),
            Text('Топ ${shown.length}',
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 4),
          Text('Групп и студентов на одного преподавателя',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          if (subjects.isEmpty)
            Center(
              child: Text('Нет данных',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade400)),
            )
          else
            ...shown.asMap().entries.map((e) {
              final idx = e.key;
              final s = e.value;
              final frac = maxRatio > 0 ? s.groupsPerTeacher / maxRatio : 0.0;
              final isTop = idx == 0;
              final accentColor =
                  isTop ? const Color(0xFFD97706) : const Color(0xFF1E3A5F);

              return Padding(
                padding: EdgeInsets.only(
                    bottom: idx < shown.length - 1 ? 12 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Rank badge
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isTop
                            ? const Color(0xFFFFFBEB)
                            : Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${idx + 1}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isTop
                                    ? const Color(0xFFD97706)
                                    : Colors.grey.shade500)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Name + bar + sub-stats
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF111827))),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: frac.clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: Colors.grey.shade100,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                accentColor.withValues(alpha: isTop ? 1.0 : 0.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          // Sub-stats row: teachers / groups / students
                          Row(children: [
                            _SubStat(
                              icon: Icons.person_outline_rounded,
                              value: '${s.teacherCount}',
                              label: 'препод.',
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 10),
                            _SubStat(
                              icon: Icons.groups_outlined,
                              value: '${s.groupCount}',
                              label: 'групп',
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 10),
                            _SubStat(
                              icon: Icons.people_outline_rounded,
                              value: '${s.studentCount}',
                              label: 'студ.',
                              color: Colors.grey.shade500,
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Load ratio
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _fmt(s.groupsPerTeacher),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                              height: 1),
                        ),
                        Text(
                          'гр./препод.',
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey.shade400),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fmt(s.studentsPerTeacher),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentColor.withValues(alpha: 0.7),
                              height: 1),
                        ),
                        Text(
                          'студ./препод.',
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SubStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _SubStat(
      {required this.icon,
      required this.value,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 10, color: color),
      const SizedBox(width: 2),
      Text('$value $label',
          style: TextStyle(fontSize: 10, color: color)),
    ]);
  }
}

// ── Common widgets ────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final Color bg;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(20),
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
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
      ]),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 88,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
    );
  }
}

// ── Activity card ─────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final List<ActivityPoint> points;
  const _ActivityCard({required this.points});

  static const _barH = 72.0;

  @override
  Widget build(BuildContext context) {
    final shown =
        points.length > 14 ? points.sublist(points.length - 14) : points;
    final maxVal = shown.isEmpty
        ? 1
        : shown.map((p) => p.logins).reduce((a, b) => a > b ? a : b).clamp(1, 99999);
    final total = shown.fold(0, (s, p) => s + p.logins);

    return _StatsCard(
      icon: Icons.bar_chart_rounded,
      title: 'Активность пользователей',
      subtitle: 'Входы за последние 14 дней',
      trailing: '$total входов',
      child: shown.isEmpty
          ? _emptyHint('Нет данных за период')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Bars ───────────────────────────────────────────────
                SizedBox(
                  height: _barH + 14, // extra room for peak label
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: shown.map((p) {
                      final frac = maxVal > 0 ? p.logins / maxVal : 0.0;
                      final isMax = p.logins == maxVal && p.logins > 0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Tooltip(
                            message: '${_fmtDate(p.date)}: ${p.logins} входов',
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Peak label (only for max bar)
                                SizedBox(
                                  height: 14,
                                  child: isMax
                                      ? Text(
                                          '${p.logins}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF2563EB),
                                          ),
                                        )
                                      : null,
                                ),
                                // Bar
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                  child: Container(
                                    height: (frac * _barH).clamp(2.0, _barH),
                                    color: isMax
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFF93C5FD),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // ── Baseline ───────────────────────────────────────────
                Container(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 5),
                // ── Date axis ──────────────────────────────────────────
                Row(
                  children: shown.asMap().entries.map((e) {
                    final idx = e.key;
                    final n = shown.length;
                    // Show: 1st, last, and every 3rd in between
                    final show =
                        idx == 0 || idx == n - 1 || (idx % 3 == 0);
                    return Expanded(
                      child: Text(
                        show ? _dayNum(e.value.date) : '',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8.5,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
    );
  }

  static String _fmtDate(String date) {
    try {
      final p = date.split('-');
      const m = ['','янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
      return '${int.parse(p[2])} ${m[int.parse(p[1])]}';
    } catch (_) { return date; }
  }

  static String _dayNum(String date) {
    try { return '${int.parse(date.split('-')[2])}'; }
    catch (_) { return ''; }
  }
}

// ── Notifications card ────────────────────────────────────────────────────────

class _NotificationsCard extends StatelessWidget {
  final List<NotificationWeek> weeks;
  const _NotificationsCard({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final maxVal = weeks.isEmpty
        ? 1
        : weeks.map((w) => w.count).reduce((a, b) => a > b ? a : b).clamp(1, 99999);
    final total = weeks.fold(0, (s, w) => s + w.count);
    final devices = weeks.fold(0, (s, w) => s + w.devices);

    return _StatsCard(
      icon: Icons.notifications_active_rounded,
      title: 'Уведомления',
      subtitle: 'За последние 8 недель',
      trailing: '$total отправлено',
      child: weeks.isEmpty
          ? _emptyHint('Уведомления не отправлялись')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 60,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: weeks.map((w) {
                      final frac = maxVal > 0 ? w.count / maxVal : 0.0;
                      final isMax = w.count == maxVal && w.count > 0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Tooltip(
                            message: '${w.label}\n${w.count} уведомл.\n${w.devices} устройств',
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                              child: Container(
                                height: (frac * 52).clamp(2.0, 52.0),
                                color: isMax
                                    ? const Color(0xFF7C3AED)
                                    : const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.devices_rounded,
                      size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Охват: $devices устройств',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ],
            ),
    );
  }
}

// ── Growth card ───────────────────────────────────────────────────────────────

class _GrowthCard extends StatelessWidget {
  final List<GrowthPoint> points;
  const _GrowthCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final totalNew = points.fold(0, (s, p) => s + p.newCount);
    final shown =
        points.length > 30 ? points.sublist(points.length - 30) : points;

    final startPeople =
        shown.isEmpty ? 0 : shown.first.total - shown.first.newCount;
    final endPeople = shown.isEmpty ? 0 : shown.last.total;
    final startReg =
        shown.isEmpty ? 0 : shown.first.totalRegistered - shown.first.newRegistered;
    final endReg = shown.isEmpty ? 0 : shown.last.totalRegistered;

    // Common max across both series for a fair scale
    final maxVal = shown.isEmpty
        ? 1.0
        : shown
            .expand((p) => [p.total.toDouble(), p.totalRegistered.toDouble()])
            .reduce((a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity)
            .toDouble();

    return _StatsCard(
      icon: Icons.group_add_rounded,
      title: 'Участники и аккаунты',
      subtitle: 'Прирост за 30 дней',
      trailing: '+$totalNew участников',
      child: shown.isEmpty
          ? _emptyHint('Нет данных за период')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 68,
                  child: CustomPaint(
                    painter: _DualLineChartPainter(
                      values1: shown.map((p) => p.total.toDouble()).toList(),
                      values2: shown
                          .map((p) => p.totalRegistered.toDouble())
                          .toList(),
                      maxVal: maxVal,
                      color1: const Color(0xFF059669),
                      color2: const Color(0xFF2563EB),
                    ),
                    size: const Size(double.infinity, 68),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _GrowthLegend(
                      color: const Color(0xFF059669),
                      label: 'Участники',
                      from: startPeople,
                      to: endPeople,
                    ),
                    _GrowthLegend(
                      color: const Color(0xFF2563EB),
                      label: 'Аккаунты',
                      from: startReg,
                      to: endReg,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _GrowthLegend extends StatelessWidget {
  final Color color;
  final String label;
  final int from;
  final int to;
  const _GrowthLegend(
      {required this.color,
      required this.label,
      required this.from,
      required this.to});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12,
        height: 2,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      const SizedBox(width: 5),
      Text('$from',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      Text(' → ',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
      Text('$to',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

// ── Dual line chart painter ───────────────────────────────────────────────────

class _DualLineChartPainter extends CustomPainter {
  final List<double> values1;
  final List<double> values2;
  final double maxVal;
  final Color color1;
  final Color color2;

  const _DualLineChartPainter({
    required this.values1,
    required this.values2,
    required this.maxVal,
    required this.color1,
    required this.color2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _draw(canvas, size, values1, color1, fill: true);
    _draw(canvas, size, values2, color2, fill: false);
  }

  void _draw(Canvas canvas, Size size, List<double> vals, Color color,
      {required bool fill}) {
    if (vals.length < 2) return;
    final w = size.width;
    final h = size.height;
    final step = w / (vals.length - 1);

    final line = Path();
    final area = fill ? Path() : null;

    for (var i = 0; i < vals.length; i++) {
      final x = i * step;
      final y = h - (vals[i] / maxVal * h * 0.88) - 1;
      if (i == 0) {
        line.moveTo(x, y);
        area?.moveTo(x, h);
        area?.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        area?.lineTo(x, y);
      }
    }
    area?.lineTo((vals.length - 1) * step, h);
    area?.close();

    if (area != null) {
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.01),
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h))
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DualLineChartPainter old) =>
      old.values1 != values1 ||
      old.values2 != values2 ||
      old.maxVal != maxVal;
}

// ── Shared card container ─────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final Widget child;

  const _StatsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 17, color: const Color(0xFF1E3A5F)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827))),
            ),
            const SizedBox(width: 6),
            Text(trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 3),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

Widget _emptyHint(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      ),
    );

class _StatsCardSkeleton extends StatelessWidget {
  final double height;
  const _StatsCardSkeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
    );
  }
}

class _StatsCardError extends StatelessWidget {
  final String title;
  final IconData icon;
  final String error;
  final VoidCallback onRetry;

  const _StatsCardError({
    required this.title,
    required this.icon,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 17, color: const Color(0xFF1E3A5F)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827))),
          ]),
          const SizedBox(height: 12),
          Text(error,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Повторить', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28)),
          ),
        ],
      ),
    );
  }
}
