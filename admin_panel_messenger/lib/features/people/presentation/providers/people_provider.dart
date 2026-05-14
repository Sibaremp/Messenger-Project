import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/people_repository.dart';
import '../../../../shared/models/person.dart';

class PeopleFilter {
  final String search;
  final String role;
  final String? group;
  final bool? hasUser;

  const PeopleFilter({
    this.search = '',
    this.role = 'all',
    this.group,
    this.hasUser,
  });

  static const Object _undefined = Object();

  PeopleFilter copyWith({
    String? search,
    String? role,
    Object? group = _undefined,
    Object? hasUser = _undefined,
  }) =>
      PeopleFilter(
        search: search ?? this.search,
        role: role ?? this.role,
        group: identical(group, _undefined) ? this.group : group as String?,
        hasUser:
            identical(hasUser, _undefined) ? this.hasUser : hasUser as bool?,
      );

  @override
  bool operator ==(Object other) =>
      other is PeopleFilter &&
      search == other.search &&
      role == other.role &&
      group == other.group &&
      hasUser == other.hasUser;

  @override
  int get hashCode => Object.hash(search, role, group, hasUser);
}

final peopleFilterProvider =
    StateProvider<PeopleFilter>((ref) => const PeopleFilter());

// ── Notifier ────────────────────────────────────────────────────────────────

class PeopleNotifier extends StateNotifier<AsyncValue<List<Person>>> {
  final PeopleRepository _repo;
  PeopleFilter _filter;

  PeopleNotifier(this._repo, this._filter)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchPeople(
          search: _filter.search,
          role: _filter.role,
          group: _filter.group,
          hasUser: _filter.hasUser,
        ));
  }

  void applyFilter(PeopleFilter filter) {
    _filter = filter;
    _load();
  }

  Future<bool> updatePerson(
    int id, {
    String? firstName,
    String? lastName,
    String? middleName,
    String? role,
    String? group,
  }) async {
    try {
      final updated = await _repo.updatePerson(id,
          firstName: firstName,
          lastName: lastName,
          middleName: middleName,
          role: role,
          group: group);
      state = state.whenData(
          (list) => list.map((p) => p.id == id ? updated : p).toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deletePerson(int id) async {
    try {
      await _repo.deletePerson(id);
      state =
          state.whenData((list) => list.where((p) => p.id != id).toList());
      return true;
    } catch (_) {
      return false;
    }
  }
}

final peopleProvider = StateNotifierProvider.autoDispose<PeopleNotifier,
    AsyncValue<List<Person>>>((ref) {
  final repo = ref.watch(peopleRepositoryProvider);
  final filter = ref.read(peopleFilterProvider);
  final notifier = PeopleNotifier(repo, filter);

  ref.listen<PeopleFilter>(peopleFilterProvider, (_, next) {
    notifier.applyFilter(next);
  });

  return notifier;
});
