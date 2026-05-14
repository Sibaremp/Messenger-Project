import 'package:flutter/material.dart';
import '../app_constants.dart';
import '../profile_screen.dart' show ProfileAvatar;

/// Элемент навигации в боковой панели.
enum SidebarNav { academic, chat, notifications, profile }

/// Боковая панель навигации (desktop-режим).
class Sidebar extends StatelessWidget {
  final SidebarNav selected;
  final ValueChanged<SidebarNav> onSelect;
  final VoidCallback onNewChat;
  final VoidCallback onLogout;

  /// Вызывается при нажатии на карточку профиля или пункт «Настройки».
  /// Если не задан — используется стандартный [onSelect(SidebarNav.profile)].
  final VoidCallback? onSettingsTap;

  /// Текст кнопки действия внизу.
  final String actionLabel;
  final IconData actionIcon;

  /// Скрыть кнопку действия (например, в академическом разделе для студента).
  final bool showActionButton;

  /// Отображаемое имя пользователя (ФИО или логин) — первая строка карточки.
  final String? displayName;

  /// Логин пользователя — вторая строка карточки.
  final String? userName;

  /// Путь к аватару текущего пользователя.
  final String? userAvatarPath;

  /// Суммарный счётчик непрочитанных для значка на «Общение».
  final int chatUnreadCount;

  const Sidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNewChat,
    required this.onLogout,
    this.actionLabel = 'Новый чат',
    this.actionIcon = Icons.add,
    this.showActionButton = true,
    this.displayName,
    this.userName,
    this.userAvatarPath,
    this.chatUnreadCount = 0,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final primary = Theme.of(context).colorScheme.primary;

    // Сайдбар фиксированной ширины — текст не масштабируется,
    // чтобы не выходить за пределы при textScale > 1.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
      width: AppSizes.sidebarWidth,
      color: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Логотип ──────────────────────────────────────────────
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: primary.withAlpha(30),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: primary.withAlpha(80),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.image_outlined,
                        size: 16,
                        color: primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Caspian Messenger',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Карточка пользователя (вверху, под логотипом) ────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onSettingsTap ?? () => onSelect(SidebarNav.profile),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Row(
                    children: [
                      // Аватар
                      ProfileAvatar(avatarPath: userAvatarPath, radius: 18),
                      const SizedBox(width: 10),
                      // Имя + логин
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName ?? userName ?? 'Профиль',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (userName != null &&
                                userName != displayName &&
                                displayName != null)
                              Text(
                                userName!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.subtle.withValues(alpha: 0.8),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Колокольчик уведомлений
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.notifications_none,
                            size: 20,
                            color: selected == SidebarNav.notifications
                                ? primary
                                : AppColors.subtle,
                          ),
                          tooltip: 'Уведомления',
                          onPressed: () => onSelect(SidebarNav.notifications),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Разделитель ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.07),
            ),
          ),

          // ── Навигация ────────────────────────────────────────────
          _NavItem(
            icon: Icons.school_outlined,
            label: 'Академический',
            selected: selected == SidebarNav.academic,
            onTap: () => onSelect(SidebarNav.academic),
          ),
          const SizedBox(height: 2),
          _NavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Общение',
            selected: selected == SidebarNav.chat,
            badge: chatUnreadCount,
            onTap: () => onSelect(SidebarNav.chat),
          ),
          const SizedBox(height: 2),
          _NavItem(
            icon: Icons.settings_outlined,
            label: 'Настройки',
            selected: selected == SidebarNav.profile,
            onTap: () => onSelect(SidebarNav.profile),
          ),

          const Spacer(),

          // ── Кнопка действия ──────────────────────────────────────
          if (showActionButton)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: onNewChat,
                  icon: Icon(actionIcon, size: 20),
                  label: Text(
                    actionLabel,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),

          const SizedBox(height: 2),

          // ── Выйти ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onLogout,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: const Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: AppColors.subtle),
                      SizedBox(width: 12),
                      Text(
                        'Выйти',
                        style:
                            TextStyle(color: AppColors.subtle, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    )); // closes Container + MediaQuery
  }
}

// ─── Элемент навигации ──────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Число в оранжевом бейдже (0 = не показывать).
  final int badge;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: selected
            ? (isDark
                ? primary.withValues(alpha: 0.15)
                : primary.withValues(alpha: 0.08))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? primary : AppColors.subtle,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: selected ? primary : null,
                    ),
                  ),
                ),
                // Бейдж непрочитанных
                if (badge > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge > 99 ? '99+' : badge.toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
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
