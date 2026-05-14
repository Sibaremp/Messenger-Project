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

/// Форматирует [time] как HH:mm в **локальном** часовом поясе устройства.
/// Сервер хранит время в UTC; здесь оно конвертируется перед отображением,
/// поэтому сообщение, отправленное во Вьетнаме в 03:00 UTC+7, на устройстве
/// в Алматы (UTC+5) отобразится как 01:00.
String formatTime(DateTime time) {
  final local = time.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Заголовок группы сообщений (Telegram-style):
/// Сегодня / Вчера / День недели / ДД.ММ / ДД.ММ.ГГГГ
/// Все сравнения выполняются в **локальном** часовом поясе.
String formatMessageGroupDate(DateTime date) {
  final local     = date.toLocal();
  final now       = DateTime.now();
  final today     = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final d         = DateTime(local.year, local.month, local.day);

  if (d == today)     return 'Сегодня';
  if (d == yesterday) return 'Вчера';
  // Текущая неделя (менее 7 дней назад)
  if (today.difference(d).inDays < 7) {
    const days = ['Понедельник','Вторник','Среда','Четверг','Пятница','Суббота','Воскресенье'];
    return days[local.weekday - 1];
  }
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  if (d.year == now.year) return '$dd.$mm';
  return '$dd.$mm.${local.year}';
}

/// Умная метка времени для списка чатов: сегодня → HH:mm, вчера → "Вчера",
/// в течение 7 дней → сокращённый день недели, старше → "d MMM".
/// Конвертирует в локальный часовой пояс перед форматированием.
String formatChatTime(DateTime time) {
  final local     = time.toLocal();
  final now       = DateTime.now();
  final today     = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day       = DateTime(local.year, local.month, local.day);

  if (day == today)     return formatTime(time);
  if (day == yesterday) return 'Вчера';
  if (today.difference(day).inDays < 7) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[local.weekday - 1];
  }
  const months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
  return '${local.day} ${months[local.month - 1]}';
}
