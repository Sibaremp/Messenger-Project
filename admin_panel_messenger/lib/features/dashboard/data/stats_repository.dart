import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  return StatsRepository(apiClient: ref.watch(apiClientProvider));
});

// ── Data models ───────────────────────────────────────────────────────────────

class ActivityPoint {
  final String date;
  final int logins;
  ActivityPoint({required this.date, required this.logins});
  factory ActivityPoint.fromJson(Map<String, dynamic> j) =>
      ActivityPoint(date: j['date'] as String, logins: j['logins'] as int);
}

class NotificationWeek {
  final String weekStart;
  final String label;
  final int count;
  final int devices;
  NotificationWeek({
    required this.weekStart,
    required this.label,
    required this.count,
    required this.devices,
  });
  factory NotificationWeek.fromJson(Map<String, dynamic> j) =>
      NotificationWeek(
        weekStart: j['weekStart'] as String,
        label: j['label'] as String,
        count: j['count'] as int,
        devices: j['devices'] as int,
      );
}

class GrowthPoint {
  final String date;
  final int newCount;
  final int total;
  GrowthPoint({required this.date, required this.newCount, required this.total});
  factory GrowthPoint.fromJson(Map<String, dynamic> j) => GrowthPoint(
        date: j['date'] as String,
        newCount: j['newCount'] as int,
        total: j['total'] as int,
      );
}

// ── Repository ────────────────────────────────────────────────────────────────

class StatsRepository {
  final ApiClient _api;
  StatsRepository({required ApiClient apiClient}) : _api = apiClient;

  Future<List<ActivityPoint>> fetchActivity({int days = 14}) async {
    final r = await _api.get<List<dynamic>>(
      '/api/admin/stats/activity',
      queryParameters: {'days': days},
    );
    return (r.data ?? [])
        .map((e) => ActivityPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<NotificationWeek>> fetchNotificationStats({int weeks = 8}) async {
    final r = await _api.get<List<dynamic>>(
      '/api/admin/stats/notifications',
      queryParameters: {'weeks': weeks},
    );
    return (r.data ?? [])
        .map((e) => NotificationWeek.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GrowthPoint>> fetchGrowth({int days = 30}) async {
    final r = await _api.get<List<dynamic>>(
      '/api/admin/stats/growth',
      queryParameters: {'days': days},
    );
    return (r.data ?? [])
        .map((e) => GrowthPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
