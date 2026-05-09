import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

final importRepositoryProvider = Provider<ImportRepository>((ref) {
  return ImportRepository(apiClient: ref.watch(apiClientProvider));
});

class ImportResult {
  final int added;
  final int skipped;

  const ImportResult({required this.added, required this.skipped});

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      added: json['added'] as int? ?? 0,
      skipped: json['skipped'] as int? ?? 0,
    );
  }
}

class ImportRepository {
  final ApiClient _apiClient;

  ImportRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<ImportResult> importPeople(
      String fileName, Uint8List bytes) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });
      final response = await _apiClient
          .postFormData<Map<String, dynamic>>('/api/admin/import-people', formData);
      return ImportResult.fromJson(
          response.data ?? {'added': 0, 'skipped': 0});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
