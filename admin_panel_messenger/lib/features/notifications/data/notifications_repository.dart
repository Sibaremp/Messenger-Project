import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/admin_notification.dart';

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(apiClient: ref.watch(apiClientProvider));
});

class NotificationsRepository {
  final ApiClient _apiClient;

  NotificationsRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<void> send({
    required String title,
    required String body,
    required String target,
    String? imageUrl,
  }) async {
    try {
      await _apiClient.post<void>(
        '/api/admin/notifications',
        data: {
          'title': title,
          'body': body,
          'target': target,
          if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        },
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<String> uploadAttachment(String fileName, List<int> bytes) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });
      final r = await _apiClient.postFormData<Map<String, dynamic>>(
          '/api/admin/notifications/upload', formData);
      final url = r.data?['url'] as String?;
      if (url == null) throw const ApiException('Не удалось получить URL файла');
      return url;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<AdminNotification>> fetchHistory({
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final r = await _apiClient.get<List<dynamic>>(
        '/api/admin/notifications',
        queryParameters: {'page': page, 'pageSize': pageSize},
      );
      return (r.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(AdminNotification.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> deleteNotification(int id) async {
    try {
      await _apiClient.delete('/api/admin/notifications/$id');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
