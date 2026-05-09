import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

class MainLayout extends StatelessWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const _Sidebar(),
          Container(width: 1, color: const Color(0xFFE5E7EB)),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFF9FAFB),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;

    return Container(
      width: 248,
      color: const Color(0xFF0F2440),
      child: Column(
        children: [
          const _SidebarHeader(),
          const SizedBox(height: 8),
          _NavItem(
            icon: Icons.people_alt_outlined,
            label: 'Участники',
            path: '/people',
            active: location.startsWith('/people'),
          ),
          _NavItem(
            icon: Icons.manage_accounts_outlined,
            label: 'Пользователи',
            path: '/users',
            active: location.startsWith('/users'),
          ),
          _NavItem(
            icon: Icons.group_outlined,
            label: 'Группы',
            path: '/groups',
            active: location.startsWith('/groups'),
          ),
          _NavItem(
            icon: Icons.menu_book_outlined,
            label: 'Предметы',
            path: '/subjects',
            active: location.startsWith('/subjects'),
          ),
          _NavItem(
            icon: Icons.notifications_outlined,
            label: 'Уведомления',
            path: '/notifications',
            active: location.startsWith('/notifications'),
          ),
          _NavItem(
            icon: Icons.upload_file_outlined,
            label: 'Импорт',
            path: '/import',
            active: location.startsWith('/import'),
          ),
          const Spacer(),
          const Divider(color: Color(0xFF1E3A5F), height: 1),
          const _LogoutTile(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Caspian Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Панель управления',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final bool active;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => context.go(path),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF1E3A5F)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: active ? Colors.white : const Color(0xFF64748B),
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: active ? Colors.white : const Color(0xFF94A3B8),
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoutTile extends ConsumerWidget {
  const _LogoutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => ref.read(authProvider.notifier).logout(),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: const Row(
              children: [
                Icon(Icons.logout_rounded,
                    size: 19, color: Color(0xFF64748B)),
                SizedBox(width: 11),
                Text(
                  'Выйти',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
