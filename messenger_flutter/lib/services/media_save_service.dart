import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models.dart';
import 'api_config.dart';
import 'file_download_service.dart';

/// Сохраняет файлы в видимую пользователю папку «CaspianMessenger».
///
/// Расположение:
///   Android  → {внешнее_хранилище_приложения}/CaspianMessenger
///              Путь: /storage/emulated/0/Android/data/{package}/files/CaspianMessenger
///              Виден в приложении «Файлы» → Внутр. хранилище → Android → data → ...
///   iOS      → {Documents}/CaspianMessenger  (виден в «Файлах» → На iPhone)
///   Desktop  → ~/Downloads/CaspianMessenger
class MediaSaveService {
  MediaSaveService._();
  static final MediaSaveService instance = MediaSaveService._();

  static const folderName = 'CaspianMessenger';

  // ── Папка по умолчанию ───────────────────────────────────────────────────────

  /// Путь к папке CaspianMessenger на текущей платформе.
  Future<String> get defaultFolder async {
    if (kIsWeb) throw UnsupportedError('Web не поддерживает файловую систему');
    if (Platform.isAndroid) {
      // Внешнее хранилище приложения — доступно без разрешений на всех версиях Android.
      final ext = await getExternalStorageDirectory();
      if (ext != null) return '${ext.path}/$folderName';
    } else if (!Platform.isIOS) {
      // Desktop: ~/Downloads/CaspianMessenger
      final dl = await getDownloadsDirectory();
      if (dl != null) return '${dl.path}/$folderName';
    }
    // iOS и fallback: {Documents}/CaspianMessenger (видна в приложении «Файлы»)
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/$folderName';
  }

  // ── Сохранение ───────────────────────────────────────────────────────────────

  /// Сохраняет вложение в папку по умолчанию.
  /// Возвращает полный путь к сохранённому файлу.
  Future<String> saveToDefaultFolder(Attachment att) async {
    final folder = await defaultFolder;
    await Directory(folder).create(recursive: true);
    final destPath = '$folder${Platform.pathSeparator}${att.fileName}';
    await _writeTo(att, destPath);
    return destPath;
  }

  // ── Статистика и очистка (для настроек) ─────────────────────────────────────

  /// Суммарный размер папки CaspianMessenger в байтах.
  Future<int> get defaultFolderSizeBytes async {
    try {
      final folder = await defaultFolder;
      return await _dirSize(Directory(folder));
    } catch (_) {
      return 0;
    }
  }

  /// Очищает содержимое папки CaspianMessenger (сама папка остаётся).
  Future<void> clearDefaultFolder() async {
    try {
      final folder = await defaultFolder;
      final dir = Directory(folder);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
    } catch (_) {}
  }

  // ── Внутреннее ──────────────────────────────────────────────────────────────

  Future<void> _writeTo(Attachment att, String destPath) async {
    if (ApiConfig.isServerMediaPath(att.path)) {
      // Сначала пробуем взять из кэша загрузчика (чтобы не тратить трафик).
      final cached = await FileDownloadService.instance.getLocalPathIfExists(att.path);
      if (cached != null) {
        await File(cached).copy(destPath);
        return;
      }
      // Скачиваем напрямую с сервера.
      final url = ApiConfig.resolveMediaUrl(att.path);
      if (url == null) throw Exception('Не удалось построить URL для ${att.path}');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      await File(destPath).writeAsBytes(response.bodyBytes);
    } else {
      // Локальный файл — просто копируем.
      await File(att.path).copy(destPath);
    }
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    try {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }
}
