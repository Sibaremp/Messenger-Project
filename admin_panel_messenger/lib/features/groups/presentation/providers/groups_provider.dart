import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/groups_repository.dart';
import '../../../../shared/models/group_item.dart';

class GroupsNotifier extends StateNotifier<AsyncValue<List<GroupItem>>> {
  final GroupsRepository _repo;

  GroupsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchGroups());
  }

  Future<bool> delete(String name) async {
    try {
      await _repo.deleteGroup(name);
      state = state.whenData(
          (list) => list.where((g) => g.name != name).toList());
      return true;
    } catch (_) {
      return false;
    }
  }
}

final groupsProvider =
    StateNotifierProvider.autoDispose<GroupsNotifier, AsyncValue<List<GroupItem>>>(
        (ref) => GroupsNotifier(ref.watch(groupsRepositoryProvider)));
