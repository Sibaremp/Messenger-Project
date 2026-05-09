import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/group_item.dart';

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(apiClient: ref.watch(apiClientProvider));
});

class GroupsRepository {
  final ApiClient _apiClient;

  GroupsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<GroupItem>> fetchGroups() async {
    try {
      final r = await _apiClient.get<List<dynamic>>('/api/admin/groups');
      return (r.data ?? [])
          .cast<Map<String, dynamic>>()
          .map(GroupItem.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> deleteGroup(String name) async {
    try {
      final encoded = Uri.encodeComponent(name);
      await _apiClient.delete('/api/admin/groups/$encoded');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
