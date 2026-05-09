import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../app_constants.dart';
import '../models.dart' show DeviceSession;
import '../services/auth_service.dart' as svc;
import '../services/chat_service.dart' show ChatEvent, SessionTerminated;

/// Экран управления активными устройствами / сессиями пользователя.
///
/// Показывает все активные сеансы с возможностью:
/// - завершить любой сеанс (кроме текущего)
/// - выйти с текущего устройства
/// - выйти со ВСЕХ устройств (только на мобильных платформах)
///
/// Подписывается на [events] для обновления списка в реальном времени,
/// когда сеанс другого устройства был завершён.
///
/// [embedded] — если true, экран рендерится без Scaffold (встраивается в панель
/// профиля на desktop). В этом режиме [onBack] используется для возврата назад.
class DevicesScreen extends StatefulWidget {
  final svc.AuthService auth;
  final Stream<ChatEvent> events;

  /// Вызывается после того, как пользователь выбрал выход (с этого устройства
  /// или со всех). Должен навигировать к AuthScreen.
  final VoidCallback onLogout;

  /// Если true — рендерится без Scaffold (встроенный режим панели профиля).
  final bool embedded;

  /// Вызывается при нажатии «Назад» в embedded-режиме.
  final VoidCallback? onBack;

  const DevicesScreen({
    super.key,
    required this.auth,
    required this.events,
    required this.onLogout,
    this.embedded = false,
    this.onBack,
  });

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<DeviceSession> _devices = [];
  bool _loading = true;
  String? _error;
  late StreamSubscription<ChatEvent> _eventSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Обновляем список, когда другой сеанс был завершён удалённо.
    // Событие isCurrent=true обрабатывается родительским экраном
    // (ChatListScreen / ResponsiveShell) — они вызывают logout и переходят к AuthScreen.
    _eventSub = widget.events.listen((event) {
      if (event is SessionTerminated && !event.isCurrent && mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _eventSub.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await widget.auth.getDevices();
      if (!mounted) return;
      // Сортировка: текущее устройство первым, затем по убыванию активности.
      devices.sort((a, b) {
        if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
        return b.lastActivity.compareTo(a.lastActivity);
      });
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Завершить конкретный сеанс ────────────────────────────────────────────

  Future<void> _terminateSession(DeviceSession session) async {
    final ok = await _confirmDialog(
      title: 'Завершить сеанс',
      message: 'Завершить сеанс на ${session.deviceName}?'
          '${session.location != null ? '\n${session.location}' : ''}',
      actionLabel: 'Завершить',
    );
    if (!ok || !mounted) return;

    try {
      await widget.auth.terminateSession(session.sessionId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка: $e');
    }
  }

  // ── Выйти с этого устройства ──────────────────────────────────────────────

  Future<void> _logoutCurrent() async {
    final ok = await _confirmDialog(
      title: 'Выйти с этого устройства',
      message: 'Вы выйдете из аккаунта на текущем устройстве.',
      actionLabel: 'Выйти',
    );
    if (!ok || !mounted) return;
    await widget.auth.logout();
    widget.onLogout();
  }

  // ── Выйти со всех устройств (только мобильные) ────────────────────────────

  Future<void> _terminateAll() async {
    final ok = await _confirmDialog(
      title: 'Выйти со всех устройств',
      message:
          'Все активные сеансы будут завершены, включая текущий.\n'
          'Вы будете перенаправлены на экран входа.',
      actionLabel: 'Выйти со всех',
      isDangerous: true,
    );
    if (!ok || !mounted) return;

    try {
      await widget.auth.terminateAllSessions();
      widget.onLogout();
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка: $e');
    }
  }

  // ── Вспомогательные ──────────────────────────────────────────────────────

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String actionLabel,
    bool isDangerous = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDangerous
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  /// Возвращает true на нативных мобильных платформах (Android / iOS).
  bool get _isMobile {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Иконка по платформе.
  IconData _platformIcon(String? platform) => switch (platform?.toLowerCase()) {
    'ios' || 'android' => Icons.smartphone,
    'web'              => Icons.language,
    'windows'          => Icons.desktop_windows,
    'macos'            => Icons.laptop_mac,
    'linux'            => Icons.computer,
    _                  => Icons.devices,
  };

  /// Человекочитаемое время последней активности.
  String _formatActivity(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1)  return 'Только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин. назад';
    if (diff.inHours < 24)   return '${diff.inHours} ч. назад';
    if (diff.inDays == 1)    return 'Вчера';
    if (diff.inDays < 7)     return '${diff.inDays} дн. назад';
    final d = time.day.toString().padLeft(2, '0');
    final m = time.month.toString().padLeft(2, '0');
    return '$d.$m.${time.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // Встроенный режим: без Scaffold, со своим заголовком
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Column(
        children: [
          // Заголовок-панель с кнопкой назад
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.07),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  tooltip: 'Назад',
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Устройства',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Обновить',
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Устройства'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 52, color: Colors.red.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              const Text('Не удалось загрузить устройства',
                  style: TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.subtle, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices,
                size: 52,
                color: AppColors.subtle.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('Нет активных устройств',
                style: TextStyle(color: AppColors.subtle, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // Заголовок секции
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            'АКТИВНЫЕ СЕАНСЫ (${_devices.length})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.subtle,
              letterSpacing: 0.8,
            ),
          ),
        ),

        // Карточки сеансов
        ..._devices.map((s) => _DeviceSessionTile(
          session: s,
          platformIcon: _platformIcon(s.platform),
          lastActivityLabel: _formatActivity(s.lastActivity),
          onTerminate:
              s.isCurrent ? null : () => _terminateSession(s),
          onLogoutCurrent:
              s.isCurrent ? _logoutCurrent : null,
        )),

        // «Выйти со всех устройств» — только на мобильных
        if (_isMobile) ...[
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _terminateAll,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Выйти со всех устройств',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Выйдет со всех сеансов, включая текущий.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.subtle),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Карточка одного сеанса ──────────────────────────────────────────────────

class _DeviceSessionTile extends StatelessWidget {
  final DeviceSession session;
  final IconData platformIcon;
  final String lastActivityLabel;
  final VoidCallback? onTerminate;
  final VoidCallback? onLogoutCurrent;

  const _DeviceSessionTile({
    required this.session,
    required this.platformIcon,
    required this.lastActivityLabel,
    this.onTerminate,
    this.onLogoutCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg =
        isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final subtitleColor = isDark ? Colors.white60 : AppColors.subtle;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Строка: иконка + имя + бейдж ────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Иконка платформы
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(platformIcon,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                // Имя + платформа + локация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.deviceName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (session.platform != null ||
                          session.location != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (session.platform != null)
                              _platformLabel(session.platform!),
                            if (session.location != null)
                              session.location!,
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 12, color: subtitleColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Бейдж «Это устройство»
                if (session.isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Это\nустройство',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // ── Нижняя строка: время + кнопка ────────────────────────
            Row(
              children: [
                Icon(Icons.access_time_outlined,
                    size: 13, color: subtitleColor),
                const SizedBox(width: 4),
                Text(
                  lastActivityLabel,
                  style:
                      TextStyle(fontSize: 12, color: subtitleColor),
                ),
                const Spacer(),
                // Кнопка действия
                if (onTerminate != null)
                  _ActionChip(
                    label: 'Завершить',
                    color: Colors.red,
                    onTap: onTerminate!,
                  )
                else if (onLogoutCurrent != null)
                  _ActionChip(
                    label: 'Выйти',
                    color: AppColors.subtle,
                    onTap: onLogoutCurrent!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _platformLabel(String platform) => switch (platform.toLowerCase()) {
    'ios'     => 'iOS',
    'android' => 'Android',
    'web'     => 'Браузер',
    'windows' => 'Windows',
    'macos'   => 'macOS',
    'linux'   => 'Linux',
    _         => platform,
  };
}

// ── Кнопка-чип для действий ──────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
