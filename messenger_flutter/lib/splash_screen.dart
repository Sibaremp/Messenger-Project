import 'package:flutter/material.dart';

/// Стартовый экран в стиле Telegram/WhatsApp:
/// логотип + прогресс-бар + надпись о сквозном шифровании.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _fadeIn   = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark     = brightness == Brightness.dark;

    final bg        = isDark ? const Color(0xFF0F0F0F) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subColor  = isDark ? const Color(0xFF8A8A8A) : const Color(0xFF9E9E9E);
    final barBg     = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.07);

    // Используем цвет схемы Material если контекст уже содержит Theme.
    Color primaryColor;
    try {
      primaryColor = Theme.of(context).colorScheme.primary;
    } catch (_) {
      primaryColor = const Color(0xFF1976D2);
    }

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Центральная часть ──────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _fadeIn,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Логотип
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.chat_bubble,
                              color: Colors.white, size: 44),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Название приложения
                    Text(
                      'Caspian Messenger',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Прогресс-бар
                    SizedBox(
                      width: 88,
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (context2, child2) => ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress.value,
                            minHeight: 3,
                            backgroundColor: barBg,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Нижняя надпись о шифровании ────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: FadeTransition(
                opacity: _fadeIn,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 13, color: subColor),
                    const SizedBox(width: 5),
                    Text(
                      'Сообщения защищены сквозным шифрованием',
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
