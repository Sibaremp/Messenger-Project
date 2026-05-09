import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/token_storage.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  );
});

class AuthRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthRepository({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  Future<void> login(String login, String password) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/admin/login',
        data: {'login': login, 'password': password},
      );
      final token = response.data!['token'] as String;
      await _tokenStorage.save(token);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> logout() async {
    await _tokenStorage.clear();
  }

  Future<bool> hasToken() async {
    final token = await _tokenStorage.get();
    return token != null && token.isNotEmpty;
  }
}
