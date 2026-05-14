import 'package:flutter/material.dart';
import '../app_constants.dart';
import '../profile_screen.dart' show ProfileAvatar;

/// Элемент навигации в боковой панели.
enum SidebarNav { academic, chat, notifications, profile }

/// Боковая панель навигации (desktop-режим).
/// Поддерживает два режима: развёрнутый (текст + иконки) и свёрнутый (только иконки).
class Sidebar extends StatelessWidget {
  final SidebarNav selected;
  final ValueChanged<SidebarNav> onSelect;
  final VoidCallback onNewChat;
  final VoidCallback onLogout;

  /// Нажатие на карточку профиля или пункт «Настройки».
  final VoidCallback? onSettingsTap;

  /// Текст кнопки действия внизу.
  final String actionLabel;
  final IconData actionIcon;

  /// Скрыть кнопку действия (например, в академическом разделе для студента).
  final bool showActionButton;

  final String? displayName;
  final String? userName;
  final String? userAvatarPath;

  /// Суммарный счётчик непрочитанных для значка на «Общение».
  final int chatUnreadCount;

  /// Свёрнутый режим — только иконки, без текста.
  final bool collapsed;

  /// Переключить свёрнутый/развёрнутый режим.
  final VoidCallback? onToggleCollapse;

  static const double _collapsedWidth = 64.0;

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
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final primary = Theme.of(context).colorScheme.primary;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: collapsed ? _collapsedWidth : AppSizes.sidebarWidth,
        color: bgColor,
        clipBehavior: Clip.hardEdge,
        child: collapsed
            ? _buildCollapsed(context, isDark, primary)
            : _buildExpanded(context, isDark, primary),
      ),
    );
  }

  // ── Развёрнутый режим ────────────────────────────────────────────────────

  Widget _buildExpanded(BuildContext context, bool isDark, Color primary) {
    // OverflowBox даёт Column всегда полную ширину сайдбара независимо от
    // текущего значения AnimatedContainer во время анимации раскрытия.
    // Clip.hardEdge на AnimatedContainer клипирует визуальный выход за границы.
    return OverflowBox(
      minWidth: AppSizes.sidebarWidth,
      maxWidth: AppSizes.sidebarWidth,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // ── Шапка: логотип + название ───────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 28, height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => _logoFallback(primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Caspian Messenger',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Карточка пользователя ───────────────────────────────
          _buildUserCard(context, isDark, primary, collapsed: false),

          // ── Разделитель ─────────────────────────────────────────
          _buildDivider(isDark),

          // ── Навигация ───────────────────────────────────────────
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

          // ── Кнопка действия ─────────────────────────────────────
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
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),

          // ── Свернуть ─────────────────────────────────────────────
          _buildCollapseButton(isDark),

          // ── Выйти ───────────────────────────────────────────────
          _buildLogoutButton(isDark, collapsed: false),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Свёрнутый режим ─────────────────────────────────────────────────────

  Widget _buildCollapsed(BuildContext context, bool isDark, Color primary) {
    return OverflowBox(
      minWidth: _collapsedWidth,
      maxWidth: _collapsedWidth,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          const SizedBox(height: 16),

          // ── Аватар ───────────────────────────────────────────────
          _buildUserCard(context, isDark, primary, collapsed: true),

          // ── Разделитель ──────────────────────────────────────────
          _buildDivider(isDark),

          // ── Иконки навигации ─────────────────────────────────────
          _CollapsedNavIcon(
            icon: Icons.school_outlined,
            selected: selected == SidebarNav.academic,
            tooltip: 'Академический',
            onTap: () => onSelect(SidebarNav.academic),
          ),
          const SizedBox(height: 2),
          _CollapsedNavIcon(
            icon: Icons.chat_bubble_outline,
            selected: selected == SidebarNav.chat,
            badge: chatUnreadCount,
            tooltip: 'Общение',
            onTap: () => onSelect(SidebarNav.chat),
          ),
          const SizedBox(height: 2),
          _CollapsedNavIcon(
            icon: Icons.settings_outlined,
            selected: selected == SidebarNav.profile,
            tooltip: 'Настройки',
            onTap: () => onSelect(SidebarNav.profile),
          ),

          const Spacer(),

          // ── Кнопка действия (иконка) ─────────────────────────────
          if (showActionButton)
            Tooltip(
              message: actionLabel,
              child: GestureDetector(
                onTap: onNewChat,
                child: Container(
                  width: 40, height: 40,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(actionIcon, color: Colors.white, size: 20),
                ),
              ),
            ),

          // ── Развернуть (иконка) ───────────────────────────────────
          Tooltip(
            message: 'Развернуть',
            child: GestureDetector(
              onTap: onToggleCollapse,
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: Center(
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.subtle),
                ),
              ),
            ),
          ),

          // ── Выход (иконка) ────────────────────────────────────────
          _buildLogoutButton(isDark, collapsed: true),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Общие хелперы ────────────────────────────────────────────────────────

  Widget _buildUserCard(BuildContext context, bool isDark, Color primary,
      {required bool collapsed}) {
    if (collapsed) {
      return Tooltip(
        message: displayName ?? userName ?? 'Профиль',
        child: GestureDetector(
          onTap: onSettingsTap ?? () => onSelect(SidebarNav.profile),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: ProfileAvatar(avatarPath: userAvatarPath, radius: 18),
            ),
          ),
        ),
      );
    }
    return Padding(
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
                ProfileAvatar(avatarPath: userAvatarPath, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName ?? userName ?? 'Профиль',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
                SizedBox(
                  width: 34, height: 34,
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
    );
  }

  Widget _buildCollapseButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggleCollapse,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(Icons.chevron_left_rounded,
                    size: 20, color: AppColors.subtle),
                const SizedBox(width: 12),
                Text('Свернуть',
                    style: TextStyle(color: AppColors.subtle, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Divider(
        height: 1, thickness: 1,
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.07),
      ),
    );
  }

  Widget _buildLogoutButton(bool isDark, {required bool collapsed}) {
    if (collapsed) {
      return Tooltip(
        message: 'Выйти',
        child: GestureDetector(
          onTap: onLogout,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              width: _collapsedWidth, height: 40,
              child: const Center(
                child: Icon(Icons.logout, size: 20, color: AppColors.subtle),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onLogout,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
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
    );
  }

  Widget _logoFallback(Color primary) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: primary.withAlpha(30),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: primary.withAlpha(80), width: 1.5),
      ),
      child: Icon(Icons.image_outlined, size: 16, color: primary),
    );
  }
}

// ─── Иконка навигации (свёрнутый режим) ──────────────────────────────────────

class _CollapsedNavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String tooltip;
  final int badge;

  const _CollapsedNavIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.tooltip,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44, height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? primary.withValues(alpha: 0.18)
                    : primary.withValues(alpha: 0.10))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 22, color: selected ? primary : AppColors.subtle),
              if (badge > 0)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge > 9 ? '9+' : badge.toString(),
                      style: const TextStyle(
                          fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Элемент навигации (развёрнутый режим) ────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? primary : AppColors.subtle),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected ? primary : null,
                    ),
                  ),
                ),
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
                          fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
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
