import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/users_repository.dart';
import '../../../../shared/models/user.dart';

class UsersNotifier extends StateNotifier<AsyncValue<List<User>>> {
  final UsersRepository _repo;

  UsersNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchUsers());
  }

  Future<bool> updateUser(int id, {
    String? login,
    String? role,
    String? group,
    String? phone,
  }) async {
    try {
      final updated = await _repo.updateUser(id,
          login: login, role: role, group: group, phone: phone);
      state = state.whenData((list) =>
          list.map((u) => u.id == id ? updated : u).toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> changePassword(int id, String newPassword) async {
    try {
      await _repo.changePassword(id, newPassword);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteUser(int id) async {
    try {
      await _repo.deleteUser(id);
      state = state.whenData(
          (list) => list.where((u) => u.id != id).toList());
      return true;
    } catch (_) {
      return false;
    }
  }
}

final usersProvider =
    StateNotifierProvider.autoDispose<UsersNotifier, AsyncValue<List<User>>>(
        (ref) => UsersNotifier(ref.watch(usersRepositoryProvider)));
