import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/subject.dart';

final subjectsRepositoryProvider = Provider<SubjectsRepository>((ref) {
  return SubjectsRepository(apiClient: ref.watch(apiClientProvider));
});

class SubjectsRepository {
  final ApiClient _apiClient;

  SubjectsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<Subject>> fetchSubjects() async {
    try {
      final r = await _apiClient.get<List<dynamic>>('/api/admin/subjects');
      return (r.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(Subject.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<Subject> createSubject(String name) async {
    try {
      final r = await _apiClient.post<Map<String, dynamic>>(
        '/api/admin/subjects',
        data: {'name': name},
      );
      return Subject.fromJson(r.data!);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<Subject> renameSubject(int id, String name) async {
    try {
      final r = await _apiClient.put<Map<String, dynamic>>(
        '/api/admin/subjects/$id',
        data: {'name': name},
      );
      return Subject.fromJson(r.data!);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> deleteSubject(int id) async {
    try {
      await _apiClient.delete('/api/admin/subjects/$id');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<TeacherAssignment>> fetchTeacherAssignments(int personId) async {
    try {
      final r = await _apiClient
          .get<List<dynamic>>('/api/admin/people/$personId/subjects');
      return (r.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(TeacherAssignment.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> addAssignment(
    int personId,
    int subjectId,
    String groupName,
  ) async {
    try {
      await _apiClient.post<dynamic>(
        '/api/admin/people/$personId/subjects',
        data: {'subjectId': subjectId, 'groupName': groupName},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<SubjectAssignment>> fetchSubjectAssignments(int subjectId) async {
    try {
      final r = await _apiClient.get<List<dynamic>>(
          '/api/admin/subjects/$subjectId/assignments');
      return (r.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(SubjectAssignment.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> removeAssignment(int personId, int assignmentId) async {
    try {
      await _apiClient
          .delete('/api/admin/people/$personId/subjects/$assignmentId');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> updateAssignment(
    int personId,
    int assignmentId, {
    int? newPersonId,
    String? newGroupName,
  }) async {
    try {
      await _apiClient.patch<dynamic>(
        '/api/admin/people/$personId/subjects/$assignmentId',
        data: {
          if (newPersonId != null) 'newPersonId': newPersonId,
          if (newGroupName != null) 'newGroupName': newGroupName,
        },
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
