import 'package:flutter/material.dart';

/// Централизованные красивые уведомления-тосты.
/// Три вида: success (зелёный ✓), error (красный ✗), info (нейтральный ℹ).
abstract final class AppSnack {
  // Длительность показа
  static const _kShort  = Duration(seconds: 2);
  static const _kNormal = Duration(milliseconds: 2600);

  /// ✓ Успех — зелёный, иконка галочки.
  static void success(BuildContext context, String text,
      {Duration? duration}) =>
      _show(context, text,
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF2E7D32),
          duration: duration ?? _kShort);

  /// ✗ Ошибка — красный, иконка крестика.
  static void error(BuildContext context, String text,
      {Duration? duration}) =>
      _show(context, text,
          icon: Icons.error_rounded,
          color: const Color(0xFFC62828),
          duration: duration ?? _kNormal);

  /// ℹ Информация — акцентный цвет темы, иконка подсказки.
  static void info(BuildContext context, String text,
      {Duration? duration}) =>
      _show(context, text,
          icon: Icons.info_rounded,
          color: Theme.of(context).colorScheme.secondary,
          duration: duration ?? _kNormal);

  /// ⚠ Предупреждение — оранжевый, иконка треугольника.
  static void warn(BuildContext context, String text,
      {Duration? duration}) =>
      _show(context, text,
          icon: Icons.warning_rounded,
          color: const Color(0xFFE65100),
          duration: duration ?? _kNormal);

  // ── Внутренний рендерер ────────────────────────────────────────────────────
  static void _show(
    BuildContext context,
    String text, {
    required IconData icon,
    required Color color,
    required Duration duration,
  }) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: duration,
          backgroundColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: EdgeInsets.zero,
          content: _AppSnackContent(icon: icon, color: color, text: text),
        ),
      );
  }
}

class _AppSnackContent extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _AppSnackContent({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Color.lerp(Colors.grey[900], color, 0.18)!
        : Color.lerp(Colors.white, color, 0.10)!;
    final textColor = isDark ? Colors.white : Colors.grey[900]!;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.45 : 0.30),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
