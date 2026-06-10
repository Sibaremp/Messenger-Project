import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/token_storage.dart';

const String kBaseUrl = 'https://api.caspianmessenger.kz';

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

    // На десктопе (Windows/Linux/macOS) dart:io проверяет SSL-цепочку системным
    // стором. Тоннельные сертификаты (Let's Encrypt через ngrok / Cloudflare)
    // иногда не проходят проверку — разрешаем все доверенные и самоподписанные.
    if (!const bool.fromEnvironment('dart.library.html')) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }

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

  Future<Response<T>> patch<T>(String path, {dynamic data}) {
    return _dio.patch<T>(path, data: data);
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

  // Извлекаем message из тела ответа (если есть)
  String? bodyMsg;
  final data = e.response?.data;
  if (data is Map) {
    bodyMsg = data['message'] as String?;
  } else if (data is String && data.isNotEmpty) {
    bodyMsg = data;
  }

  if (status == 400) {
    return ApiException(bodyMsg ?? 'Некорректный запрос', statusCode: 400);
  }
  if (status == 401) {
    // Для страницы логина сервер возвращает своё сообщение — показываем его
    return ApiException(
      bodyMsg ?? 'Неверный логин или пароль',
      statusCode: 401,
    );
  }
  if (status == 403) {
    return ApiException(bodyMsg ?? 'Доступ запрещён', statusCode: 403);
  }
  if (status == 404) {
    return ApiException(bodyMsg ?? 'Ресурс не найден', statusCode: 404);
  }
  if (status == 409) {
    return ApiException(bodyMsg ?? 'Такая запись уже существует', statusCode: 409);
  }
  if (status != null && status >= 500) {
    return ApiException(bodyMsg ?? 'Ошибка сервера ($status)', statusCode: status);
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return const ApiException('Превышено время ожидания. Проверьте соединение.');
  }
  if (e.type == DioExceptionType.connectionError) {
    return const ApiException('Нет соединения с сервером. Проверьте адрес и сеть.');
  }
  // Браузерные CORS/сетевые ошибки попадают сюда с type == unknown
  if (e.type == DioExceptionType.unknown) {
    final msg = e.message ?? '';
    final inner = e.error?.toString() ?? '';
    final detail = [if (msg.isNotEmpty) msg, if (inner.isNotEmpty && inner != msg) inner]
        .join(' | ');
    if (msg.toLowerCase().contains('xmlhttprequest') ||
        msg.toLowerCase().contains('cors') ||
        inner.toLowerCase().contains('cors')) {
      return const ApiException('Ошибка сети. Возможно, CORS не настроен на сервере.');
    }
    return ApiException(
      bodyMsg ?? (detail.isNotEmpty ? detail : 'Нет ответа от сервера.'),
    );
  }
  return ApiException(bodyMsg ?? e.message ?? 'Неизвестная ошибка');
}
