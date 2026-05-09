import 'package:flutter/material.dart';
import '../app_constants.dart';
import '../theme.dart' show ThemeProvider, AppThemeMode;

/// Элемент навигации в боковой панели.
enum SidebarNav { academic, chat, notifications, profile }

/// Боковая панель навигации (desktop-режим).
class Sidebar extends StatelessWidget {
  final SidebarNav selected;
  final ValueChanged<SidebarNav> onSelect;
  final VoidCallback onNewChat;
  final VoidCallback onLogout;
  /// Текст кнопки внизу — меняется в зависимости от вкладки
  final String actionLabel;
  final IconData actionIcon;
  /// Скрыть кнопку действия (например, в Академический/Группы)
  final bool showActionButton;

  const Sidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNewChat,
    required this.onLogout,
    this.actionLabel = 'Новый чат',
    this.actionIcon = Icons.add,
    this.showActionButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final provider = ThemeProvider.of(context);

    // Иконка темы зависит от текущего режима
    IconData themeIcon;
    switch (provider.mode) {
      case AppThemeMode.light:
        themeIcon = Icons.light_mode_outlined;
      case AppThemeMode.dark:
        themeIcon = Icons.dark_mode_outlined;
      case AppThemeMode.system:
        themeIcon = Icons.brightness_auto_outlined;
    }

    return Container(
      width: AppSizes.sidebarWidth,
      color: bgColor,
      child: Column(
        children: [
          // ── Логотип (на уровне верхней строки поиска) ────────────
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Место для логотипа: положите файл assets/images/logo.png
                // и он появится здесь автоматически.
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: AppColors.primary.withAlpha(80),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.image_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Caspian Messenger',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Навигация ────────────────────────────────────────────
          _NavItem(
            icon: Icons.school_outlined,
            label: 'Академический',
            selected: selected == SidebarNav.academic,
            onTap: () => onSelect(SidebarNav.academic),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Общение',
            selected: selected == SidebarNav.chat,
            onTap: () => onSelect(SidebarNav.chat),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.notifications_none,
            label: 'Уведомления',
            selected: selected == SidebarNav.notifications,
            onTap: () => onSelect(SidebarNav.notifications),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.person_outline,
            label: 'Профиль',
            selected: selected == SidebarNav.profile,
            onTap: () => onSelect(SidebarNav.profile),
          ),

          const Spacer(),

          // ── Кнопка действия (скрывается если showActionButton == false)
          if (showActionButton)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: onNewChat,
                  icon: Icon(actionIcon, size: 20),
                  label: Text(actionLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // ── Тема (кликабельная — переключает тему по циклу) ──────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  switch (provider.mode) {
                    case AppThemeMode.light:
                      provider.setMode(AppThemeMode.dark);
                    case AppThemeMode.dark:
                      provider.setMode(AppThemeMode.system);
                    case AppThemeMode.system:
                      provider.setMode(AppThemeMode.light);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(themeIcon, size: 20, color: AppColors.subtle),
                      const SizedBox(width: 12),
                      const Text('Тема',
                          style: TextStyle(color: AppColors.subtle, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // ── Выйти ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onLogout,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: const Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: AppColors.subtle),
                      SizedBox(width: 12),
                      Text('Выйти',
                          style: TextStyle(color: AppColors.subtle, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Элемент навигации ──────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: selected
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.primary.withValues(alpha: 0.08))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 20,
                    color: selected ? AppColors.primary : AppColors.subtle),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? AppColors.primary : null,
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
