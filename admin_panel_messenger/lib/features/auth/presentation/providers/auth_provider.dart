import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final has = await _repo.hasToken();
    state = state.copyWith(
      status: has ? AuthStatus.authenticated : AuthStatus.unauthenticated,
    );
  }

  Future<void> login(String login, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.login(login, password);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      clearError: true,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
