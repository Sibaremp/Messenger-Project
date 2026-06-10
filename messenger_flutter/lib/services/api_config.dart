import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Конфигурация подключения к серверу.
///
/// Автоматически выбирает адрес:
///   - Android-эмулятор → 10.0.2.2
///   - Web / десктоп / iOS-симулятор → localhost
/// Для реального устройства или продакшена переопредели [overrideHost].
class ApiConfig {
  /// Порт сервера.
  static const int port = 5216;

  /// Туннель (ngrok, Cloudflare Tunnel и т.д.). Если задан — используется вместо локального хоста.
  /// Формат: только хост без схемы и порта, например:
  ///   `abc123.trycloudflare.com`
  static const String? tunnelHost = 'api.caspianmessenger.kz';

  /// Переопределение хоста (например, `192.168.1.10` для реального устройства
  /// или прод-домен). Если не установлено, используется автоопределение.
  static String? overrideHost;

  static bool get _useNgrok => tunnelHost != null && tunnelHost!.isNotEmpty;

  static String get _host {
    if (_useNgrok) return tunnelHost!;
    if (overrideHost != null && overrideHost!.isNotEmpty) return overrideHost!;
    if (!kIsWeb && Platform.isAndroid) return '10.0.2.2';
    return 'localhost';
  }

  /// Корень сервера (без /api). Используется для резолвинга путей вида `/uploads/...`.
  /// ngrok всегда HTTPS и не требует порта.
  static String get origin =>
      _useNgrok ? 'https://$_host' : 'http://$_host:$port';

  /// Базовый URL REST API (без завершающего слеша).
  static String get baseUrl => '$origin/api';

  /// URL SignalR-хаба для получения событий в реальном времени.
  static String get hubUrl => '$origin/hub/chat';

  /// URL SignalR-хаба для сигнализации WebRTC звонков.
  static String get callHubUrl => '$origin/hub/calls';

  /// Эндпоинт загрузки голосовых сообщений.
  /// POST multipart/form-data, field «file». Ответ: { "url": "..." }
  static String get audioUploadUrl => '$baseUrl/messages/upload-audio';

  /// Превращает путь, полученный от сервера, в абсолютный URL для загрузки.
  /// - `null` / пустая строка → `null`
  /// - абсолютный URL с `localhost`/`127.0.0.1` → заменяется на текущий хост
  ///   (чтобы картинки грузились на реальном устройстве / эмуляторе)
  /// - любой другой абсолютный URL → возвращается как есть
  /// - серверный путь `/uploads/...`, `/thumbnails/...` и т.д. → префиксуется origin
  /// - всё остальное (локальный путь устройства) → возвращается как есть
  static String? resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      // Сервер иногда возвращает абсолютные URL с localhost/127.0.0.1.
      // Заменяем всю origin-часть (схема + хост + порт) на текущий origin,
      // чтобы корректно работало и с ngrok (https, без порта), и локально.
      return path.replaceFirstMapped(
        RegExp(r'https?://(?:localhost|127\.0\.0\.1)(?::\d+)?'),
        (_) => origin,
      );
    }
    if (isServerMediaPath(path)) return '$origin$path';
    return path;
  }

  /// Возвращает true, если [path] — путь, обслуживаемый сервером (а не локальный файл).
  ///
  /// ВАЖНО: на Android локальные файлы из image_picker возвращаются как абсолютные
  /// пути, начинающиеся с `/` (например, `/data/user/0/.../cache/xxx.jpg`). Поэтому
  /// одной проверки `startsWith('/')` недостаточно — нужно сверяться с конкретным
  /// префиксом `/uploads/`, который использует сервер.
  static bool isServerMediaPath(String? path) {
    if (path == null || path.isEmpty) return false;
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('/uploads/') ||
        path.startsWith('/avatars/') ||
        path.startsWith('/media/') ||
        path.startsWith('/thumbnails/');
  }

  /// Базовые HTTP-заголовки (без авторизации).
  static Map<String, String> get baseHeaders => {
    'Content-Type': 'application/json',
  };

  /// Таймаут HTTP-запросов.
  static const Duration httpTimeout = Duration(seconds: 30);

  /// Интервал переподключения SignalR при обрыве связи.
  static const Duration wsReconnectDelay = Duration(seconds: 3);

  /// Максимальный размер загружаемого файла (100 МБ).
  static const int maxUploadSize = 100 * 1024 * 1024;
}
