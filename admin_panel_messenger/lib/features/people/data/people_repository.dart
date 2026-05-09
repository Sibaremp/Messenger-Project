import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/person.dart';

final peopleRepositoryProvider = Provider<PeopleRepository>((ref) {
  return PeopleRepository(apiClient: ref.watch(apiClientProvider));
});

class PeopleRepository {
  final ApiClient _apiClient;

  PeopleRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<Person>> fetchPeople({String? search, String? role}) async {
    try {
      final params = <String, dynamic>{};
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (role != null && role != 'all') params['role'] = role;

      final response = await _apiClient.get<List<dynamic>>(
        '/api/admin/people',
        queryParameters: params.isNotEmpty ? params : null,
      );
      return (response.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(Person.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<Person> updatePerson(int id, {
    String? firstName,
    String? lastName,
    String? middleName,
    String? role,
    String? group,
  }) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/admin/people/$id',
        data: {
          'firstName':  firstName,
          'lastName':   lastName,
          'middleName': middleName,
          'role':       role,
          'group':      group,
        },
      );
      return Person.fromJson(response.data!);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> deletePerson(int id) async {
    try {
      await _apiClient.delete('/api/admin/people/$id');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
