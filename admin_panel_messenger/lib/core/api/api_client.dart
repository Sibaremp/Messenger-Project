import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/token_storage.dart';

const String kBaseUrl = 'http://localhost:5216';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(tokenStorage: ref.watch(tokenStorageProvider));
});

class ApiClient {
  late final Dio _dio;
  final TokenStorage tokenStorage;

  ApiClient({required this.tokenStorage}) {
    _dio = Dio(BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await tokenStorage.get();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(String path, {dynamic data}) {
    return _dio.post<T>(path, data: data);
  }

  Future<Response<T>> put<T>(String path, {dynamic data}) {
    return _dio.put<T>(path, data: data);
  }

  Future<Response<T>> delete<T>(String path) {
    return _dio.delete<T>(path);
  }

  Future<Response<T>> postFormData<T>(String path, FormData formData) {
    return _dio.post<T>(path, data: formData);
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

ApiException mapDioException(DioException e) {
  final status = e.response?.statusCode;
  if (status == 401) {
    return const ApiException('Сессия истекла. Войдите снова.', statusCode: 401);
  }
  if (status == 400) {
    final msg = e.response?.data?['message'] as String?;
    return ApiException(msg ?? 'Некорректный запрос', statusCode: 400);
  }
  if (status == 404) {
    return const ApiException('Ресурс не найден', statusCode: 404);
  }
  if (status == 409) {
    final msg = e.response?.data?['message'] as String?;
    return ApiException(msg ?? 'Такая запись уже существует', statusCode: 409);
  }
  if (status != null && status >= 500) {
    return ApiException('Ошибка сервера ($status)', statusCode: status);
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return const ApiException('Превышено время ожидания. Проверьте соединение.');
  }
  if (e.type == DioExceptionType.connectionError) {
    return const ApiException('Нет соединения с сервером. Проверьте адрес и сеть.');
  }
  final bodyMsg = e.response?.data is Map
      ? (e.response!.data as Map)['message'] as String?
      : null;
  return ApiException(bodyMsg ?? e.message ?? 'Неизвестная ошибка');
}
