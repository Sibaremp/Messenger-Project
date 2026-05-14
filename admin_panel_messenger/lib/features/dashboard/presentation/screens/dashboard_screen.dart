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
    ..sort((a, b) => b.assignmentCount.compareTo(a.assignmentCount));

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _CompositionCard(stats: stats),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _TopSubjectsCard(subjects: stats.topSubjects),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Real statistics row (from API)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ref.watch(_activityProvider).when(
                  data: (pts) => _ActivityCard(points: pts),
                  loading: () => const _StatsCardSkeleton(height: 200),
                  error: (e, _) => _StatsCardError(
                    title: 'Активность пользователей',
                    icon: Icons.bar_chart_rounded,
                    error: e.toString(),
                    onRetry: () => ref.invalidate(_activityProvider),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ref.watch(_notifStatsProvider).when(
                  data: (weeks) => _NotificationsCard(weeks: weeks),
                  loading: () => const _StatsCardSkeleton(height: 200),
                  error: (e, _) => _StatsCardError(
                    title: 'Уведомления',
                    icon: Icons.notifications_active_rounded,
                    error: e.toString(),
                    onRetry: () => ref.invalidate(_notifStatsProvider),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ref.watch(_growthProvider).when(
                  data: (pts) => _GrowthCard(points: pts),
                  loading: () => const _StatsCardSkeleton(height: 200),
                  error: (e, _) => _StatsCardError(
                    title: 'Новые участники',
                    icon: Icons.group_add_rounded,
                    error: e.toString(),
                    onRetry: () => ref.invalidate(_growthProvider),
                  ),
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
                Text(
                  'Зарегистрировано: ${stats.users} из ${stats.people} '
                  '(${total > 0 ? (stats.users / total * 100).round() : 0}%)',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF059669),
                      fontWeight: FontWeight.w500),
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

/// Топ предметов по количеству назначений
class _TopSubjectsCard extends StatelessWidget {
  final List<Subject> subjects;
  const _TopSubjectsCard({required this.subjects});

  @override
  Widget build(BuildContext context) {
    final maxCount = subjects.isEmpty
        ? 1
        : subjects.first.assignmentCount.clamp(1, 999);
    final shown = subjects.take(6).toList();

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
            const Text('Назначения предметов',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827))),
            const Spacer(),
            Text('Топ ${shown.length}',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 4),
          Text('Предметы по количеству назначенных преподавателей',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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
              final frac =
                  s.assignmentCount / maxCount;
              return Padding(
                padding: EdgeInsets.only(
                    bottom: idx < shown.length - 1 ? 10 : 0),
                child: Row(children: [
                  // Rank badge
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: idx == 0
                          ? const Color(0xFFFFFBEB)
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${idx + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: idx == 0
                                  ? const Color(0xFFD97706)
                                  : Colors.grey.shade500)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name + bar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF111827))),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: frac,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade100,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(
                              idx == 0
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF1E3A5F)
                                      .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Count
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${s.assignmentCount}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: idx == 0
                              ? const Color(0xFFD97706)
                              : Colors.grey.shade600),
                    ),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final maxVal = points.isEmpty
        ? 1
        : points.map((p) => p.logins).reduce((a, b) => a > b ? a : b).clamp(1, 99999);
    final total = points.fold(0, (s, p) => s + p.logins);
    // Show only last 14 labels but abbreviated
    final shown = points.length > 14 ? points.sublist(points.length - 14) : points;

    return _StatsCard(
      icon: Icons.bar_chart_rounded,
      title: 'Активность пользователей',
      subtitle: 'Входы за последние 14 дней',
      trailing: '$total входов',
      child: shown.isEmpty
          ? _emptyHint('Нет данных за период')
          : SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: shown.map((p) {
                  final frac = maxVal > 0 ? p.logins / maxVal : 0.0;
                  final isMax = p.logins == maxVal && p.logins > 0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Tooltip(
                        message: '${p.date}\n${p.logins} входов',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (p.logins > 0)
                              Text('${p.logins}',
                                  style: TextStyle(
                                      fontSize: 8,
                                      color: isMax
                                          ? const Color(0xFF2563EB)
                                          : Colors.grey.shade400)),
                            const SizedBox(height: 2),
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3)),
                              child: Container(
                                height: (frac * 60).clamp(2.0, 60.0),
                                color: isMax
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF2563EB)
                                        .withValues(alpha: 0.3),
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
    );
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
    final currentTotal = points.isEmpty ? 0 : points.last.total;
    final startTotal = points.isEmpty ? 0 : points.first.total - points.first.newCount;
    final maxVal = points.isEmpty
        ? 1
        : points.map((p) => p.total).reduce((a, b) => a > b ? a : b).clamp(1, 99999);
    // Show weekly buckets (every 7th point label)
    final shown = points.length > 30 ? points.sublist(points.length - 30) : points;

    return _StatsCard(
      icon: Icons.group_add_rounded,
      title: 'Новые участники',
      subtitle: 'Прирост за 30 дней',
      trailing: '+$totalNew за период',
      child: shown.isEmpty
          ? _emptyHint('Нет данных за период')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Area-like chart via gradient bars
                SizedBox(
                  height: 60,
                  child: CustomPaint(
                    painter: _LineChartPainter(
                      values: shown.map((p) => p.total.toDouble()).toList(),
                      maxVal: maxVal.toDouble(),
                      color: const Color(0xFF059669),
                    ),
                    size: const Size(double.infinity, 60),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _GrowthStat(
                      label: 'Было',
                      value: '$startTotal',
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 12),
                    _GrowthStat(
                      label: 'Стало',
                      value: '$currentTotal',
                      color: const Color(0xFF059669),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _GrowthStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _GrowthStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      Text(value,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

// ── Line chart painter ────────────────────────────────────────────────────────

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxVal;
  final Color color;

  const _LineChartPainter({
    required this.values,
    required this.maxVal,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final w = size.width;
    final h = size.height;
    final step = w / (values.length - 1);

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < values.length; i++) {
      final x = i * step;
      final y = h - (values[i] / maxVal * h * 0.85) - 2;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, h);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo((values.length - 1) * step, h);
    fillPath.close();

    // Fill
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.2),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill,
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values || old.maxVal != maxVal;
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
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827))),
            ),
            Text(trailing,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 3),
          Text(subtitle,
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
