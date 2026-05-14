import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:signalr_netcore/signalr_client.dart';
import '../models.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'chat_service.dart';
import 'encryption_service.dart';

/// Реализация [ChatService] для работы с удалённым сервером через REST API + SignalR.
class ApiChatService implements ChatService {
  final AuthService _auth;
  final _eventController = StreamController<ChatEvent>.broadcast();

  HubConnection? _hub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  ApiChatService(this._auth) {
    _connectSignalR();
  }

  // ── HTTP-хелперы ──────────────────────────────────────────────────────────

  String get _base => ApiConfig.baseUrl;
  Map<String, String> get _headers => _auth.authHeaders;
  String get _uid => _auth.currentUser?.id ?? '';

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      Uri.parse('$_base$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(ApiConfig.httpTimeout);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final r = await http.put(
      Uri.parse('$_base$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(ApiConfig.httpTimeout);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await http.get(
      Uri.parse('$_base$path'),
      headers: _headers,
    ).timeout(ApiConfig.httpTimeout);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> _delete(String path, [Map<String, dynamic>? body]) async {
    final request = http.Request('DELETE', Uri.parse('$_base$path'));
    request.headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await request.send().timeout(ApiConfig.httpTimeout);
    final r = await http.Response.fromStream(streamed);
    return _handleResponse(r);
  }

  Map<String, dynamic> _handleResponse(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return {};
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    final msg = r.body.isNotEmpty
        ? (jsonDecode(r.body) as Map<String, dynamic>)['message'] ?? 'Ошибка сервера'
        : 'Ошибка сервера (${r.statusCode})';
    throw ApiException(msg as String, r.statusCode);
  }

  Chat _chatFromJson(Map<String, dynamic> j) =>
      Chat.fromJson(j, currentUserId: _uid);

  /// Парсит чат из JSON и расшифровывает тексты сообщений.
  Future<Chat> _chatFromJsonDecrypted(Map<String, dynamic> j) =>
      _decryptChat(_chatFromJson(j));

  // ── SignalR ───────────────────────────────────────────────────────────────

  void _connectSignalR() {
    if (_disposed || _auth.token == null) return;
    try {
      _hub = HubConnectionBuilder()
          .withUrl(
            ApiConfig.hubUrl,
            options: HttpConnectionOptions(
              accessTokenFactory: () async => _auth.token ?? '',
            ),
          )
          .build();

      _hub!.on('ReceiveEvent', _onHubEvent);
      _hub!.onclose(({error}) => _scheduleReconnect());

      _hub!.start()?.then((_) async {
        if (_disposed) return;
        // Выполняем обмен ключами Диффи-Хеллмана (X25519) для шифрования сообщений.
        await EncryptionService.instance.initAndExchange(_base, _headers);
        // Сигнализируем UI о восстановлении связи → перезагрузить список чатов.
        _eventController.add(ConnectionRestored());
      }).catchError((_) {
        _scheduleReconnect();
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(ApiConfig.wsReconnectDelay, _connectSignalR);
  }

  void _onHubEvent(List<Object?>? args) {
    _processHubEvent(args); // fire-and-forget: async расшифровка не блокирует
  }

  Future<void> _processHubEvent(List<Object?>? args) async {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null) return;
      final type = data['type'] as String;
      switch (type) {
        case 'message_received':
          final chatId  = data['chatId'] as String;
          var msgData   = data['message'] as Map<String, dynamic>;
          // Расшифровываем текст сообщения
          final rawText = msgData['text'] as String? ?? '';
          final plain   = await EncryptionService.instance.decryptText(rawText);
          msgData = Map<String, dynamic>.from(msgData)..['text'] = plain;
          final msg = Message.fromJson(msgData, currentUserId: _uid);
          _eventController.add(MessageReceived(chatId, msg));
          // Сразу подтверждаем доставку отправителю (sent → delivered).
          if (!msg.isMe) _markDelivered(chatId, msg.id);
        case 'message_edited':
          final encNewText = data['newText'] as String;
          final plainNew   = await EncryptionService.instance.decryptText(encNewText);
          _eventController.add(MessageEdited(
            data['chatId'] as String,
            data['messageId'] as String,
            plainNew,
          ));
        case 'message_deleted':
          _eventController.add(MessageDeleted(
            data['chatId'] as String,
            (data['messageIds'] as List<dynamic>).cast<String>(),
          ));
        case 'chat_updated':
          _eventController.add(ChatUpdated(
            _chatFromJson(data['chat'] as Map<String, dynamic>),
          ));
        case 'chat_deleted':
          _eventController.add(ChatDeleted(data['chatId'] as String));
        case 'message_pinned':
          _eventController.add(MessagePinned(
            data['chatId'] as String,
            data['messageId'] as String,
          ));
        case 'message_unpinned':
          _eventController.add(MessageUnpinned(
            data['chatId'] as String,
            data['messageId'] as String,
          ));
        case 'poll_voted':
          _eventController.add(PollVoted(
            data['chatId'] as String,
            data['messageId'] as String,
            data['userId'] as String,
            (data['optionIds'] as List<dynamic>).cast<String>(),
          ));
        case 'poll_closed':
          _eventController.add(PollClosed(
            data['chatId'] as String,
            data['messageId'] as String,
          ));
        case 'admin_notification':
          _eventController.add(AdminNotificationReceived(
            id:     (data['id'] as num?)?.toInt() ?? 0,
            title:  data['title'] as String? ?? '',
            body:   data['body']  as String? ?? '',
            sentAt: DateTime.tryParse(
                        data['sentAt'] as String? ?? '') ??
                    DateTime.now(),
          ));
        case 'session_terminated':
          _eventController.add(SessionTerminated(
            data['sessionId'] as String,
            isCurrent: data['isCurrent'] as bool? ?? false,
          ));
        case 'message_status':
          // Сервер шлёт "sent" / "delivered" / "read"; если прилетит что-то
          // неожиданное — молча игнорируем, не валим поток.
          final statusStr = data['status'] as String? ?? 'sent';
          MessageStatus parsed;
          try {
            parsed = MessageStatus.values.byName(statusStr);
          } catch (_) {
            parsed = MessageStatus.sent;
          }
          _eventController.add(MessageStatusChanged(
            data['chatId'] as String,
            data['messageId'] as String,
            parsed,
          ));
      }
    } catch (_) {
      // Некорректный пакет — игнорируем
    }
  }

  // ── ChatService API ───────────────────────────────────────────────────────

  Future<List<dynamic>> _getList(String path) async {
    final r = await http.get(Uri.parse('$_base$path'), headers: _headers)
        .timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) throw ApiException('Ошибка запроса', r.statusCode);
    return jsonDecode(r.body) as List<dynamic>;
  }

  @override
  Future<List<Chat>> loadChats() async {
    final list  = await _getList('/chats');
    final chats = list.map((j) => _chatFromJson(j as Map<String, dynamic>)).toList();
    return Future.wait(chats.map(_decryptChat));
  }

  /// Расшифровывает текст всех сообщений в чате.
  Future<Chat> _decryptChat(Chat chat) async {
    if (!EncryptionService.instance.isReady) return chat;
    final msgs = await Future.wait(
      chat.messages.map((m) async =>
          m.copyWith(text: await EncryptionService.instance.decryptText(m.text))),
    );
    return chat.copyWith(messages: msgs);
  }

  @override
  Future<List<AdminNotification>> loadAdminNotifications() async {
    try {
      final list = await _getList('/notifications');
      return list
          .map((j) => AdminNotification.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Chat> sendMessage({
    required String chatId,
    required String text,
    Attachment? attachment,
    List<Attachment>? attachments,
    String senderName = 'Я',
    String? senderGroup,
    ReplyInfo? replyTo,
    List<Mention> mentions = const [],
    bool postAsCommunity = false,
  }) async {
    // Одиночный файл
    Attachment? uploaded = attachment;
    if (attachment != null && !ApiConfig.isServerMediaPath(attachment.path)) {
      uploaded = await _uploadAttachment(attachment);
    }

    // Медиаальбом — загружаем каждый файл последовательно
    List<Attachment>? uploadedList;
    if (attachments != null && attachments.isNotEmpty) {
      uploadedList = [];
      for (final att in attachments) {
        if (!ApiConfig.isServerMediaPath(att.path)) {
          uploadedList.add(await _uploadAttachment(att));
        } else {
          uploadedList.add(att);
        }
      }
    }

    final encText = await EncryptionService.instance.encryptText(text);
    final body = <String, dynamic>{
      'text': encText,
      if (uploaded != null && uploadedList == null) 'attachment': uploaded.toJson(),
      if (uploadedList != null && uploadedList.isNotEmpty)
        'attachments': uploadedList.map((a) => a.toJson()).toList(),
      if (replyTo != null) 'replyTo': replyTo.toJson(),
      if (mentions.isNotEmpty)
        'mentions': mentions.map((m) => m.toJson()).toList(),
      if (postAsCommunity) 'postAsCommunity': true,
    };
    final data = await _post('/chats/$chatId/messages', body);
    return _chatFromJsonDecrypted(data);
  }

  /// Заливает файл на сервер через POST /api/files/upload (multipart) и
  /// возвращает новый Attachment с серверным путём.
  /// Аудио-файлы направляются на отдельный эндпоинт [ApiConfig.audioUploadUrl].
  Future<Attachment> _uploadAttachment(Attachment src) async {
    if (src.type == AttachmentType.audio) return _uploadAudio(src);

    final file = File(src.path);
    if (!await file.exists()) {
      throw ApiException('Файл не найден: ${src.path}', 0);
    }
    final req = http.MultipartRequest('POST', Uri.parse('$_base/files/upload'))
      ..headers['Authorization'] = _headers['Authorization'] ?? ''
      ..files.add(await http.MultipartFile.fromPath(
        'file', file.path,
        filename: src.fileName,
      ));
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'Ошибка загрузки файла';
      try { msg = (jsonDecode(resp.body) as Map<String, dynamic>)['message']?.toString() ?? msg; } catch (_) {}
      throw ApiException(msg, resp.statusCode);
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final serverPath = data['path'] as String;
    final typeStr = (data['type'] as String?) ?? src.type.name;
    AttachmentType parsedType;
    try {
      parsedType = AttachmentType.values.byName(typeStr);
    } catch (_) {
      parsedType = src.type;
    }
    // Также забираем thumbnailPath и durationMs, которые сервер генерирует
    // при загрузке видео. Без них они не попадут в тело запроса на создание
    // сообщения, и превью не будет сохранено в чате.
    return Attachment(
      path: serverPath,
      type: parsedType,
      fileName: (data['fileName'] as String?) ?? src.fileName,
      fileSize: (data['fileSize'] as num?)?.toInt() ?? src.fileSize,
      thumbnailPath: (data['thumbnailPath'] ?? data['thumbnail_path']) as String?,
      durationMs: ((data['durationMs'] ?? data['duration_ms']) as num?)?.toInt(),
    );
  }

  /// Загружает голосовое сообщение на [ApiConfig.audioUploadUrl].
  /// Ответ сервера: { "url": "http://host/uploads/audio/uuid.ext" }
  ///
  /// Из абсолютного URL извлекается **только путь** (`/uploads/audio/uuid.ext`),
  /// который сохраняется в БД. Это позволяет корректно загружать аудио
  /// на любом устройстве (включая реальные телефоны, не только эмулятор).
  Future<Attachment> _uploadAudio(Attachment src) async {
    final file = File(src.path);
    if (!await file.exists()) {
      throw ApiException('Файл не найден: ${src.path}', 0);
    }

    final fileSize = await file.length();

    final req = http.MultipartRequest(
      'POST', Uri.parse(ApiConfig.audioUploadUrl),
    )
      ..headers['Authorization'] = _headers['Authorization'] ?? ''
      ..files.add(await http.MultipartFile.fromPath(
        'file', file.path,
        filename: src.fileName,
        contentType: _audioMimeType(src.fileName),
      ));
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      String msg = 'Ошибка загрузки аудио';
      try { msg = (jsonDecode(resp.body) as Map<String, dynamic>)['message']?.toString() ?? msg; } catch (_) {}
      throw ApiException(msg, resp.statusCode);
    }

    final absoluteUrl =
        (jsonDecode(resp.body) as Map<String, dynamic>)['url'] as String;

    // Сервер возвращает полный URL вида http://host/uploads/audio/uuid.ext.
    // Сохраняем только путь (/uploads/audio/uuid.ext), чтобы он был
    // переносимым и корректно работал на любом устройстве через resolveMediaUrl.
    final relativePath = Uri.tryParse(absoluteUrl)?.path ?? absoluteUrl;

    return Attachment(
      path:      relativePath,   // /uploads/audio/uuid.ext
      type:      AttachmentType.audio,
      fileName:  src.fileName,
      fileSize:  fileSize,
      durationMs: src.durationMs,
    );
  }

  /// Возвращает корректный MIME-тип для аудиофайла по расширению.
  static MediaType _audioMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return switch (ext) {
      'ogg'  => MediaType('audio', 'ogg'),
      'wav'  => MediaType('audio', 'wav'),
      'mp3'  => MediaType('audio', 'mpeg'),
      'aac'  => MediaType('audio', 'aac'),
      'm4a'  => MediaType('audio', 'x-m4a'),   // AAC в контейнере MPEG-4
      'flac' => MediaType('audio', 'flac'),
      _      => MediaType('audio', 'mp4'),
    };
  }

  @override
  Future<Chat> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final encText = await EncryptionService.instance.encryptText(newText);
    final data = await _put('/chats/$chatId/messages/$messageId', {'text': encText});
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> deleteMessages({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final data = await _delete('/chats/$chatId/messages', {'ids': messageIds});
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> forwardMessages({
    required String targetChatId,
    required List<Message> messages,
  }) async {
    final data = await _post('/chats/$targetChatId/forward', {
      'messageIds': messages.map((m) => m.id).toList(),
    });
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> createDirectChat({required String contactName, bool isAcademic = false}) async {
    final data = await _post('/chats/direct', {
      'contactName': contactName,
      'isAcademic': isAcademic,
    });
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> createGroupOrCommunity({
    required String name,
    required ChatType type,
    required List<ChatMember> members,
    String? adminName,
    bool isAcademic = false,
    String? description,
  }) async {
    final data = await _post('/chats/group', {
      'name': name,
      'type': type.name,
      'members': members.map((m) => m.toJson()).toList(),
      if (adminName != null) 'adminName': adminName,
      'isAcademic': isAcademic,
      if (description != null) 'description': description,
    });
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> updateChatSettings(Chat chat) async {
    Chat toSave = chat;
    // Если аватар — локальный файл (ещё не загружен на сервер), заливаем его
    // и подменяем путь на серверный URL перед отправкой настроек.
    if (chat.avatarPath != null &&
        chat.avatarPath!.isNotEmpty &&
        !ApiConfig.isServerMediaPath(chat.avatarPath)) {
      final serverPath = await _uploadChatAvatar(chat.id, chat.avatarPath!);
      if (serverPath != null) {
        toSave = chat.copyWith(avatarPath: serverPath);
      }
    }
    final data = await _put('/chats/${toSave.id}/settings', toSave.toJson());
    return _chatFromJsonDecrypted(data);
  }

  /// Загружает аватар чата на сервер через POST /api/chats/{id}/avatar.
  /// Возвращает серверный путь/URL или null при ошибке.
  Future<String?> _uploadChatAvatar(String chatId, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    final req = http.MultipartRequest(
      'POST', Uri.parse('$_base/chats/$chatId/avatar'),
    )
      ..headers['Authorization'] = _headers['Authorization'] ?? ''
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['avatarUrl'] ?? data['avatarPath'] ?? data['path']) as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteChat(String chatId) async {
    await _delete('/chats/$chatId');
    _eventController.add(ChatDeleted(chatId));
  }

  @override
  Future<Chat> addComment({
    required String chatId,
    required String messageId,
    required String text,
    String senderName = 'Я',
    String? senderGroup,
    Attachment? attachment,
    ReplyInfo? replyTo,
  }) async {
    Attachment? uploaded = attachment;
    if (attachment != null && !ApiConfig.isServerMediaPath(attachment.path)) {
      uploaded = await _uploadAttachment(attachment);
    }
    final data = await _post('/chats/$chatId/messages/$messageId/comments', {
      'text': text,
      if (uploaded != null) 'attachment': uploaded.toJson(),
      if (replyTo != null) 'replyTo': replyTo.toJson(),
    });
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> editComment({
    required String chatId,
    required String messageId,
    required String commentId,
    required String newText,
  }) async {
    final data = await _put(
      '/chats/$chatId/messages/$messageId/comments/$commentId',
      {'text': newText},
    );
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> deleteComments({
    required String chatId,
    required String messageId,
    required List<String> commentIds,
  }) async {
    final data = await _delete(
      '/chats/$chatId/messages/$messageId/comments',
      {'ids': commentIds},
    );
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<List<Chat>> searchChats(String query) async {
    final r = await http.get(
      Uri.parse('$_base/chats/search?q=${Uri.encodeQueryComponent(query)}'),
      headers: _headers,
    ).timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) return [];
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((j) => _chatFromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<SearchMessageResult>> searchMessages(String query) async {
    final r = await http.get(
      Uri.parse('$_base/messages/search?q=${Uri.encodeQueryComponent(query)}'),
      headers: _headers,
    ).timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) return [];
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((j) {
      final item = j as Map<String, dynamic>;
      return SearchMessageResult(
        chat: _chatFromJson(item['chat'] as Map<String, dynamic>),
        message: Message.fromJson(item['message'] as Map<String, dynamic>, currentUserId: _uid),
      );
    }).toList();
  }

  @override
  Future<List<SearchFileResult>> searchFiles({
    AttachmentType? type,
    String? nameQuery,
  }) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type.name;
    if (nameQuery != null && nameQuery.isNotEmpty) params['q'] = nameQuery;
    final uri = Uri.parse('$_base/files/search').replace(queryParameters: params);
    final r = await http.get(uri, headers: _headers).timeout(ApiConfig.httpTimeout);
    if (r.statusCode != 200) return [];
    final list = jsonDecode(r.body) as List<dynamic>;
    return list.map((j) {
      final item = j as Map<String, dynamic>;
      return SearchFileResult(
        chat: _chatFromJson(item['chat'] as Map<String, dynamic>),
        message: Message.fromJson(item['message'] as Map<String, dynamic>, currentUserId: _uid),
        attachment: Attachment.fromJson(item['attachment'] as Map<String, dynamic>),
      );
    }).toList();
  }

  @override
  Future<Chat> pinMessage({
    required String chatId,
    required String messageId,
  }) async {
    final data = await _post('/chats/$chatId/messages/$messageId/pin', {});
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> unpinMessage({
    required String chatId,
    required String messageId,
  }) async {
    final data = await _delete('/chats/$chatId/messages/$messageId/pin');
    return _chatFromJsonDecrypted(data);
  }

  // ── Опросы ────────────────────────────────────────────────────────────────

  @override
  Future<Chat> sendPoll({
    required String chatId,
    required String question,
    required List<String> options,
    PollType type = PollType.single,
    bool isAnonymous = false,
    bool canChangeVote = false,
    DateTime? deadline,
  }) async {
    final data = await _post('/chats/$chatId/polls', {
      'question': question,
      'options': options,
      'type': type.name,
      'isAnonymous': isAnonymous,
      'canChangeVote': canChangeVote,
      if (deadline != null) 'deadline': deadline.toIso8601String(),
    });
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> votePoll({
    required String chatId,
    required String messageId,
    required List<String> optionIds,
    required String userId,
  }) async {
    final data = await _post('/chats/$chatId/polls/$messageId/vote', {
      'optionIds': optionIds,
    });
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<Chat> closePoll({
    required String chatId,
    required String messageId,
  }) async {
    final data = await _post('/chats/$chatId/polls/$messageId/close', {});
    return _chatFromJsonDecrypted(data);
  }

  @override
  Future<void> markRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final hub = _hub;
    // Hub может быть ещё не подключён (или переподключается); в этом случае
    // молча пропускаем — сервер всё равно не сможет принять вызов. При
    // следующем входе в чат markRead будет вызван снова.
    if (hub == null || hub.state != HubConnectionState.Connected) return;
    try {
      await hub.invoke('MarkRead', args: [chatId, messageIds]);
    } catch (_) {
      // Не даём ошибкам хаба всплыть в UI — это фоновая операция.
    }
  }

  /// Подтверждает получение сообщений (sent → delivered).
  /// Вызывается автоматически при обработке message_received.
  void _markDelivered(String chatId, String messageId) {
    final hub = _hub;
    if (hub == null || hub.state != HubConnectionState.Connected) return;
    hub.invoke('MarkDelivered', args: [chatId, [messageId]]).catchError((_) => null);
  }

  @override
  Future<void> addMember({required String chatId, required String userId}) async {
    await _post('/chats/$chatId/members', {'userId': userId});
  }

  @override
  Future<Chat> joinChat(String chatId) async {
    final data = await _post('/chats/$chatId/join', {});
    return _chatFromJsonDecrypted(data as Map<String, dynamic>);
  }

  @override
  Future<String?> getInviteLink(String chatId) async {
    try {
      final data = await _get('/chats/$chatId/invite-link');
      return data['link'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<ChatEvent> get events => _eventController.stream;

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    EncryptionService.instance.reset();
    await _hub?.stop();
    await _eventController.close();
  }
}

/// Ошибка при работе с API сервера.
class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
