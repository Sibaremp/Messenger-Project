import 'package:flutter/material.dart';

/// Цветовая палитра приложения. Приватный конструктор запрещает создание экземпляров.
class AppColors {
  const AppColors._();
  static const primary    = Color(0xFFD4765B);
  static const background = Color(0xFFF5F5F5);
  static const chatMe     = Color(0xFFD4765B);
  static const chatOther  = Color(0xFFFFFFFF);
  static const textDark   = Color(0xFF000000);
  static const textLight  = Color(0xFFFFFFFF);
  static const subtle     = Color(0xFF757575);
}

/// Общие константы разметки. Приватный конструктор запрещает создание экземпляров.
class AppSizes {
  const AppSizes._();
  static const avatarRadiusSmall      = 16.0;
  static const avatarRadiusLarge      = 24.0;
  /// Пузырьки сообщений ограничены 70 % ширины экрана.
  static const bubbleMaxWidthFactor   = 0.7;
  /// Порог переключения на десктопный трёхпанельный режим.
  static const desktopBreakpoint      = 800.0;
  /// Ширина боковой панели навигации (desktop).
  static const sidebarWidth           = 220.0;
  /// Ширина средней панели со списком чатов (desktop).
  static const middlePanelWidth       = 300.0;
}

/// Расширения файлов, воспринимаемые как видео при выборе документов.
const kVideoExtensions = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp'};

/// Форматирует [time] как HH:mm (используется внутри пузырьков сообщений).
String formatTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Заголовок группы сообщений (Telegram-style):
/// Сегодня / Вчера / День недели / ДД.ММ / ДД.ММ.ГГГГ
String formatMessageGroupDate(DateTime date) {
  final now      = DateTime.now();
  final today    = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final d        = DateTime(date.year, date.month, date.day);

  if (d == today)     return 'Сегодня';
  if (d == yesterday) return 'Вчера';
  // Текущая неделя (менее 7 дней назад)
  if (today.difference(d).inDays < 7) {
    const days = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье'];
    return days[date.weekday - 1];
  }
  final dd = date.day.toString().padLeft(2, '0');
  final mm = date.month.toString().padLeft(2, '0');
  if (d.year == now.year) return '$dd.$mm';
  return '$dd.$mm.${date.year}';
}

/// Умная метка времени для списка чатов: сегодня → HH:mm, вчера → "Вчера",
/// в течение 7 дней → сокращённый день недели, старше → "d MMM".
String formatChatTime(DateTime time) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day   = DateTime(time.year, time.month, time.day);

  if (day == today)     return formatTime(time);
  if (day == yesterday) return 'Вчера';
  if (today.difference(day).inDays < 7) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[time.weekday - 1];
  }
  const months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
  return '${time.day} ${months[time.month - 1]}';
}
