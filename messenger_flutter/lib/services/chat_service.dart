import 'dart:async';
import '../models.dart';

// ── События (sealed) ────────────────────────────────────────────────────────
sealed class ChatEvent {}

/// Вызывается при получении нового сообщения (отправленного локально или удалённо).
class MessageReceived extends ChatEvent {
  final String chatId;
  final Message message;
  MessageReceived(this.chatId, this.message);
}

class MessageEdited extends ChatEvent {
  final String chatId;
  final String messageId;
  final String newText;
  MessageEdited(this.chatId, this.messageId, this.newText);
}

class MessageDeleted extends ChatEvent {
  final String chatId;
  final List<String> messageIds;
  MessageDeleted(this.chatId, this.messageIds);
}

/// Изменился статус доставки сообщения (sent/delivered/read) — обычно прилетает
/// отправителю, когда получатель открыл чат и прочитал сообщения.
class MessageStatusChanged extends ChatEvent {
  final String chatId;
  final String messageId;
  final MessageStatus status;
  MessageStatusChanged(this.chatId, this.messageId, this.status);
}

class ChatUpdated extends ChatEvent {
  final Chat chat;
  ChatUpdated(this.chat);
}

class ChatDeleted extends ChatEvent {
  final String chatId;
  ChatDeleted(this.chatId);
}

/// Сообщение закреплено (локально или удалённо).
class MessagePinned extends ChatEvent {
  final String chatId;
  final String messageId;
  MessagePinned(this.chatId, this.messageId);
}

/// Сообщение откреплено (локально или удалённо).
class MessageUnpinned extends ChatEvent {
  final String chatId;
  final String messageId;
  MessageUnpinned(this.chatId, this.messageId);
}

/// Пользователь проголосовал в опросе.
class PollVoted extends ChatEvent {
  final String chatId;
  final String messageId;
  final String userId;
  final List<String> optionIds;
  PollVoted(this.chatId, this.messageId, this.userId, this.optionIds);
}

/// Опрос завершён (вручную или по дедлайну).
class PollClosed extends ChatEvent {
  final String chatId;
  final String messageId;
  PollClosed(this.chatId, this.messageId);
}

/// Сеанс пользователя был завершён удалённо (другим устройством, администратором,
/// или истёк 30-дневный срок бездействия).
/// Если [isCurrent] == true — текущий клиент обязан разлогиниться.
class SessionTerminated extends ChatEvent {
  final String sessionId;
  final bool isCurrent;
  SessionTerminated(this.sessionId, {this.isCurrent = false});
}

/// SignalR успешно подключился (в том числе после разрыва связи с сервером).
/// UI должен перезагрузить список чатов, чтобы не пропустить изменения
/// за время отсутствия подключения.
class ConnectionRestored extends ChatEvent {}

/// Административное уведомление, пришедшее по SignalR.
class AdminNotificationReceived extends ChatEvent {
  final int id;
  final String title;
  final String body;
  final DateTime sentAt;
  AdminNotificationReceived({
    required this.id,
    required this.title,
    required this.body,
    required this.sentAt,
  });
}

// ── Абстрактный интерфейс ─────────────────────────────────────────────────────

/// Контракт для всех бэкендов чата (локальный, удалённый, mock).
/// Экраны зависят от этого интерфейса, а не от конкретной реализации.
/// Модель административного уведомления (для отображения в панели).
class AdminNotification {
  final int id;
  final String title;
  final String body;
  final String target;
  final DateTime sentAt;

  const AdminNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    required this.sentAt,
  });

  factory AdminNotification.fromJson(Map<String, dynamic> j) => AdminNotification(
    id:     (j['id'] as num).toInt(),
    title:  j['title'] as String? ?? '',
    body:   j['body']  as String? ?? '',
    target: j['target'] as String? ?? 'all',
    sentAt: DateTime.tryParse(j['sentAt'] as String? ?? '') ?? DateTime.now(),
  );
}

abstract class ChatService {
  /// Максимальное количество закреплённых сообщений в чате.
  static const int maxPinnedMessages = 5;
  Future<List<Chat>> loadChats();

  /// Загружает историю административных уведомлений для текущего пользователя.
  Future<List<AdminNotification>> loadAdminNotifications();

  /// Максимальное количество упоминаний в одном сообщении (защита от спама).
  static const int maxMentionsPerMessage = 10;

  Future<Chat> sendMessage({
    required String chatId,
    required String text,
    Attachment? attachment,
    /// Медиаальбом — несколько файлов в одном сообщении. Если задано,
    /// [attachment] игнорируется.
    List<Attachment>? attachments,
    String senderName,
    String? senderGroup,
    ReplyInfo? replyTo,
    List<Mention> mentions,
    bool postAsCommunity,
  });

  Future<Chat> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  });

  Future<Chat> deleteMessages({
    required String chatId,
    required List<String> messageIds,
  });

  Future<Chat> forwardMessages({
    required String targetChatId,
    required List<Message> messages,
  });

  Future<Chat> createDirectChat({required String contactName, bool isAcademic = false});

  Future<Chat> createGroupOrCommunity({
    required String name,
    required ChatType type,
    required List<ChatMember> members,
    String? adminName,
    bool isAcademic = false,
    String? description,
  });

  Future<Chat> updateChatSettings(Chat chat);

  /// Удаляет чат полностью. Эмитит [ChatDeleted] для подписчиков.
  Future<void> deleteChat(String chatId);

  /// Добавляет комментарий к сообщению (посту) в группе/сообществе.
  Future<Chat> addComment({
    required String chatId,
    required String messageId,
    required String text,
    String senderName = 'Я',
    String? senderGroup,
    Attachment? attachment,
    ReplyInfo? replyTo,
  });

  /// Редактирует текст комментария.
  Future<Chat> editComment({
    required String chatId,
    required String messageId,
    required String commentId,
    required String newText,
  });

  /// Удаляет комментарии по id.
  Future<Chat> deleteComments({
    required String chatId,
    required String messageId,
    required List<String> commentIds,
  });

  /// Поиск чатов/групп по имени.
  Future<List<Chat>> searchChats(String query);

  /// Поиск сообщений по тексту. Возвращает пары (чат, сообщение).
  Future<List<SearchMessageResult>> searchMessages(String query);

  /// Поиск вложений по типу файла и (опционально) имени.
  Future<List<SearchFileResult>> searchFiles({
    AttachmentType? type,
    String? nameQuery,
  });

  /// Закрепляет сообщение в чате. Выбрасывает [StateError], если достигнут лимит.
  Future<Chat> pinMessage({
    required String chatId,
    required String messageId,
  });

  /// Открепляет ранее закреплённое сообщение.
  Future<Chat> unpinMessage({
    required String chatId,
    required String messageId,
  });

  // ── Опросы ────────────────────────────────────────────────────────────────

  /// Создаёт новое сообщение-опрос в чате.
  Future<Chat> sendPoll({
    required String chatId,
    required String question,
    required List<String> options,
    PollType type = PollType.single,
    bool isAnonymous = false,
    bool canChangeVote = false,
    DateTime? deadline,
  });

  /// Голосует в опросе. [optionIds] может содержать несколько id при множественном выборе.
  Future<Chat> votePoll({
    required String chatId,
    required String messageId,
    required List<String> optionIds,
    required String userId,
  });

  /// Закрывает опрос вручную (только создатель или администратор).
  Future<Chat> closePoll({
    required String chatId,
    required String messageId,
  });

  /// Помечает сообщения прочитанными на сервере. Сервер рассылает
  /// [MessageStatusChanged] отправителям этих сообщений — чтобы галочки
  /// стали голубыми в реальном времени.
  Future<void> markRead({
    required String chatId,
    required List<String> messageIds,
  });

  /// Добавляет пользователя в группу/сообщество по его userId или username.
  Future<void> addMember({required String chatId, required String userId});

  /// Вступает в группу/сообщество (текущий пользователь добавляет себя).
  /// Используется при принятии приглашения.
  Future<Chat> joinChat(String chatId);

  /// Возвращает пригласительную ссылку на группу/сообщество.
  /// Может вернуть null если сервер не поддерживает эту функцию.
  Future<String?> getInviteLink(String chatId);

  Stream<ChatEvent> get events;

  Future<void> dispose();
}

/// Результат поиска сообщения — чат + конкретное сообщение.
class SearchMessageResult {
  final Chat chat;
  final Message message;
  const SearchMessageResult({required this.chat, required this.message});
}

/// Результат поиска файла — чат + сообщение с вложением.
class SearchFileResult {
  final Chat chat;
  final Message message;
  final Attachment attachment;
  const SearchFileResult({
    required this.chat,
    required this.message,
    required this.attachment,
  });
}

// ── Локальная (in-memory) реализация ──────────────────────────────────────────
class LocalChatService implements ChatService {
  final List<Chat> _chats;
  final _controller = StreamController<ChatEvent>.broadcast();

  LocalChatService() : _chats = _seedChats();

  static List<Chat> _seedChats() => [
    // ── Обычные чаты (раздел «Общение») ──────────────────────────
    Chat(
      name: 'Алексей',
      type: ChatType.direct,
      messages: [
        Message(text: 'Привет!', isMe: false,
            time: DateTime.now().subtract(const Duration(minutes: 5))),
        Message(text: 'Здорово', isMe: true,
            time: DateTime.now().subtract(const Duration(minutes: 4))),
      ],
    ),
    Chat(
      name: 'Мария',
      type: ChatType.direct,
      messages: [
        Message(text: 'Ты где?', isMe: false,
            time: DateTime.now().subtract(const Duration(minutes: 10))),
      ],
    ),
    Chat(
      name: 'Иван',
      type: ChatType.direct,
      messages: [
        Message(text: 'Ок', isMe: false,
            time: DateTime.now().subtract(const Duration(days: 1))),
      ],
    ),
    // ── Академические чаты (раздел «Академический») ──────────────
    Chat(
      name: 'Проф. Иванов А.С.',
      type: ChatType.direct,
      isAcademic: true,
      messages: [
        Message(text: 'Добрый день! Когда можно подойти на консультацию?', isMe: true,
            time: DateTime.now().subtract(const Duration(hours: 2))),
        Message(text: 'Завтра с 14:00 до 16:00, аудитория 305', isMe: false,
            senderName: 'Проф. Иванов А.С.',
            time: DateTime.now().subtract(const Duration(hours: 1))),
      ],
    ),
    Chat(
      name: 'Физика и оптика ФО 22-1',
      type: ChatType.community,
      isAcademic: true,
      adminName: 'Проф. Петров',
      description: 'Учебная группа по физике и оптике',
      messages: [
        Message(text: 'Конспект лекции №14: Введение в квантовую электродинамику', isMe: false,
            senderName: 'Проф. Петров',
            time: DateTime.now().subtract(const Duration(hours: 3))),
      ],
      members: [
        const ChatMember(name: 'Проф. Петров', role: MemberRole.creator),
        const ChatMember(name: 'Студент 1', group: 'ФО-22', role: MemberRole.member),
      ],
    ),
    Chat(
      name: 'История Казахстана ФО 22',
      type: ChatType.community,
      isAcademic: true,
      adminName: 'Доц. Сулейменова',
      description: 'Курс истории Казахстана',
      messages: [
        Message(text: 'Домашнее задание на следующую неделю опубликовано', isMe: false,
            senderName: 'Доц. Сулейменова',
            time: DateTime.now().subtract(const Duration(days: 1))),
      ],
      members: [
        const ChatMember(name: 'Доц. Сулейменова', role: MemberRole.creator),
      ],
    ),
  ];

  /// Возвращает индекс в списке для [chatId] или -1, если не найден.
  int _idx(String chatId) => _chats.indexWhere((c) => c.id == chatId);

  @override
  Future<List<Chat>> loadChats() async => List.unmodifiable(_chats);

  @override
  Future<List<AdminNotification>> loadAdminNotifications() async => [];

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
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msg = Message(
      text: text, isMe: true, time: DateTime.now(),
      senderName: senderName, senderGroup: senderGroup,
      postAsCommunity: postAsCommunity,
      attachment: attachments != null ? null : attachment,
      attachments: attachments,
      replyTo: replyTo,
      mentions: mentions,
      status: MessageStatus.delivered,
    );
    final updated = _chats[i].copyWith(messages: [..._chats[i].messages, msg]);
    _chats[i] = updated;
    _controller.add(MessageReceived(chatId, msg));
    return updated;
  }

  @override
  Future<Chat> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msgs = _chats[i].messages
        .map((m) => m.id == messageId ? m.copyWith(text: newText, isEdited: true) : m)
        .toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(MessageEdited(chatId, messageId, newText));
    return updated;
  }

  @override
  Future<Chat> deleteMessages({
    required String chatId,
    required List<String> messageIds,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final idSet = messageIds.toSet(); // O(1) поиск вместо перебора списка
    final msgs = _chats[i].messages.where((m) => !idSet.contains(m.id)).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(MessageDeleted(chatId, messageIds));
    return updated;
  }

  @override
  Future<Chat> forwardMessages({
    required String targetChatId,
    required List<Message> messages,
  }) async {
    final i = _idx(targetChatId);
    if (i == -1) throw StateError('Chat not found: $targetChatId');
    final forwarded = messages
        .map((m) => Message(text: m.text, isMe: true, time: DateTime.now(),
              senderName: 'Я', attachment: m.attachment))
        .toList();
    final updated = _chats[i].copyWith(
        messages: [..._chats[i].messages, ...forwarded]);
    _chats[i] = updated;
    for (final m in forwarded) { _controller.add(MessageReceived(targetChatId, m)); }
    return updated;
  }

  @override
  Future<Chat> createDirectChat({required String contactName, bool isAcademic = false}) async {
    // Повторно использует существующий чат вместо создания дубликата.
    final existing = _chats.where(
      (c) => c.name == contactName && c.type == ChatType.direct,
    ).firstOrNull;
    if (existing != null) return existing;
    final c = Chat(name: contactName, type: ChatType.direct, messages: [], isAcademic: isAcademic);
    _chats.add(c);
    _controller.add(ChatUpdated(c));
    return c;
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
    final chat = Chat(
      name: name, type: type, members: members,
      adminName: adminName, messages: [],
      isAcademic: isAcademic,
      description: description,
    );
    _chats.add(chat);
    _controller.add(ChatUpdated(chat));
    return chat;
  }

  @override
  Future<Chat> updateChatSettings(Chat chat) async {
    final i = _idx(chat.id);
    if (i == -1) throw StateError('Chat not found: ${chat.id}');
    _chats[i] = chat;
    _controller.add(ChatUpdated(chat));
    return chat;
  }

  @override
  Future<void> deleteChat(String chatId) async {
    final i = _idx(chatId);
    if (i == -1) return;
    _chats.removeAt(i);
    _controller.add(ChatDeleted(chatId));
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
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final comment = Comment(
      text: text,
      senderName: senderName,
      senderGroup: senderGroup,
      time: DateTime.now(),
      isMe: true,
      attachment: attachment,
      replyTo: replyTo,
    );
    final msgs = _chats[i].messages.map((m) {
      if (m.id == messageId) {
        return m.copyWith(comments: [...m.comments, comment]);
      }
      return m;
    }).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(ChatUpdated(updated));
    return updated;
  }

  @override
  Future<Chat> editComment({
    required String chatId,
    required String messageId,
    required String commentId,
    required String newText,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msgs = _chats[i].messages.map((m) {
      if (m.id == messageId) {
        final updatedComments = m.comments.map((c) {
          if (c.id == commentId) return c.copyWith(text: newText, isEdited: true);
          return c;
        }).toList();
        return m.copyWith(comments: updatedComments);
      }
      return m;
    }).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(ChatUpdated(updated));
    return updated;
  }

  @override
  Future<Chat> deleteComments({
    required String chatId,
    required String messageId,
    required List<String> commentIds,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final ids = commentIds.toSet();
    final msgs = _chats[i].messages.map((m) {
      if (m.id == messageId) {
        final filtered = m.comments.where((c) => !ids.contains(c.id)).toList();
        return m.copyWith(comments: filtered);
      }
      return m;
    }).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(ChatUpdated(updated));
    return updated;
  }

  @override
  Future<List<Chat>> searchChats(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    return _chats.where((c) {
      return c.name.toLowerCase().contains(q) ||
          (c.description?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Future<List<SearchMessageResult>> searchMessages(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    final results = <SearchMessageResult>[];
    for (final chat in _chats) {
      for (final msg in chat.messages) {
        if (msg.text.toLowerCase().contains(q)) {
          results.add(SearchMessageResult(chat: chat, message: msg));
        }
      }
    }
    // Сортировка: новые сообщения первыми
    results.sort((a, b) => b.message.time.compareTo(a.message.time));
    return results;
  }

  @override
  Future<List<SearchFileResult>> searchFiles({
    AttachmentType? type,
    String? nameQuery,
  }) async {
    final q = nameQuery?.toLowerCase().trim() ?? '';
    final results = <SearchFileResult>[];
    for (final chat in _chats) {
      for (final msg in chat.messages) {
        final att = msg.attachment;
        if (att == null) continue;
        if (type != null && att.type != type) continue;
        if (q.isNotEmpty && !att.fileName.toLowerCase().contains(q)) continue;
        results.add(SearchFileResult(
          chat: chat, message: msg, attachment: att,
        ));
      }
    }
    results.sort((a, b) => b.message.time.compareTo(a.message.time));
    return results;
  }

  @override
  Future<Chat> pinMessage({
    required String chatId,
    required String messageId,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final chat = _chats[i];
    if (chat.pinnedMessageIds.contains(messageId)) return chat;
    if (chat.pinnedMessageIds.length >= ChatService.maxPinnedMessages) {
      throw StateError(
          'Достигнут лимит закреплённых сообщений (${ChatService.maxPinnedMessages})');
    }
    final updated = chat.copyWith(
        pinnedMessageIds: [...chat.pinnedMessageIds, messageId]);
    _chats[i] = updated;
    _controller.add(MessagePinned(chatId, messageId));
    _controller.add(ChatUpdated(updated));
    return updated;
  }

  @override
  Future<Chat> unpinMessage({
    required String chatId,
    required String messageId,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final chat = _chats[i];
    if (!chat.pinnedMessageIds.contains(messageId)) return chat;
    final updated = chat.copyWith(
        pinnedMessageIds:
            chat.pinnedMessageIds.where((id) => id != messageId).toList());
    _chats[i] = updated;
    _controller.add(MessageUnpinned(chatId, messageId));
    _controller.add(ChatUpdated(updated));
    return updated;
  }

  // ── Счётчик id вариантов опроса ───────────────────────────────────────────
  static int _optionCounter = 0;

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
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final pollOptions = options
        .map((t) => PollOption(id: 'opt_${++_optionCounter}', text: t))
        .toList();
    final poll = Poll(
      question: question,
      options: pollOptions,
      type: type,
      isAnonymous: isAnonymous,
      canChangeVote: canChangeVote,
      deadline: deadline,
    );
    final msg = Message(
      text: '',
      isMe: true,
      time: DateTime.now(),
      poll: poll,
      status: MessageStatus.delivered,
    );
    final updated = _chats[i].copyWith(messages: [..._chats[i].messages, msg]);
    _chats[i] = updated;
    _controller.add(MessageReceived(chatId, msg));
    return updated;
  }

  @override
  Future<Chat> votePoll({
    required String chatId,
    required String messageId,
    required List<String> optionIds,
    required String userId,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msgs = _chats[i].messages.map((m) {
      if (m.id != messageId || m.poll == null) return m;
      final poll = m.poll!;
      if (!poll.isActive) return m;
      // Если повторное голосование запрещено — пропускаем
      if (!poll.canChangeVote && poll.userVotes.containsKey(userId)) return m;
      // Убираем старые голоса пользователя
      final prevVotes = poll.userVotes[userId] ?? const [];
      var opts = poll.options.map((o) {
        int v = o.votes;
        if (prevVotes.contains(o.id)) v = (v - 1).clamp(0, 999999);
        if (optionIds.contains(o.id)) v++;
        return o.copyWith(votes: v);
      }).toList();
      final newUV = Map<String, List<String>>.from(poll.userVotes)
        ..[userId] = optionIds;
      return m.copyWith(
        poll: poll.copyWith(
          options: opts,
          myVotes: optionIds,
          userVotes: newUV,
        ),
      );
    }).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(PollVoted(chatId, messageId, userId, optionIds));
    return updated;
  }

  @override
  Future<Chat> closePoll({
    required String chatId,
    required String messageId,
  }) async {
    final i = _idx(chatId);
    if (i == -1) throw StateError('Chat not found: $chatId');
    final msgs = _chats[i].messages.map((m) {
      if (m.id != messageId || m.poll == null) return m;
      return m.copyWith(poll: m.poll!.copyWith(isClosed: true));
    }).toList();
    final updated = _chats[i].copyWith(messages: msgs);
    _chats[i] = updated;
    _controller.add(PollClosed(chatId, messageId));
    return updated;
  }

  @override
  Future<void> markRead({
    required String chatId,
    required List<String> messageIds,
  }) async {
    // В in-memory режиме нет понятия «прочитано удалённо» — просто обновляем
    // статус локально, чтобы UI выглядел одинаково с серверным сценарием.
    final i = _idx(chatId);
    if (i == -1) return;
    final ids = messageIds.toSet();
    final msgs = _chats[i].messages.map((m) {
      if (m.isMe && ids.contains(m.id)) {
        return m.copyWith(status: MessageStatus.read);
      }
      return m;
    }).toList();
    _chats[i] = _chats[i].copyWith(messages: msgs);
  }

  @override
  Future<void> addMember({required String chatId, required String userId}) async {
    final i = _idx(chatId);
    if (i == -1) return;
    final chat = _chats[i];
    if (chat.members.any((m) => m.name == userId || m.userId == userId)) return;
    final updated = chat.copyWith(
      members: [...chat.members, ChatMember(name: userId, role: MemberRole.member)],
    );
    _chats[i] = updated;
    _controller.add(ChatUpdated(updated));
  }

  @override
  Future<Chat> joinChat(String chatId) async {
    // В локальном режиме: добавляем себя как участника
    final i = _idx(chatId);
    if (i == -1) throw Exception('Chat not found');
    final chat = _chats[i];
    const self = 'me';
    if (!chat.members.any((m) => m.name == self)) {
      final updated = chat.copyWith(
        members: [...chat.members, ChatMember(name: self, role: MemberRole.member)],
      );
      _chats[i] = updated;
      _controller.add(ChatUpdated(updated));
      return updated;
    }
    return chat;
  }

  @override
  Future<String?> getInviteLink(String chatId) async {
    // В локальном режиме возвращаем мок-ссылку
    return 'https://messenger.app/join/$chatId';
  }

  @override
  Stream<ChatEvent> get events => _controller.stream;

  @override
  Future<void> dispose() async => _controller.close();
}
