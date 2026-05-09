import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'api_config.dart';

/// Состояние загрузки одного файла.
enum DownloadState { idle, downloading, completed, failed }

class DownloadProgress {
  final DownloadState state;
  /// 0.0–1.0, либо null если размер неизвестен.
  final double? progress;
  /// Скачанных байт.
  final int received;
  /// Всего байт (из Content-Length). 0 если неизвестно.
  final int total;
  /// Локальный путь к готовому файлу (если [state] == completed).
  final String? localPath;
  final String? error;

  const DownloadProgress({
    required this.state,
    this.progress,
    this.received = 0,
    this.total = 0,
    this.localPath,
    this.error,
  });
}

/// Сервис скачивания файлов с сервера с отслеживанием прогресса.
///
/// - Файлы кэшируются локально в `{ApplicationDocuments}/downloads/{safeKey}`.
/// - Для каждого серверного пути есть свой broadcast-стрим прогресса.
/// - Вызов [download] на уже скачанный файл — no-op, просто вернёт путь.
class FileDownloadService {
  FileDownloadService._();
  static final FileDownloadService instance = FileDownloadService._();

  final Map<String, StreamController<DownloadProgress>> _streams = {};
  final Map<String, DownloadProgress> _lastState = {};
  final Map<String, StreamSubscription<List<int>>> _active = {};

  /// Поток прогресса для заданного серверного пути/URL.
  /// Всегда сразу отдаёт текущее состояние новому подписчику.
  Stream<DownloadProgress> watch(String serverPath) {
    final key = _key(serverPath);
    final ctrl = _streams.putIfAbsent(
      key,
      () => StreamController<DownloadProgress>.broadcast(
        onListen: () {
          final last = _lastState[key];
          if (last != null) _streams[key]?.add(last);
        },
      ),
    );
    // Стартовое состояние: проверим, нет ли уже файла на диске.
    _ensureInitialState(serverPath, key);
    return ctrl.stream;
  }

  /// Проверяет, есть ли уже локально скачанный файл.
  Future<String?> getLocalPathIfExists(String serverPath) async {
    final path = await _localPathFor(serverPath);
    final file = File(path);
    if (await file.exists()) return path;
    return null;
  }

  /// Начинает (или продолжает наблюдать) скачивание. Возвращает локальный путь
  /// по завершении. Если файл уже скачан — возвращает его путь сразу.
  Future<String> download(String serverPath, {String? fileName}) async {
    final key = _key(serverPath);
    final localPath = await _localPathFor(serverPath, fileName: fileName);
    final file = File(localPath);

    if (await file.exists()) {
      _emit(key, DownloadProgress(
        state: DownloadState.completed,
        progress: 1.0,
        received: await file.length(),
        total: await file.length(),
        localPath: localPath,
      ));
      return localPath;
    }

    // Если уже качается — ждём завершения.
    if (_active.containsKey(key)) {
      final completer = Completer<String>();
      late StreamSubscription<DownloadProgress> sub;
      sub = watch(serverPath).listen((p) {
        if (p.state == DownloadState.completed && p.localPath != null) {
          completer.complete(p.localPath!);
          sub.cancel();
        } else if (p.state == DownloadState.failed) {
          completer.completeError(p.error ?? 'Download failed');
          sub.cancel();
        }
      });
      return completer.future;
    }

    final url = ApiConfig.resolveMediaUrl(serverPath);
    if (url == null) {
      throw ArgumentError('Не удалось построить URL для $serverPath');
    }

    _emit(key, const DownloadProgress(state: DownloadState.downloading));

    final request = http.Request('GET', Uri.parse(url));
    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      // Создаём каталог.
      await Directory(file.parent.path).create(recursive: true);
      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      int received = 0;

      final completer = Completer<String>();
      final sub = response.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          _emit(key, DownloadProgress(
            state: DownloadState.downloading,
            progress: total > 0 ? received / total : null,
            received: received,
            total: total,
          ));
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          _emit(key, DownloadProgress(
            state: DownloadState.completed,
            progress: 1.0,
            received: received,
            total: total,
            localPath: localPath,
          ));
          _active.remove(key);
          client.close();
          completer.complete(localPath);
        },
        onError: (Object e, StackTrace _) async {
          await sink.close();
          if (await file.exists()) await file.delete();
          _emit(key, DownloadProgress(
            state: DownloadState.failed,
            error: e.toString(),
          ));
          _active.remove(key);
          client.close();
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );
      _active[key] = sub;
      return completer.future;
    } catch (e) {
      _emit(key, DownloadProgress(
        state: DownloadState.failed,
        error: e.toString(),
      ));
      _active.remove(key);
      client.close();
      rethrow;
    }
  }

  /// Отмена текущей загрузки (если идёт).
  Future<void> cancel(String serverPath) async {
    final key = _key(serverPath);
    final sub = _active.remove(key);
    await sub?.cancel();
    final path = await _localPathFor(serverPath);
    final file = File(path);
    if (await file.exists()) await file.delete();
    _emit(key, const DownloadProgress(state: DownloadState.idle));
  }

  /// Удалить локальный файл (кнопка "убрать из памяти устройства").
  Future<void> removeLocal(String serverPath) async {
    final key = _key(serverPath);
    final path = await _localPathFor(serverPath);
    final file = File(path);
    if (await file.exists()) await file.delete();
    _emit(key, const DownloadProgress(state: DownloadState.idle));
  }

  // ── Внутреннее ──────────────────────────────────────────────────────────

  Future<void> _ensureInitialState(String serverPath, String key) async {
    if (_lastState.containsKey(key)) return;
    final path = await _localPathFor(serverPath);
    final file = File(path);
    if (await file.exists()) {
      _emit(key, DownloadProgress(
        state: DownloadState.completed,
        progress: 1.0,
        received: await file.length(),
        total: await file.length(),
        localPath: path,
      ));
    } else {
      _emit(key, const DownloadProgress(state: DownloadState.idle));
    }
  }

  void _emit(String key, DownloadProgress progress) {
    _lastState[key] = progress;
    _streams[key]?.add(progress);
  }

  String _key(String serverPath) => serverPath;

  Future<String> _localPathFor(String serverPath, {String? fileName}) async {
    final dir = await getApplicationDocumentsDirectory();
    // Безопасное имя каталога на базе пути: меняем / \ : на _
    final safe = serverPath.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    final name = fileName ?? _extractName(serverPath);
    return '${dir.path}/downloads/$safe/$name';
  }

  String _extractName(String serverPath) {
    final cleaned = serverPath.split('?').first;
    final seg = cleaned.split('/').where((s) => s.isNotEmpty).toList();
    return seg.isEmpty ? 'file' : seg.last;
  }
}
