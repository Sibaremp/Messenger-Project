import 'dart:convert';
import 'package:http/http.dart' as http;

/// Один GIF из Tenor.
class TenorGif {
  final String id;
  /// URL маленькой версии (tinygif ≈ 220px) — для сетки пикера.
  final String previewUrl;
  /// URL полного GIF — вставляется в сообщение.
  final String gifUrl;
  final int width;
  final int height;

  const TenorGif({
    required this.id,
    required this.previewUrl,
    required this.gifUrl,
    required this.width,
    required this.height,
  });
}

/// Обёртка над Tenor API v1 (demo-ключ, не нужен Google Cloud).
/// Для продакшена замените [apiKey] на свой ключ из https://developers.google.com/tenor
class TenorService {
  // Публичный demo-ключ Tenor для разработки
  static const String apiKey  = 'LIVDSRZULELA';
  static const String _base   = 'https://api.tenor.com/v1';
  static const int    _limit  = 24;

  // ── Поиск ──────────────────────────────────────────────────────────────────

  Future<List<TenorGif>> search(String query, {String? next}) async {
    final uri = Uri.parse('$_base/search').replace(queryParameters: {
      'q':            query,
      'key':          apiKey,
      'limit':        '$_limit',
      'media_filter': 'minimal',
      'contentfilter':'medium',
      'locale':       'ru_RU',
      if (next != null) 'pos': next,
    });
    return _fetch(uri);
  }

  /// Актуальные тренды (показываются на главном экране пикера).
  Future<List<TenorGif>> trending() async {
    final uri = Uri.parse('$_base/trending').replace(queryParameters: {
      'key':          apiKey,
      'limit':        '$_limit',
      'media_filter': 'minimal',
      'contentfilter':'medium',
    });
    return _fetch(uri);
  }

  // ── Внутренние ──────────────────────────────────────────────────────────────

  Future<List<TenorGif>> _fetch(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>;
      return results.map(_parseGif).whereType<TenorGif>().toList();
    } catch (_) {
      return [];
    }
  }

  TenorGif? _parseGif(dynamic item) {
    try {
      final mediaList = item['media'] as List<dynamic>;
      if (mediaList.isEmpty) return null;
      final media    = mediaList[0] as Map<String, dynamic>;
      final tiny     = media['tinygif'] as Map<String, dynamic>?;
      final full     = media['gif']     as Map<String, dynamic>?;
      if (tiny == null || full == null) return null;
      final dims     = (tiny['dims'] as List<dynamic>?)?.cast<int>();
      return TenorGif(
        id:         item['id'] as String,
        previewUrl: tiny['url'] as String,
        gifUrl:     (full['url'] as String),
        width:      dims?[0] ?? 220,
        height:     dims?[1] ?? 160,
      );
    } catch (_) {
      return null;
    }
  }
}
