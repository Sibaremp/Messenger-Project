import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/dashboard/presentation/screens/dashboard_screen.dart';
import 'features/import/presentation/screens/import_screen.dart';
import 'features/people/presentation/screens/people_screen.dart';
import 'features/users/presentation/screens/users_screen.dart';
import 'features/groups/presentation/screens/groups_screen.dart';
import 'features/subjects/presentation/screens/subjects_screen.dart';
import 'features/notifications/presentation/screens/notifications_screen.dart';
import 'shared/widgets/main_layout.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _AuthStatusNotifier(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;

      if (auth.status == AuthStatus.unknown) {
        return loc == '/' ? null : '/';
      }
      if (auth.status == AuthStatus.unauthenticated) {
        return loc == '/login' ? null : '/login';
      }
      if (auth.status == AuthStatus.authenticated) {
        if (loc == '/' || loc == '/login') return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainLayout(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => NoTransitionPage(
              child: const DashboardScreen(),
              key: state.pageKey,
            ),
          ),
          GoRoute(
            path: '/people',
            pageBuilder: (context, state) => NoTransitionPage(
              child: const PeopleScreen(),
              key: state.pageKey,
            ),
          ),
          GoRoute(
            path: '/users',
            pageBuilder: (context, state) => NoTransitionPage(
              child: const UsersScreen(),
              key: state.pageKey,
            ),
          ),
          GoRoute(
            path: '/groups',
            pageBuilder: (context, state) => NoTransitionPage(
              child: const GroupsScreen(),
              key: state.pageKey,
            ),
          ),
          GoRoute(
            path: '/subjects',
            pageBuilder: (context, state) => NoTransitionPage(
              child: const SubjectsScreen(),
              key: state.pageKey,
            ),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (context, state) => NoTransitionPage(
              child: const NotificationsScreen(),
              key: state.pageKey,
            ),
          ),
          GoRoute(
            path: '/import',
            pageBuilder: (context, state) => NoTransitionPage(
              child: const ImportScreen(),
              key: state.pageKey,
            ),
          ),
        ],
      ),
    ],
  );
});

class _AuthStatusNotifier extends ChangeNotifier {
  final Ref _ref;
  AuthStatus? _last;

  _AuthStatusNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.status != _last) {
        _last = next.status;
        notifyListeners();
      }
    });
  }
}
