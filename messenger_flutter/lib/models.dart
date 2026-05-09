// ─── Models ───────────────────────────────────────────────────────────────────

/// Различает личные, групповые и широковещательные (сообщества) чаты.
enum ChatType { direct, group, community }

/// Категории вложений файлов для рендеринга и обработки MIME.
enum AttachmentType { image, video, document, audio }

/// Статус доставки сообщения (отображается только у своих сообщений)
enum MessageStatus {
  sending,   // ⏱ отправляется
  sent,      // ✓  отправлено
  delivered, // ✓✓ доставлено (серые)
  read,      // ✓✓ прочитано (голубые)
  error,     // ✗  ошибка
}

/// Файл, прикреплённый к [Message] (изображение, видео или документ).
class Attachment {
  final String path;
  final AttachmentType type;
  final String fileName;
  final int? fileSize;

  /// Серверный путь к JPEG-превью (только для видео).
  /// Генерируется бэкендом при загрузке видео через FFmpeg.
  /// Null у старых сообщений и у локальных файлов до отправки.
  final String? thumbnailPath;

  /// Длительность видео в миллисекундах.
  /// Заполняется бэкендом вместе с [thumbnailPath].
  final int? durationMs;

  const Attachment({
    required this.path,
    required this.type,
    required this.fileName,
    this.fileSize,
    this.thumbnailPath,
    this.durationMs,
  });

  /// Читаемый размер файла: байты → КБ → МБ.
  String get readableSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize Б';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} КБ';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  /// Длительность как [Duration] (null если неизвестна).
  Duration? get duration =>
      durationMs != null ? Duration(milliseconds: durationMs!) : null;

  Map<String, dynamic> toJson() => {
    'path': path,
    'type': type.name,
    'fileName': fileName,
    if (fileSize != null) 'fileSize': fileSize,
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
    if (durationMs != null) 'durationMs': durationMs,
  };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    path: j['path'] as String,
    type: AttachmentType.values.byName(j['type'] as String),
    fileName: j['fileName'] as String,
    fileSize: (j['fileSize'] as num?)?.toInt(),
    // Принимаем оба варианта ключа (camelCase и snake_case) на случай
    // разных версий бэкенда или автогенерированной сериализации.
    thumbnailPath: (j['thumbnailPath'] ?? j['thumbnail_path']) as String?,
    durationMs: ((j['durationMs'] ?? j['duration_ms']) as num?)?.toInt(),
  );
}

/// Контакт, отображаемый в выборщике контактов (реестр приложения, не книга устройства).
class AppContact {
  final String name;
  final String? group;
  final String? phone;
  /// true — преподаватель (отображается в «Академический»), false — студент (в «Общение»).
  final bool isTeacher;

  const AppContact({required this.name, this.group, this.phone, this.isTeacher = false});

  Map<String, dynamic> toJson() => {
    'name': name,
    if (group != null) 'group': group,
    if (phone != null) 'phone': phone,
    'isTeacher': isTeacher,
  };

  factory AppContact.fromJson(Map<String, dynamic> j) => AppContact(
    name: j['name'] as String,
    group: j['group'] as String?,
    phone: j['phone'] as String?,
    isTeacher: j['isTeacher'] as bool? ?? false,
  );
}

/// Упоминание пользователя в тексте сообщения (@mention).
/// [userId] == 'all' для @all / @everyone.
class Mention {
  final String userId;
  final String username;
  /// Позиция начала токена (включая @) в строке текста сообщения.
  final int offset;
  /// Длина токена (включая @).
  final int length;

  const Mention({
    required this.userId,
    required this.username,
    required this.offset,
    required this.length,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'offset': offset,
    'length': length,
  };

  factory Mention.fromJson(Map<String, dynamic> j) => Mention(
    userId: j['userId'] as String,
    username: j['username'] as String,
    offset: (j['offset'] as num).toInt(),
    length: (j['length'] as num).toInt(),
  );
}

// ── Опросы ────────────────────────────────────────────────────────────────────

/// Одиночный (radio) или множественный (checkbox) выбор в опросе.
enum PollType { single, multiple }

/// Вариант ответа в опросе.
class PollOption {
  final String id;
  final String text;
  final int votes;

  const PollOption({required this.id, required this.text, this.votes = 0});

  PollOption copyWith({int? votes}) =>
      PollOption(id: id, text: text, votes: votes ?? this.votes);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'votes': votes};

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
    id: j['id'] as String,
    text: j['text'] as String,
    votes: (j['votes'] as num?)?.toInt() ?? 0,
  );
}

/// Опрос, прикреплённый к сообщению.
class Poll {
  static int _nextId = 0;

  final String id;
  final String question;
  final List<PollOption> options;
  final PollType type;
  final bool isAnonymous;
  final bool canChangeVote;
  final DateTime? deadline;
  final bool isClosed;
  /// Варианты, выбранные текущим пользователем.
  final List<String> myVotes;
  /// userId → список optionId (заполнен только у публичных опросов).
  final Map<String, List<String>> userVotes;

  Poll({
    String? id,
    required this.question,
    required this.options,
    this.type = PollType.single,
    this.isAnonymous = false,
    this.canChangeVote = false,
    this.deadline,
    this.isClosed = false,
    this.myVotes = const [],
    this.userVotes = const {},
  }) : id = id ?? 'poll_${++_nextId}';

  int get totalVotes => options.fold(0, (s, o) => s + o.votes);
  bool get isExpired => deadline != null && DateTime.now().isAfter(deadline!);
  bool get isActive => !isClosed && !isExpired;

  /// Доля голосов за вариант (0.0 – 1.0).
  double optionPercent(String optionId) {
    final total = totalVotes;
    if (total == 0) return 0.0;
    final opt = options.where((o) => o.id == optionId).firstOrNull;
    return (opt?.votes ?? 0) / total;
  }

  Poll copyWith({
    List<PollOption>? options,
    bool? isClosed,
    List<String>? myVotes,
    Map<String, List<String>>? userVotes,
  }) => Poll(
    id: id,
    question: question,
    options: options ?? this.options,
    type: type,
    isAnonymous: isAnonymous,
    canChangeVote: canChangeVote,
    deadline: deadline,
    isClosed: isClosed ?? this.isClosed,
    myVotes: myVotes ?? this.myVotes,
    userVotes: userVotes ?? Map.from(this.userVotes),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'options': options.map((o) => o.toJson()).toList(),
    'type': type.name,
    'isAnonymous': isAnonymous,
    'canChangeVote': canChangeVote,
    if (deadline != null) 'deadline': deadline!.toIso8601String(),
    'isClosed': isClosed,
    if (myVotes.isNotEmpty) 'myVotes': myVotes,
  };

  factory Poll.fromJson(Map<String, dynamic> j, {required String currentUserId}) {
    final rawUV = (j['userVotes'] as Map<String, dynamic>?) ?? {};
    final userVotes = rawUV.map(
      (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()),
    );
    final myVotes = (j['myVotes'] as List<dynamic>?)?.cast<String>() ??
        userVotes[currentUserId] ??
        const <String>[];
    return Poll(
      id: j['id'] as String,
      question: j['question'] as String,
      options: (j['options'] as List<dynamic>)
          .map((o) => PollOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      type: PollType.values.byName(j['type'] as String? ?? 'single'),
      isAnonymous: j['isAnonymous'] as bool? ?? false,
      canChangeVote: j['canChangeVote'] as bool? ?? false,
      deadline: j['deadline'] != null
          ? DateTime.parse(j['deadline'] as String)
          : null,
      isClosed: j['isClosed'] as bool? ?? false,
      myVotes: myVotes,
      userVotes: userVotes,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Отдельное сообщение чата с необязательным вложением и статусом доставки.
class Message {
  // Автоинкрементный резервный идентификатор, используемый когда явный id не задан.
  static int _nextId = 0;

  final String id;
  final String text;
  final bool isMe;
  final DateTime time;
  final String? senderName;
  /// Учебная группа отправителя (для студентов).
  final String? senderGroup;
  /// Путь/URL к аватару отправителя (чтобы показать его рядом с пузырём).
  final String? senderAvatarPath;
  final Attachment? attachment;
  /// Медиаальбом — несколько фото/видео в одном сообщении (Telegram-style).
  /// Если задано — [attachment] игнорируется при рендеринге.
  final List<Attachment>? attachments;
  final bool isEdited;
  final MessageStatus status;
  final List<Comment> comments;
  /// Ответ на сообщение (Telegram-style reply).
  final ReplyInfo? replyTo;
  /// Упоминания пользователей (@mention) в тексте сообщения.
  final List<Mention> mentions;
  /// Опрос, прикреплённый к этому сообщению (null если не опрос).
  final Poll? poll;

  Message({
    String? id,
    required this.text,
    required this.isMe,
    required this.time,
    this.senderName,
    this.senderGroup,
    this.senderAvatarPath,
    this.attachment,
    this.attachments,
    this.isEdited = false,
    this.status = MessageStatus.sent,
    this.comments = const [],
    this.replyTo,
    this.mentions = const [],
    this.poll,
  }) : id = id ?? 'msg_${++_nextId}';

  Message copyWith({
    String? text,
    bool? isEdited,
    MessageStatus? status,
    List<Comment>? comments,
    ReplyInfo? replyTo,
    bool clearReply = false,
    List<Mention>? mentions,
    Poll? poll,
    bool clearPoll = false,
  }) => Message(
    id: id,
    text: text ?? this.text,
    isMe: isMe,
    time: time,
    senderName: senderName,
    senderGroup: senderGroup,
    senderAvatarPath: senderAvatarPath,
    attachment: attachment,
    attachments: attachments,
    isEdited: isEdited ?? this.isEdited,
    status: status ?? this.status,
    comments: comments ?? this.comments,
    replyTo: clearReply ? null : (replyTo ?? this.replyTo),
    mentions: mentions ?? this.mentions,
    poll: clearPoll ? null : (poll ?? this.poll),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isMe': isMe,
    'time': time.toIso8601String(),
    if (senderName != null) 'senderName': senderName,
    if (senderGroup != null) 'senderGroup': senderGroup,
    if (senderAvatarPath != null) 'senderAvatarPath': senderAvatarPath,
    if (attachment != null) 'attachment': attachment!.toJson(),
    if (attachments != null && attachments!.isNotEmpty)
      'attachments': attachments!.map((a) => a.toJson()).toList(),
    'isEdited': isEdited,
    'status': status.name,
    if (comments.isNotEmpty) 'comments': comments.map((c) => c.toJson()).toList(),
    if (replyTo != null) 'replyTo': replyTo!.toJson(),
    if (mentions.isNotEmpty) 'mentions': mentions.map((m) => m.toJson()).toList(),
    if (poll != null) 'poll': poll!.toJson(),
  };

  factory Message.fromJson(Map<String, dynamic> j, {required String currentUserId}) => Message(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    isMe: (j['senderId'] as String?) == currentUserId || (j['isMe'] as bool? ?? false),
    time: DateTime.parse(j['time'] as String),
    senderName: j['senderName'] as String?,
    senderGroup: j['senderGroup'] as String?,
    senderAvatarPath: j['senderAvatarPath'] as String?,
    attachment: j['attachment'] != null
        ? Attachment.fromJson(j['attachment'] as Map<String, dynamic>)
        : null,
    attachments: (j['attachments'] as List<dynamic>?)
        ?.map((a) => Attachment.fromJson(a as Map<String, dynamic>))
        .toList(),
    isEdited: j['isEdited'] as bool? ?? false,
    status: MessageStatus.values.byName(j['status'] as String? ?? 'sent'),
    comments: (j['comments'] as List<dynamic>?)
        ?.map((c) => Comment.fromJson(c as Map<String, dynamic>, currentUserId: currentUserId))
        .toList() ?? const [],
    replyTo: j['replyTo'] != null
        ? ReplyInfo.fromJson(j['replyTo'] as Map<String, dynamic>)
        : null,
    mentions: (j['mentions'] as List<dynamic>?)
        ?.map((m) => Mention.fromJson(m as Map<String, dynamic>))
        .toList() ?? const [],
    poll: j['poll'] != null
        ? Poll.fromJson(j['poll'] as Map<String, dynamic>, currentUserId: currentUserId)
        : null,
  );
}

/// Комментарий к сообщению (посту) — аналог тредов в Telegram-каналах.
class Comment {
  static int _nextId = 0;

  final String id;
  final String text;
  final String senderName;
  /// Учебная группа отправителя (для студентов).
  final String? senderGroup;
  final DateTime time;
  final bool isMe;
  final bool isEdited;
  final ReplyInfo? replyTo;
  final Attachment? attachment;

  Comment({
    String? id,
    required this.text,
    required this.senderName,
    this.senderGroup,
    required this.time,
    this.isMe = false,
    this.isEdited = false,
    this.replyTo,
    this.attachment,
  }) : id = id ?? 'cmt_${++_nextId}';

  Comment copyWith({
    String? text,
    bool? isEdited,
    ReplyInfo? replyTo,
    bool clearReply = false,
    Attachment? attachment,
    bool clearAttachment = false,
  }) {
    return Comment(
      id: id,
      text: text ?? this.text,
      senderName: senderName,
      senderGroup: senderGroup,
      time: time,
      isMe: isMe,
      isEdited: isEdited ?? this.isEdited,
      replyTo: clearReply ? null : (replyTo ?? this.replyTo),
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'senderName': senderName,
    if (senderGroup != null) 'senderGroup': senderGroup,
    'time': time.toIso8601String(),
    'isMe': isMe,
    'isEdited': isEdited,
    if (replyTo != null) 'replyTo': replyTo!.toJson(),
    if (attachment != null) 'attachment': attachment!.toJson(),
  };

  factory Comment.fromJson(Map<String, dynamic> j, {required String currentUserId}) => Comment(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    senderName: j['senderName'] as String? ?? '',
    senderGroup: j['senderGroup'] as String?,
    time: DateTime.parse(j['time'] as String),
    isMe: (j['senderId'] as String?) == currentUserId || (j['isMe'] as bool? ?? false),
    isEdited: j['isEdited'] as bool? ?? false,
    replyTo: j['replyTo'] != null
        ? ReplyInfo.fromJson(j['replyTo'] as Map<String, dynamic>)
        : null,
    attachment: j['attachment'] != null
        ? Attachment.fromJson(j['attachment'] as Map<String, dynamic>)
        : null,
  );
}

/// Информация об ответе на сообщение (reply).
class ReplyInfo {
  final String messageId;
  final String senderName;
  final String text;

  const ReplyInfo({
    required this.messageId,
    required this.senderName,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'senderName': senderName,
    'text': text,
  };

  factory ReplyInfo.fromJson(Map<String, dynamic> j) => ReplyInfo(
    messageId: j['messageId'] as String,
    senderName: j['senderName'] as String? ?? '',
    text: j['text'] as String? ?? '',
  );
}

/// Уровень привилегий участника в групповом чате или сообществе.
enum MemberRole { creator, admin, member }

/// Участник [Chat] с назначенной ролью [MemberRole].
class ChatMember {
  /// Серверный идентификатор пользователя (UUID).
  /// Используется в метаданных @упоминаний, отправляемых на сервер.
  /// Может отсутствовать для виртуальных/локальных участников.
  final String? userId;
  final String name;
  /// Учебная группа участника (для студентов).
  final String? group;
  final MemberRole role;

  const ChatMember({
    this.userId,
    required this.name,
    this.group,
    this.role = MemberRole.member,
  });

  ChatMember copyWith({
    String? userId,
    String? name,
    String? group,
    MemberRole? role,
  }) => ChatMember(
    userId: userId ?? this.userId,
    name: name ?? this.name,
    group: group ?? this.group,
    role: role ?? this.role,
  );

  Map<String, dynamic> toJson() => {
    if (userId != null) 'userId': userId,
    'name': name,
    if (group != null) 'group': group,
    'role': role.name,
  };

  factory ChatMember.fromJson(Map<String, dynamic> j) => ChatMember(
    // Сервер может присылать userId или id — пробуем оба ключа.
    userId: j['userId'] as String? ?? j['id'] as String?,
    name: j['name'] as String,
    group: j['group'] as String?,
    role: MemberRole.values.byName(j['role'] as String? ?? 'member'),
  );
}

/// Основная сущность чата, содержащая сообщения, участников и метаданные.
class Chat {
  // Автоинкрементный резервный идентификатор, используемый когда явный id не задан.
  static int _nextId = 0;

  final String id;
  final String name;
  final List<Message> messages;
  final ChatType type;
  final List<ChatMember> members;
  final String? adminName;
  final String? avatarPath;
  final String? description;
  final DateTime? createdAt;
  /// Флаг: чат принадлежит академическому разделу (преподаватели)
  final bool isAcademic;
  /// Идентификаторы закреплённых сообщений (в порядке закрепления, макс. 5).
  final List<String> pinnedMessageIds;
  /// Количество непрочитанных сообщений (приходит с сервера).
  final int unreadCount;

  Chat({
    String? id,
    required this.name,
    required this.messages,
    this.type = ChatType.direct,
    this.members = const [],
    this.adminName,
    this.avatarPath,
    this.description,
    this.createdAt,
    this.isAcademic = false,
    this.pinnedMessageIds = const [],
    this.unreadCount = 0,
  }) : id = id ?? 'chat_${++_nextId}';

  String get lastMessage {
    if (messages.isEmpty) return '';
    final msg = messages.last;
    String content = msg.text;
    if (content.isEmpty) {
      if (msg.poll != null) {
        content = '📊 ${msg.poll!.question}';
      } else if (msg.attachment != null) {
        content = switch (msg.attachment!.type) {
          AttachmentType.image    => '📷 Фото',
          AttachmentType.video    => '🎬 Видео',
          AttachmentType.document => '📎 ${msg.attachment!.fileName}',
          AttachmentType.audio    => '🎤 Голосовое сообщение',
        };
      }
    }
    if (type != ChatType.direct && msg.senderName != null && !msg.isMe) {
      final prefix = msg.senderGroup != null
          ? '${msg.senderGroup} ${msg.senderName}'
          : msg.senderName!;
      return '$prefix: $content';
    }
    return content;
  }

  DateTime get lastTime =>
      messages.isNotEmpty ? messages.last.time : DateTime(0);

  /// Чаты-сообщества доступны только для чтения, если текущий пользователь не является
  /// создателем или администратором. Для определения роли нужно имя текущего пользователя —
  /// используй [canWriteAs].
  bool get canWrite => type != ChatType.community;

  /// Возвращает true, если пользователь с именем [userName] может писать в этот чат.
  /// В сообществах — только создатель и администраторы.
  bool canWriteAs(String? userName) {
    if (type != ChatType.community) return true;
    return isCreatorOrAdmin(userName);
  }

  /// Возвращает true, если [userName] является создателем или администратором в этом чате.
  bool isCreatorOrAdmin(String? userName) {
    if (userName == null || userName.isEmpty) return false;
    // Сначала проверяем поле adminName
    if (adminName == userName) return true;
    // Затем — список участников (роль creator или admin)
    return members.any((m) =>
        m.name == userName &&
        (m.role == MemberRole.creator || m.role == MemberRole.admin));
  }

  // Сигнальное значение для определения «не передано» у nullable-полей в copyWith
  static const _keep = Object();

  Chat copyWith({
    String? name,
    List<Message>? messages,
    ChatType? type,
    List<ChatMember>? members,
    Object? adminName = _keep,
    Object? avatarPath = _keep,
    Object? description = _keep,
    DateTime? createdAt,
    bool? isAcademic,
    List<String>? pinnedMessageIds,
    int? unreadCount,
  }) {
    return Chat(
      id: id,
      name: name ?? this.name,
      messages: messages ?? this.messages,
      type: type ?? this.type,
      members: members ?? this.members,
      adminName: identical(adminName, _keep) ? this.adminName : adminName as String?,
      avatarPath: identical(avatarPath, _keep) ? this.avatarPath : avatarPath as String?,
      description: identical(description, _keep) ? this.description : description as String?,
      createdAt: createdAt ?? this.createdAt,
      isAcademic: isAcademic ?? this.isAcademic,
      pinnedMessageIds: pinnedMessageIds ?? this.pinnedMessageIds,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'messages': messages.map((m) => m.toJson()).toList(),
    'members': members.map((m) => m.toJson()).toList(),
    if (adminName != null) 'adminName': adminName,
    if (avatarPath != null) 'avatarPath': avatarPath,
    if (description != null) 'description': description,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    'isAcademic': isAcademic,
    if (pinnedMessageIds.isNotEmpty) 'pinnedMessageIds': pinnedMessageIds,
    if (unreadCount > 0) 'unreadCount': unreadCount,
  };

  factory Chat.fromJson(Map<String, dynamic> j, {required String currentUserId}) {
    // Сортируем сообщения по времени (по возрастанию) — сервер иногда возвращает
    // их в обратном порядке (последние 20 для превью списка чатов), а клиент
    // ожидает старые→новые: .last должен быть самым свежим.
    final msgs = (j['messages'] as List<dynamic>?)
        ?.map((m) => Message.fromJson(m as Map<String, dynamic>, currentUserId: currentUserId))
        .toList() ?? [];
    msgs.sort((a, b) => a.time.compareTo(b.time));
    return Chat(
      id: j['id'] as String,
      name: j['name'] as String,
      type: ChatType.values.byName(j['type'] as String? ?? 'direct'),
      messages: msgs,
      members: (j['members'] as List<dynamic>?)
          ?.map((m) => ChatMember.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
      adminName: j['adminName'] as String?,
      avatarPath: j['avatarPath'] as String?,
      description: j['description'] as String?,
      createdAt: j['createdAt'] != null ? DateTime.parse(j['createdAt'] as String) : null,
      isAcademic: j['isAcademic'] as bool? ?? false,
      pinnedMessageIds: (j['pinnedMessageIds'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─── Управление устройствами ──────────────────────────────────────────────────

/// Активный сеанс пользователя на конкретном устройстве.
class DeviceSession {
  final String sessionId;

  /// Читаемое имя устройства, напр. «iPhone 14 Pro» или «Chrome · Windows 11».
  final String deviceName;

  /// Платформа: "ios" | "android" | "web" | "windows" | "macos" | "linux".
  final String? platform;

  /// Географическое местоположение, напр. «Баку, Азербайджан».
  final String? location;

  /// Время последней активности сеанса.
  final DateTime lastActivity;

  /// true — это сеанс текущего устройства.
  final bool isCurrent;

  const DeviceSession({
    required this.sessionId,
    required this.deviceName,
    this.platform,
    this.location,
    required this.lastActivity,
    this.isCurrent = false,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'deviceName': deviceName,
    if (platform != null) 'platform': platform,
    if (location != null) 'location': location,
    'lastActivity': lastActivity.toIso8601String(),
    'isCurrent': isCurrent,
  };

  factory DeviceSession.fromJson(Map<String, dynamic> j) => DeviceSession(
    sessionId: j['sessionId'] as String,
    deviceName: j['deviceName'] as String,
    platform: j['platform'] as String?,
    location: j['location'] as String?,
    lastActivity: DateTime.parse(j['lastActivity'] as String),
    isCurrent: j['isCurrent'] as bool? ?? false,
  );
}
