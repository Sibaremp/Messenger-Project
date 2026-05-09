import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/user.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(apiClient: ref.watch(apiClientProvider));
});

class UsersRepository {
  final ApiClient _apiClient;

  UsersRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<User>> fetchUsers() async {
    try {
      final response = await _apiClient.get<List<dynamic>>('/api/admin/users');
      final list = response.data ?? [];
      return list.cast<Map<String, dynamic>>().map(User.fromJson).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<User> updateUser(int id, {
    String? login,
    String? role,
    String? group,
    String? phone,
  }) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/admin/users/$id',
        data: {
          'login': login,
          'role':  role,
          'group': group,
          'phone': phone,
        },
      );
      return User.fromJson(response.data!);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> changePassword(int id, String newPassword) async {
    try {
      await _apiClient.put<void>(
        '/api/admin/users/$id/password',
        data: {'newPassword': newPassword},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> deleteUser(int id) async {
    try {
      await _apiClient.delete('/api/admin/users/$id');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
