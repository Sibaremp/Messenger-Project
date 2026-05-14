import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/notifications_repository.dart';
import '../../../../shared/models/admin_notification.dart';

// ── History ────────────────────────────────────────────────────────────────────

class NotificationsHistoryNotifier
    extends StateNotifier<AsyncValue<List<AdminNotification>>> {
  final NotificationsRepository _repo;

  NotificationsHistoryNotifier(this._repo)
      : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.fetchHistory());
  }

  Future<bool> delete(int id) async {
    try {
      await _repo.deleteNotification(id);
      state =
          state.whenData((list) => list.where((n) => n.id != id).toList());
      return true;
    } catch (_) {
      return false;
    }
  }
}

final notificationsHistoryProvider = StateNotifierProvider.autoDispose<
    NotificationsHistoryNotifier,
    AsyncValue<List<AdminNotification>>>(
  (ref) => NotificationsHistoryNotifier(
      ref.watch(notificationsRepositoryProvider)),
);

// ── Send form ──────────────────────────────────────────────────────────────────

enum SendStatus { idle, loading, success, error }

class SendState {
  final SendStatus status;
  final String? error;

  const SendState({this.status = SendStatus.idle, this.error});

  SendState copyWith({SendStatus? status, String? error, bool clearError = false}) =>
      SendState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
      );
}

class SendNotifier extends StateNotifier<SendState> {
  final NotificationsRepository _repo;
  final NotificationsHistoryNotifier _history;

  SendNotifier(this._repo, this._history) : super(const SendState());

  Future<void> send({
    required String title,
    required String body,
    required String target,
    String? imageUrl,
  }) async {
    state = state.copyWith(status: SendStatus.loading, clearError: true);
    try {
      await _repo.send(
          title: title, body: body, target: target, imageUrl: imageUrl);
      state = state.copyWith(status: SendStatus.success);
      _history.load();
    } catch (e) {
      state = state.copyWith(
          status: SendStatus.error, error: e.toString());
    }
  }

  void reset() => state = const SendState();
}

final sendNotificationProvider =
    StateNotifierProvider.autoDispose<SendNotifier, SendState>((ref) {
  return SendNotifier(
    ref.watch(notificationsRepositoryProvider),
    ref.watch(notificationsHistoryProvider.notifier),
  );
});
