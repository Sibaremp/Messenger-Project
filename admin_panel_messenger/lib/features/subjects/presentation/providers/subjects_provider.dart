import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/subjects_repository.dart';
import '../../../../shared/models/subject.dart';

class SubjectsNotifier extends StateNotifier<AsyncValue<List<Subject>>> {
  final SubjectsRepository _repo;

  SubjectsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchSubjects());
  }

  Future<bool> create(String name) async {
    try {
      final created = await _repo.createSubject(name);
      state = state.whenData((list) => [...list, created]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rename(int id, String name) async {
    try {
      final updated = await _repo.renameSubject(id, name);
      state = state.whenData(
          (list) => list.map((s) => s.id == id ? updated : s).toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(int id) async {
    try {
      await _repo.deleteSubject(id);
      state = state.whenData((list) => list.where((s) => s.id != id).toList());
      return true;
    } catch (_) {
      return false;
    }
  }
}

final subjectsProvider =
    StateNotifierProvider.autoDispose<SubjectsNotifier, AsyncValue<List<Subject>>>(
        (ref) => SubjectsNotifier(ref.watch(subjectsRepositoryProvider)));
