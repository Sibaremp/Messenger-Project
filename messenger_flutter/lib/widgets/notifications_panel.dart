import 'dart:async';
import 'package:flutter/material.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';

/// Панель уведомлений для desktop-режима.
/// Получает уведомления двумя путями:
///   1. При открытии — загружает историю через REST (GET /api/notifications)
///   2. В реальном времени — слушает [ChatService.events] на AdminNotificationReceived
class NotificationsPanel extends StatefulWidget {
  final ChatService service;
  const NotificationsPanel({super.key, required this.service});

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  int _selectedFilter = 0; // 0 = все, 1 = за последние сутки
  bool _loading = true;
  String? _error;

  final List<AdminNotification> _notifications = [];
  StreamSubscription<ChatEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _load();
    _eventSub = widget.service.events.listen((event) {
      if (event is AdminNotificationReceived && mounted) {
        setState(() {
          // Добавляем в начало, избегаем дублей
          _notifications.removeWhere((n) => n.id == event.id);
          _notifications.insert(0, AdminNotification(
            id:     event.id,
            title:  event.title,
            body:   event.body,
            target: 'all',
            sentAt: event.sentAt,
          ));
        });
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final items = await widget.service.loadAdminNotifications();
      if (!mounted) return;
      setState(() {
        _notifications
          ..clear()
          ..addAll(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Не удалось загрузить уведомления'; });
    }
  }

  List<AdminNotification> get _filtered {
    if (_selectedFilter == 1) {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      return _notifications.where((n) => n.sentAt.isAfter(cutoff)).toList();
    }
    return _notifications;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items  = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Заголовок ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 4),
          child: Row(
            children: [
              Text(
                'Центр уведомлений',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                color: AppColors.subtle,
                tooltip: 'Обновить',
                onPressed: _load,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Системные уведомления от администратора',
            style: TextStyle(fontSize: 13, color: AppColors.subtle),
          ),
        ),
        const SizedBox(height: 20),

        // ── Фильтр ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            children: [
              _FilterChip(
                label: 'Все',
                selected: _selectedFilter == 0,
                onTap: () => setState(() => _selectedFilter = 0),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'За последние сутки',
                selected: _selectedFilter == 1,
                onTap: () => setState(() => _selectedFilter = 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Divider(
          height: 1,
          color: isDark
              ? Colors.white.withAlpha(25)
              : Colors.grey.withAlpha(50),
        ),

        // ── Список ─────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, color: AppColors.subtle, size: 40),
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: AppColors.subtle)),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _load, child: const Text('Повторить')),
                        ],
                      ),
                    )
                  : items.isEmpty
                      ? Center(
                          child: Text(
                            'Нет уведомлений',
                            style: TextStyle(color: AppColors.subtle, fontSize: 15),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 32,
                            color: isDark
                                ? Colors.white.withAlpha(20)
                                : Colors.grey.withAlpha(38),
                          ),
                          itemBuilder: (context, index) =>
                              _NotificationCard(notification: items[index]),
                        ),
        ),
      ],
    );
  }
}

// ─── Чип-фильтр ────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : AppColors.subtle.withAlpha(76),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.subtle,
          ),
        ),
      ),
    );
  }
}

// ─── Карточка уведомления ───────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final AdminNotification notification;
  const _NotificationCard({required this.notification});

  String _targetLabel(String target) => switch (target.toLowerCase()) {
    'students' => 'Студенты',
    'teachers' => 'Преподаватели',
    _          => 'Все',
  };

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(local.day)}.${p(local.month)}.${local.year}  ${p(local.hour)}:${p(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Иконка администратора
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.campaign_outlined, color: Theme.of(context).colorScheme.primary, size: 26),
        ),
        const SizedBox(width: 14),

        // Заголовок + текст
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _targetLabel(notification.target),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                notification.body,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatTime(notification.sentAt),
                style: TextStyle(fontSize: 11, color: AppColors.subtle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
