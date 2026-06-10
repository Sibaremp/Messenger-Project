import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/api_config.dart' show ApiConfig;
import '../services/file_download_service.dart';
import '../services/volume_service.dart';
import 'package:cached_network_image/cached_network_image.dart' hide DownloadProgress;
import 'package:share_plus/share_plus.dart';
import '../profile_screen.dart' show ProfileAvatar;
import '../theme.dart' show CustomChatTheme;
import '../services/audio_service.dart';
import 'audio_message_bubble.dart';
import '../utils/profanity_filter.dart';
import '../utils/app_snack.dart';
import '../services/media_save_service.dart';

// ─── Аватар ───────────────────────────────────────────────────────────────────

/// Круглый аватар чата.
/// Если [avatarPath] задан и изображение загружается — показывает его,
/// иначе — иконку-заглушку по типу чата.
/// При ошибке загрузки сетевого изображения автоматически показывает fallback.
class ChatAvatar extends StatefulWidget {
  final ChatType type;
  final double radius;
  final String? avatarPath;
  /// Имя чата — используется для генерации уникального цвета аватара.
  final String? chatName;

  const ChatAvatar({
    super.key,
    this.type = ChatType.direct,
    this.radius = AppSizes.avatarRadiusLarge,
    this.avatarPath,
    this.chatName,
  });

  static const _avatarColors = [
    Color(0xFFE57373), Color(0xFF81C784), Color(0xFF64B5F6), Color(0xFFFFB74D),
    Color(0xFFBA68C8), Color(0xFF4DD0E1), Color(0xFFF06292), Color(0xFFAED581),
  ];

  @override
  State<ChatAvatar> createState() => _ChatAvatarState();
}

class _ChatAvatarState extends State<ChatAvatar> {
  /// true когда сетевое изображение не смогло загрузиться — показываем fallback.
  bool _imageError = false;

  Color get _color {
    final name = widget.chatName;
    if (name == null || name.isEmpty) return AppColors.primary;
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return ChatAvatar._avatarColors[hash % ChatAvatar._avatarColors.length];
  }

  IconData get _icon => switch (widget.type) {
    ChatType.direct    => Icons.person,
    ChatType.group     => Icons.group,
    ChatType.community => Icons.campaign,
  };

  @override
  void didUpdateWidget(ChatAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Сбрасываем ошибку при смене avatarPath, чтобы повторно попробовать загрузку.
    if (oldWidget.avatarPath != widget.avatarPath) {
      _imageError = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.avatarPath;
    if (!_imageError && path != null && path.isNotEmpty) {
      if (ApiConfig.isServerMediaPath(path)) {
        final url = ApiConfig.resolveMediaUrl(path);
        if (url != null) {
          // GIF-аватары показываем через CachedNetworkImage — он анимирует GIF.
          final isGif = url.toLowerCase().endsWith('.gif');
          if (isGif) {
            return ClipOval(
              child: SizedBox(
                width: widget.radius * 2,
                height: widget.radius * 2,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: _color.withValues(alpha: 0.18)),
                  errorWidget: (_, __, ___) {
                    if (mounted) setState(() => _imageError = true);
                    return Container(color: _color.withValues(alpha: 0.18));
                  },
                ),
              ),
            );
          }
          return CircleAvatar(
            radius: widget.radius,
            backgroundColor: _color.withValues(alpha: 0.18),
            backgroundImage: NetworkImage(url),
            onBackgroundImageError: (e, stack) {
              // Переключаемся на иконку-заглушку при ошибке сети.
              if (mounted) setState(() => _imageError = true);
            },
          );
        }
      } else if (!kIsWeb) {
        // Локальный путь есть только на native-платформах; на web dart:io
        // — это stub, File().existsSync() выбрасывает.
        final file = File(path);
        if (file.existsSync()) {
          return CircleAvatar(
            radius: widget.radius,
            backgroundImage: FileImage(file),
          );
        }
      }
    }
    final color = _color;

    // Для групп и сообществ показываем инициалы из названия (как в Telegram).
    // Для личных чатов — иконку человека.
    if (widget.type != ChatType.direct) {
      final name   = widget.chatName?.trim() ?? '';
      final words  = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      final initials = words.length >= 2
          ? '${words[0][0]}${words[1][0]}'.toUpperCase()
          : name.isNotEmpty ? name[0].toUpperCase() : '?';
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: color,
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.radius * 0.72,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Icon(_icon, size: widget.radius, color: color),
    );
  }
}

// ─── Разделитель дат ──────────────────────────────────────────────────────────

/// Плашка-разделитель между группами сообщений с разными датами (Telegram-style).
class DateSeparator extends StatelessWidget {
  final DateTime date;
  const DateSeparator({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final label = formatMessageGroupDate(date);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );
  }
}

// ─── Панель закреплённых сообщений ────────────────────────────────────────────

/// Telegram-style бар над списком сообщений, показывающий текущее закреплённое
/// сообщение. Тап — прокрутить к сообщению и перейти к следующему в цикле.
class PinnedMessagesBar extends StatelessWidget {
  final List<Message> pinnedMessages;
  /// Индекс текущего отображаемого закреплённого сообщения.
  final int currentIndex;
  /// Вызывается по тапу на бар: прокрутить + перейти к следующему.
  final VoidCallback onTap;
  /// Вызывается при нажатии кнопки открепления; null — кнопка не показывается.
  final void Function(String messageId)? onUnpin;

  const PinnedMessagesBar({
    super.key,
    required this.pinnedMessages,
    required this.currentIndex,
    required this.onTap,
    this.onUnpin,
  });

  static String _preview(Message msg) {
    if (msg.text.isNotEmpty) return msg.text;
    if (msg.poll != null) return '📊 ${msg.poll!.question}';
    final att = msg.attachment;
    if (att != null) {
      return switch (att.type) {
        AttachmentType.image    => '📷 Фото',
        AttachmentType.video    => '🎬 Видео',
        AttachmentType.document => '📎 ${att.fileName}',
        AttachmentType.audio    => '🎤 Голосовое сообщение',
      };
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (pinnedMessages.isEmpty) return const SizedBox.shrink();
    final safeIdx = currentIndex.clamp(0, pinnedMessages.length - 1);
    final msg   = pinnedMessages[safeIdx];
    final total = pinnedMessages.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Theme.of(context).cardColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.07),
              ),
            ),
          ),
          child: Row(
            children: [
              // Цветная полоска (как в Telegram)
              Container(
                width: 2.5,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Закреплённое сообщение',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (total > 1) ...[
                          const Spacer(),
                          Text(
                            '${safeIdx + 1} / $total',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _preview(msg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопка открепить
              if (onUnpin != null)
                IconButton(
                  icon: const Icon(Icons.push_pin, size: 18),
                  color: AppColors.subtle,
                  tooltip: 'Открепить',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => onUnpin!(msg.id),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.push_pin, size: 16, color: AppColors.subtle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Упоминания (@mention) ────────────────────────────────────────────────────

/// Строит [InlineSpan] с цветными кликабельными @упоминаниями.
InlineSpan buildMentionText(
  String text,
  List<Mention> mentions, {
  TextStyle? baseStyle,
  Color? mentionColor,
  void Function(Mention)? onMentionTap,
}) {
  if (mentions.isEmpty || text.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }
  final sorted = List<Mention>.from(mentions)
    ..sort((a, b) => a.offset.compareTo(b.offset));
  final spans = <InlineSpan>[];
  int cursor = 0;
  for (final m in sorted) {
    final start = m.offset.clamp(0, text.length);
    final end   = (m.offset + m.length).clamp(0, text.length);
    if (start >= end) continue;
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start), style: baseStyle));
    }
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onMentionTap != null ? () => onMentionTap(m) : null,
        child: Text(
          text.substring(start, end),
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: mentionColor ?? AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ));
    cursor = end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return TextSpan(children: spans, style: baseStyle);
}

// ─── Карточка опроса ──────────────────────────────────────────────────────────

/// Карточка опроса внутри пузыря сообщения: вопрос, варианты с прогресс-барами,
/// кнопки голосования и завершения.
class PollCard extends StatefulWidget {
  final Poll poll;
  final bool isMe;
  final String? currentUserId;
  /// Callback голосования; null — голосование недоступно.
  final Future<void> Function(List<String> optionIds)? onVote;
  /// Callback закрытия опроса.
  final Future<void> Function()? onClose;
  /// Показывать кнопку «Завершить опрос».
  final bool canClose;

  const PollCard({
    super.key,
    required this.poll,
    this.isMe = false,
    this.currentUserId,
    this.onVote,
    this.onClose,
    this.canClose = false,
  });

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  Set<String> _selected = {};
  bool _isVoting  = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.poll.myVotes);
  }

  @override
  void didUpdateWidget(PollCard old) {
    super.didUpdateWidget(old);
    if (old.poll.myVotes != widget.poll.myVotes) {
      setState(() => _selected = Set.from(widget.poll.myVotes));
    }
  }

  bool get _hasVoted => widget.poll.myVotes.isNotEmpty;
  bool get _canInteract =>
      widget.poll.isActive &&
      widget.onVote != null &&
      (!_hasVoted || widget.poll.canChangeVote);
  bool get _showResults => _hasVoted || !widget.poll.isActive;

  Future<void> _vote() async {
    if (_isVoting || _selected.isEmpty) return;
    setState(() => _isVoting = true);
    try {
      await widget.onVote?.call(_selected.toList());
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  Future<void> _close() async {
    if (_isClosing) return;
    setState(() => _isClosing = true);
    try {
      await widget.onClose?.call();
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final poll    = widget.poll;
    final isMe    = widget.isMe;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final textClr  = isMe ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final subtleClr = isMe ? Colors.white54 : Colors.black45;
    final accentClr = isMe ? Colors.white   : Theme.of(context).colorScheme.primary;
    final total = poll.totalVotes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Вопрос ──────────────────────────────────────
        Text(
          poll.question,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textClr),
        ),
        const SizedBox(height: 4),
        // ── Тип + статус ────────────────────────────────
        Row(children: [
          Icon(
            poll.type == PollType.multiple
                ? Icons.check_box_outlined
                : Icons.radio_button_checked,
            size: 12,
            color: subtleClr,
          ),
          const SizedBox(width: 4),
          Text(
            poll.type == PollType.multiple ? 'Множественный выбор' : 'Опрос',
            style: TextStyle(fontSize: 11, color: subtleClr),
          ),
          if (poll.isAnonymous) ...[
            const SizedBox(width: 8),
            Icon(Icons.lock_outline, size: 12, color: subtleClr),
            const SizedBox(width: 2),
            Text('Анонимный', style: TextStyle(fontSize: 11, color: subtleClr)),
          ],
          const Spacer(),
          if (!poll.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                poll.isClosed ? 'Завершён' : 'Истёк',
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.black45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else if (poll.deadline != null) ...[
            Icon(Icons.schedule, size: 12, color: subtleClr),
            const SizedBox(width: 2),
            Text(
              _fmtDeadline(poll.deadline!),
              style: TextStyle(fontSize: 11, color: subtleClr),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        // ── Варианты ────────────────────────────────────
        for (final opt in poll.options)
          _buildOption(opt, total, isMe, accentClr, subtleClr, textClr),
        const SizedBox(height: 4),
        // ── Итого и кнопка закрыть ───────────────────────
        Row(children: [
          Text(
            '$total ${_pluralVotes(total)}',
            style: TextStyle(fontSize: 12, color: subtleClr),
          ),
          const Spacer(),
          if (widget.canClose && poll.isActive)
            GestureDetector(
              onTap: _isClosing ? null : _close,
              child: Text(
                _isClosing ? 'Завершение…' : 'Завершить опрос',
                style: TextStyle(
                  fontSize: 12,
                  color: isMe ? Colors.white70 : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ]),
        // ── Кнопка «Проголосовать» ───────────────────────
        if (_canInteract && _selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: isMe
                    ? Colors.white.withValues(alpha: 0.2)
                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                foregroundColor: isMe ? Colors.white : Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _isVoting ? null : _vote,
              child: Text(
                _isVoting ? 'Голосование…' : 'Проголосовать',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOption(
    PollOption opt,
    int total,
    bool isMe,
    Color accentClr,
    Color subtleClr,
    Color textClr,
  ) {
    final poll      = widget.poll;
    final isSelected = _selected.contains(opt.id);
    final pct        = poll.optionPercent(opt.id);

    return GestureDetector(
      onTap: _canInteract
          ? () => setState(() {
                if (poll.type == PollType.single) {
                  _selected = {opt.id};
                } else {
                  if (isSelected) {
                    _selected.remove(opt.id);
                  } else {
                    _selected.add(opt.id);
                  }
                }
              })
          : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (!_showResults) ...[
                SizedBox(
                  width: 20, height: 20,
                  child: poll.type == PollType.multiple
                      ? Checkbox(
                          value: isSelected,
                          onChanged: null,
                          activeColor: accentClr,
                          side: BorderSide(color: accentClr, width: 1.5),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )
                      : Radio<bool>(
                          value: true,
                          groupValue: isSelected,
                          onChanged: null,
                          activeColor: accentClr,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  opt.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: textClr,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (_showResults) ...[
                const SizedBox(width: 8),
                Text(
                  opt.votes.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? accentClr : subtleClr,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? accentClr : subtleClr,
                  ),
                ),
              ],
            ]),
            if (_showResults) ...[
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 4,
                  backgroundColor: isMe
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isSelected
                        ? accentClr
                        : (isMe
                            ? Colors.white.withValues(alpha: 0.45)
                            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDeadline(DateTime d) {
    final diff = d.difference(DateTime.now());
    if (diff.inDays > 0)    return 'до ${diff.inDays} дн.';
    if (diff.inHours > 0)   return 'до ${diff.inHours} ч.';
    if (diff.inMinutes > 0) return 'до ${diff.inMinutes} мин.';
    return 'истекает';
  }

  String _pluralVotes(int n) {
    final mod100 = n % 100;
    final mod10  = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return 'голосов';
    if (mod10 == 1) return 'голос';
    if (mod10 >= 2 && mod10 <= 4) return 'голоса';
    return 'голосов';
  }
}

// ─── Иконка статуса сообщения ─────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final Color color;

  const _StatusIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sending   => Icon(Icons.access_time, size: 14, color: color),
      MessageStatus.sent      => Icon(Icons.done, size: 16, color: color),
      MessageStatus.delivered => Icon(Icons.done_all, size: 16, color: color),
      MessageStatus.read      => const Icon(Icons.done_all, size: 16, color: Color(0xFF4FC3F7)),
      MessageStatus.error     => const Icon(Icons.error_outline, size: 14, color: Colors.red),
    };
  }
}

// ─── Пузырь сообщения ─────────────────────────────────────────────────────────

/// Отображает одно сообщение в виде стилизованного пузырька с необязательным аватаром,
/// подсветкой выделения и превью вложения.
class MessageBubble extends StatefulWidget {
  final Message message;
  final bool showSenderName;
  final String? myAvatarPath;
  /// Путь к аватару собеседника (только для личных чатов).
  final String? interlocutorAvatarPath;
  /// Показывать ли аватар слева от чужих сообщений.
  /// true — личный чат или последнее сообщение серии в группе.
  final bool showInterlocutorAvatar;
  /// Зарезервировать место под аватар без отображения (для выравнивания
  /// в середине серии сообщений от одного отправителя в группе).
  final bool reserveAvatarSpace;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  /// Показывать ли кнопку комментариев (только для сообществ).
  final bool showComments;
  /// Колбэк при нажатии на «💬 N комментариев».
  final VoidCallback? onOpenComments;
  /// Колбэк ответа на сообщение (свайп вправо).
  final VoidCallback? onReply;
  /// Все медиа-вложения в чате (изображения + видео) для Telegram-style галереи.
  final List<Attachment> allMedia;
  // ── Опросы ────────────────────────────────────────────
  /// ID текущего пользователя (нужен PollCard).
  final String? currentUserId;
  /// Callback голосования; null → голосование недоступно.
  final Future<void> Function(List<String> optionIds)? onVotePoll;
  /// Callback закрытия опроса.
  final Future<void> Function()? onClosePoll;
  /// Показывать кнопку «Завершить опрос».
  final bool canClosePoll;
  // ── Упоминания ─────────────────────────────────────────
  /// Callback тапа по @упоминанию.
  final void Function(Mention mention)? onMentionTap;
  // ── Академический раздел ───────────────────────────────
  /// Если true — текст сообщений цензурируется при отображении.
  final bool isAcademic;
  // ── Приглашения в группу ───────────────────────────────
  /// Вызывается когда пользователь нажимает «Принять» на карточке-приглашении.
  final Future<void> Function(GroupInvite invite)? onAcceptInvite;

  const MessageBubble({
    super.key,
    required this.message,
    this.showSenderName = false,
    this.myAvatarPath,
    this.interlocutorAvatarPath,
    this.showInterlocutorAvatar = false,
    this.reserveAvatarSpace = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onLongPress,
    required this.onTap,
    this.showComments = false,
    this.onOpenComments,
    this.onReply,
    this.allMedia = const [],
    this.currentUserId,
    this.onVotePoll,
    this.onClosePoll,
    this.canClosePoll = false,
    this.onMentionTap,
    this.isAcademic = false,
    this.onAcceptInvite,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  double _swipeOffset = 0;
  bool _swipeTriggered = false;
  static const _swipeThreshold = 64.0;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final showSenderName = widget.showSenderName;
    final myAvatarPath = widget.myAvatarPath;
    final interlocutorAvatarPath = widget.interlocutorAvatarPath;
    final showInterlocutorAvatar = widget.showInterlocutorAvatar;
    final isSelected = widget.isSelected;
    final isSelectionMode = widget.isSelectionMode;
    final onLongPress = widget.onLongPress;
    final onTap = widget.onTap;
    final showComments = widget.showComments;
    final onOpenComments = widget.onOpenComments;
    final onReply = widget.onReply;
    final isMe = message.isMe;
    // Академическая цензура: при отображении заменяем бранные слова «*».
    final displayText = widget.isAcademic
        ? ProfanityFilter.censor(message.text)
        : message.text;
    final timeColor = isMe
        ? const Color(0xB3FFFFFF)
        : AppColors.subtle;

    // ── Пузырь с контентом ──────────────────────────────
    // Опросы занимают фиксированную ширину 88 % экрана (иначе IntrinsicWidth
    // сжимает пузырь до минимума и Spacer внутри PollCard не работает).
    // Обычные сообщения по-прежнему используют IntrinsicWidth (shrink-to-fit).
    final isInvite    = message.groupInvite != null;
    final isGif       = message.isGif;
    final isStickerEmoji = message.isEmojiOnly;
    final isPoll = message.poll != null;
    // Альбом — только когда вложений больше одного.
    // Сервер всегда заполняет attachments[] даже для одиночных вложений (аудио,
    // одно фото), поэтому isNotEmpty недостаточно — нужен length > 1.
    final isAlbum = message.attachments != null && message.attachments!.length > 1;
    // Сервер может прислать attachment=null + attachments=[item] для одиночных вложений.
    // В этом случае message.attachment == null, и вложение не рендерится.
    // Решение: если attachment == null но attachments содержит ровно 1 элемент —
    // используем его как одиночное вложение.
    final effectiveAttachment = message.attachment ??
        (!isAlbum && (message.attachments?.length == 1)
            ? message.attachments!.first
            : null);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > AppSizes.desktopBreakpoint;
    // Для альбома ширина = min(bubbleMaxWidth, 320/480) — как в Telegram:
    // альбом не должен растягиваться на весь широкий десктоп-чат.
    final bubbleMaxWidth = screenWidth *
        (isPoll ? 0.88 : AppSizes.bubbleMaxWidthFactor);
    final albumWidth = isAlbum
        ? bubbleMaxWidth.clamp(200.0, isDesktop ? 480.0 : 320.0)
        : bubbleMaxWidth;
    // Карточка-приглашение: фиксированная ширина пузыря (как у опроса), иначе
    // IntrinsicWidth вычисляет ширину только по нефлекс-элементам (аватар + кнопка)
    // и Flexible-столбец с названием чата получает 0px — текст не виден на мобиле.
    final inviteWidth = bubbleMaxWidth.clamp(200.0, 320.0);
    Widget bubbleChild = Container(
      // Альбом: фиксированная ширина ≤ 320px, опросы: 88% экрана,
      // карточка-приглашение: ≤ 320px, остальные: shrink-to-fit.
      width: (isPoll || isAlbum || isInvite)
          ? (isPoll ? bubbleMaxWidth : isInvite ? inviteWidth : albumWidth)
          : null,
      constraints: (isPoll || isAlbum || isInvite)
          ? null
          : BoxConstraints(maxWidth: bubbleMaxWidth),
        // У альбома убираем горизонтальные отступы — изображения идут
        // от края до края пузыря, текст/время добавят свои отступы ниже.
        padding: isAlbum
            ? const EdgeInsets.symmetric(vertical: 0, horizontal: 0)
            : const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isMe
              ? (Theme.of(context).extension<CustomChatTheme>()?.myBubbleColor ?? AppColors.chatMe)
              : (Theme.of(context).extension<CustomChatTheme>()?.otherBubbleColor ?? Theme.of(context).cardColor),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSenderName && !isMe && message.senderName != null && !message.postAsCommunity)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text.rich(
                  TextSpan(children: [
                    if (message.senderGroup != null)
                      TextSpan(
                        text: '${message.senderGroup}  ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _senderColor(message.senderName!).withValues(alpha: 0.7),
                        ),
                      ),
                    TextSpan(
                      // Показываем ФИО (Фамилия И.О.) если сервер его вернул, иначе логин
                      text: message.senderDisplayName ?? message.senderName!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _senderColor(message.senderName!),
                      ),
                    ),
                  ]),
                ),
              ),
            // ── Ответ (reply preview) ────────────────────
            if (message.replyTo != null)
              _ReplyPreview(reply: message.replyTo!, isMe: isMe),
            // ── Карточка-приглашение в группу ────────────
            if (message.groupInvite != null) ...[
              _GroupInviteCard(
                invite: message.groupInvite!,
                isMe: isMe,
                onAccept: widget.onAcceptInvite != null
                    ? () => widget.onAcceptInvite!(message.groupInvite!)
                    : null,
              ),
              const SizedBox(height: 4),
            ],
            // ── Опрос ────────────────────────────────────
            if (message.poll != null) ...[
              PollCard(
                key: ValueKey('poll_${message.poll!.id}'),
                poll: message.poll!,
                isMe: isMe,
                currentUserId: widget.currentUserId,
                onVote: widget.onVotePoll,
                onClose: widget.onClosePoll,
                canClose: widget.canClosePoll,
              ),
              const SizedBox(height: 2),
            ],
            // ── Медиаальбом (несколько файлов) ───────────────
            if (isAlbum) ...[
              _MediaAlbum(
                attachments: message.attachments!,
                allMedia: widget.allMedia,
                isMe: isMe,
              ),
              if (message.text.isNotEmpty) const SizedBox(height: 4),
            ],
            // ── Одиночное вложение (аудио / фото / видео / документ) ─────
            if (!isAlbum && effectiveAttachment != null)
              _AttachmentPreview(attachment: effectiveAttachment, isMe: isMe, allMedia: widget.allMedia),
            // Небольшой отступ-разделитель между медиа и подписью
            if (!isAlbum && effectiveAttachment != null && message.text.isNotEmpty)
              const SizedBox(height: 3),
            // ── Текст (с подсвеченными @упоминаниями) + время + статус ──
            // Для карточки-приглашения текст (raw INVITE{...}) не показываем
            if (message.text.isNotEmpty && !isInvite)
              Padding(
                // У альбома текст рендерится вне внешнего padding — добавляем свой
                padding: isAlbum
                    ? const EdgeInsets.fromLTRB(10, 6, 10, 8)
                    : EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text.rich(
                        buildMentionText(
                          displayText,
                          message.mentions,
                          baseStyle: TextStyle(
                            color: isMe ? AppColors.textLight : null,
                          ),
                          mentionColor: isMe ? Colors.white : Theme.of(context).colorScheme.primary,
                          onMentionTap: widget.onMentionTap,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (message.isEdited)
                      Text('изм. ',
                          style: TextStyle(fontSize: 10, color: timeColor)),
                    Text(formatTime(message.time),
                        style: TextStyle(fontSize: 10, color: timeColor)),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      _StatusIcon(status: message.status, color: timeColor),
                    ],
                  ],
                ),
              )
            else
              // Время под вложением / под опросом / пустое сообщение
              Padding(
                padding: isAlbum
                    ? const EdgeInsets.fromLTRB(0, 0, 10, 8)
                    : EdgeInsets.zero,
                child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isEdited)
                        Text('изм. ',
                            style: TextStyle(fontSize: 10, color: timeColor)),
                      Text(formatTime(message.time),
                          style: TextStyle(fontSize: 10, color: timeColor)),
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        _StatusIcon(status: message.status, color: timeColor),
                      ],
                    ],
                  ),
                ),
              ),       // closes Align
            ),         // closes outer Padding (isAlbum guard)
          ],
        ),
    );
    // Альбом, опросы, приглашения — фиксированная ширина; текстовые — shrink-to-fit.
    final bubble = (isPoll || isAlbum || isInvite) ? bubbleChild : IntrinsicWidth(child: bubbleChild);

    // ── Emoji-стикер: без пузыря, крупно ─────────────────────────────────────
    if (isStickerEmoji) {
      return _buildStickerRow(context, message, isMe, isSelected, isSelectionMode, onTap, onLongPress);
    }

    // ── GIF: без пузыря, только анимация ─────────────────────────────────────
    if (isGif) {
      return _buildGifRow(context, message, isMe, isSelected, isSelectionMode, onTap, onLongPress, bubbleMaxWidth);
    }

    // В режиме выделения касания переключают выбор; вне него долгое нажатие открывает меню действий.
    Widget row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isSelectionMode ? onTap : null,
      onLongPress: isSelectionMode ? null : onLongPress,
      onSecondaryTap: isSelectionMode ? null : onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Чекбокс выделения ─────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: isSelectionMode
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? Theme.of(context).colorScheme.primary : AppColors.subtle,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // ── Содержимое сообщения ──────────────────────
            Expanded(
              child: Row(
                mainAxisAlignment:
                    isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Аватар слева от чужих сообщений
                  if (!isMe && showInterlocutorAvatar) ...[
                    ProfileAvatar(
                      avatarPath: widget.message.senderAvatarPath ??
                          interlocutorAvatarPath,
                      radius: AppSizes.avatarRadiusSmall,
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Резервируем место под аватар для выравнивания серии сообщений
                  if (!isMe && widget.reserveAvatarSpace)
                    const SizedBox(width: AppSizes.avatarRadiusSmall * 2 + 6),
                  // Минимальный отступ когда аватар не нужен совсем
                  if (!isMe && !showInterlocutorAvatar && !widget.reserveAvatarSpace)
                    const SizedBox(width: 4),
                  Flexible(
                    child: Column(
                      crossAxisAlignment:
                          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        bubble,
                        // ── Кнопка комментариев ────────────────
                        if (showComments)
                          GestureDetector(
                            onTap: onOpenComments,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mode_comment_outlined,
                                      size: 14, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    message.comments.isEmpty
                                        ? 'Комментировать'
                                        : '${message.comments.length} комментари${_commentSuffix(message.comments.length)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    ProfileAvatar(
                      avatarPath: myAvatarPath,
                      radius: AppSizes.avatarRadiusSmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Свайп вправо для ответа (Telegram-style с пружинящей иконкой)
    if (onReply != null && !isSelectionMode) {
      final swipeProgress = (_swipeOffset / _swipeThreshold).clamp(0.0, 1.0);
      row = GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _swipeOffset = (_swipeOffset + details.delta.dx).clamp(0.0, _swipeThreshold + 20);
            if (!_swipeTriggered && _swipeOffset >= _swipeThreshold) {
              _swipeTriggered = true;
              HapticFeedback.lightImpact();
            }
          });
        },
        onHorizontalDragEnd: (_) {
          if (_swipeTriggered) onReply();
          setState(() {
            _swipeOffset = 0;
            _swipeTriggered = false;
          });
        },
        onHorizontalDragCancel: () {
          setState(() {
            _swipeOffset = 0;
            _swipeTriggered = false;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Иконка-индикатор свайпа
            if (_swipeOffset > 4)
              Positioned(
                left: _swipeOffset - 44,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _swipeTriggered
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.reply,
                      size: 18 + (swipeProgress * 4),
                      color: _swipeTriggered ? Colors.white : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            // Само сообщение, сдвигается вправо
            Transform.translate(
              offset: Offset(_swipeOffset, 0),
              child: row,
            ),
          ],
        ),
      );
    }

    return row;
  }

  // ── Emoji-стикер (без пузыря) ─────────────────────────────────────────────

  Widget _buildStickerRow(
    BuildContext context, Message message, bool isMe,
    bool isSelected, bool isSelectionMode,
    VoidCallback onTap, VoidCallback onLongPress,
  ) {
    final timeColor = AppColors.subtle;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:          isSelectionMode ? onTap : null,
      onLongPress:    isSelectionMode ? null : onLongPress,
      onSecondaryTap: isSelectionMode ? null : onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.text.trim(),
                    style: const TextStyle(fontSize: 52, height: 1.1)),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatTime(message.time),
                        style: TextStyle(fontSize: 10, color: timeColor)),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      _StatusIcon(status: message.status, color: timeColor),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── GIF (без пузыря, с анимацией) ─────────────────────────────────────────

  Widget _buildGifRow(
    BuildContext context, Message message, bool isMe,
    bool isSelected, bool isSelectionMode,
    VoidCallback onTap, VoidCallback onLongPress, double maxWidth,
  ) {
    final timeColor = AppColors.subtle;
    final gifUrl    = message.gifUrl!;
    final gifWidth  = (maxWidth * 0.65).clamp(140.0, 260.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:          isSelectionMode ? onTap : null,
      onLongPress:    isSelectionMode ? null : onLongPress,
      onSecondaryTap: isSelectionMode ? null : onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  // CachedNetworkImage кэширует GIF на диск — при повторном
                  // открытии чата анимация берётся из кэша, а не качается
                  // заново из сети. Без этого Image.network перезагружал
                  // GIF при каждом входе в приложение, и тот «переигрывал»
                  // анимацию с начала — из-за чего сообщение визуально
                  // выглядело как только что пришедшее («новое»).
                  child: CachedNetworkImage(
                    imageUrl: gifUrl,
                    width: gifWidth,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => SizedBox(
                      width: gifWidth,
                      height: gifWidth * 0.7,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => SizedBox(
                      width: gifWidth,
                      height: 60,
                      child: const Center(
                          child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatTime(message.time),
                        style: TextStyle(fontSize: 10, color: timeColor)),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      _StatusIcon(status: message.status, color: timeColor),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Превью ответа внутри пузыря сообщения (Telegram-style).
class _ReplyPreview extends StatelessWidget {
  final ReplyInfo reply;
  final bool isMe;

  const _ReplyPreview({required this.reply, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final accentColor = _senderColor(reply.senderName);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      // TODO: можно прокрутить к цитируемому сообщению
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: isMe
              ? Colors.black.withValues(alpha: 0.1)
              : accentColor.withValues(alpha: 0.1),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Цветная полоска слева (2px, скруглена с контейнером)
              Container(
                width: 2.5,
                color: isMe ? Colors.white.withValues(alpha: 0.85) : accentColor,
              ),
              // Текст
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        reply.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isMe ? Colors.white : accentColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        reply.text.isEmpty ? 'Вложение' : reply.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.7)
                              : isDark
                                  ? Colors.white70
                                  : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Генерирует уникальный цвет для имени отправителя (контрастный на светлом фоне).
Color _senderColor(String name) {
  const colors = [
    Color(0xFFD32F2F), // red
    Color(0xFF388E3C), // green
    Color(0xFF1976D2), // blue
    Color(0xFFE64A19), // deep orange
    Color(0xFF7B1FA2), // purple
    Color(0xFF00838F), // cyan
    Color(0xFFC2185B), // pink
    Color(0xFF455A64), // blue grey
  ];
  final hash = name.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
  return colors[hash.abs() % colors.length];
}

/// Склонение слова «комментарий» по числу.
String _commentSuffix(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 19) return 'ев';
  if (mod10 == 1) return 'й';
  if (mod10 >= 2 && mod10 <= 4) return 'я';
  return 'ев';
}

/// Показывает выбор способа сохранения: «Сохранить» (в папку CaspianMessenger)
/// или «Сохранить как…» (выбор папки вручную).
/// Используется в чате, комментариях и просмотрщике медиа.
Future<void> showSaveOptions(BuildContext context, Attachment att) async {
  if (kIsWeb) return;
  final result = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            leading: const Icon(Icons.download_done_outlined),
            title: const Text('Сохранить'),
            subtitle: const Text('В папку CaspianMessenger'),
            onTap: () => Navigator.pop(sheetCtx, 'save'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Сохранить как…'),
            subtitle: const Text('Выбрать папку вручную'),
            onTap: () => Navigator.pop(sheetCtx, 'save_as'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (result == 'save') {
    await _saveAttachmentDefault(context, att);
  } else if (result == 'save_as') {
    await _saveAttachmentAs(context, att);
  }
}

/// Быстрое сохранение в папку CaspianMessenger без диалога.
Future<void> _saveAttachmentDefault(BuildContext context, Attachment att) async {
  try {
    await MediaSaveService.instance.saveToDefaultFolder(att);
    if (!context.mounted) return;
    AppSnack.success(context, 'Сохранено в папку CaspianMessenger');
  } catch (e) {
    if (!context.mounted) return;
    AppSnack.error(context, 'Ошибка сохранения: $e');
  }
}

/// Сохранение с выбором папки через системный диалог.
Future<void> _saveAttachmentAs(BuildContext context, Attachment att) async {
  if (kIsWeb) return;
  String? destPath;
  try {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // Desktop: нативный диалог «Сохранить как»
      destPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить как',
        fileName: att.fileName,
      );
    } else {
      // Mobile: выбираем папку, имя файла оставляем оригинальное
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выберите папку для сохранения',
      );
      if (dir != null) destPath = '$dir${Platform.pathSeparator}${att.fileName}';
    }
  } catch (_) {
    // FilePicker недоступен — используем папку по умолчанию
    destPath = null;
  }
  if (destPath == null) return; // пользователь отменил

  try {
    final destDir = File(destPath).parent.path;
    await Directory(destDir).create(recursive: true);

    if (ApiConfig.isServerMediaPath(att.path)) {
      final cached = await FileDownloadService.instance.getLocalPathIfExists(att.path);
      if (cached != null) {
        await File(cached).copy(destPath);
      } else {
        final url = ApiConfig.resolveMediaUrl(att.path)!;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
        await File(destPath).writeAsBytes(response.bodyBytes);
      }
    } else {
      await File(att.path).copy(destPath);
    }

    if (!context.mounted) return;
    AppSnack.success(context, 'Сохранено: ${att.fileName}');
  } catch (e) {
    if (!context.mounted) return;
    AppSnack.error(context, 'Ошибка сохранения: $e');
  }
}

// ─── Превью вложения ─────────────────────────────────────────────────────────

class _AttachmentPreview extends StatelessWidget {
  final Attachment attachment;
  final bool isMe;
  final List<Attachment> allMedia;

  const _AttachmentPreview({required this.attachment, required this.isMe, this.allMedia = const []});

  @override
  Widget build(BuildContext context) {
    return switch (attachment.type) {
      AttachmentType.image    => _ImagePreview(attachment: attachment, allMedia: allMedia),
      AttachmentType.video    => _VideoPreview(attachment: attachment, allMedia: allMedia),
      AttachmentType.document => _DocumentPreview(attachment: attachment, isMe: isMe),
      AttachmentType.audio    => AudioMessageBubble(
          audioPath: attachment.path,
          durationMs: attachment.durationMs,
          foregroundColor: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
        ),
    };
  }
}

class _ImagePreview extends StatelessWidget {
  final Attachment attachment;
  final List<Attachment> allMedia;

  const _ImagePreview({required this.attachment, this.allMedia = const []});

  @override
  Widget build(BuildContext context) {
    final path = attachment.path;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > AppSizes.desktopBreakpoint;
    final w = isDesktop ? 340.0 : 220.0;
    final h = isDesktop ? 280.0 : 200.0;

    void openViewer() => MediaViewerScreen.open(context, attachment, allMedia: allMedia);

    Widget frame(Widget child) => _MediaFrame(isDark: isDark, child: child);

    // Изображение, хранящееся на сервере → грузим по сети
    if (ApiConfig.isServerMediaPath(path)) {
      final url = ApiConfig.resolveMediaUrl(path)!;
      return GestureDetector(
        onTap: openViewer,
        child: Hero(
          tag: 'media_$path',
          child: frame(ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              url,
              width: w,
              height: h,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: w, height: h,
                  color: Colors.grey[300],
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                );
              },
              errorBuilder: (ctx, e, s) => _brokenBox(w, h),
            ),
          )),
        ),
      );
    }

    // Локальный файл устройства (исходящее сообщение в процессе отправки)
    final file = File(path);
    if (!file.existsSync()) return _brokenBox(w, h);
    return GestureDetector(
      onTap: openViewer,
      child: Hero(
        tag: 'media_$path',
        child: frame(ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(file, width: w, height: h, fit: BoxFit.cover),
        )),
      ),
    );
  }

  Widget _brokenBox(double w, double h) => Container(
        width: w, height: h / 2,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
}

/// Изображение для поста канала: загружает естественные пропорции и отображает
/// без обрезки. Портретные снимки показываются вертикально (ratio ≥ 0.45),
/// горизонтальные — до 2.2:1. Пока размер не загружен, используется 4:3.
class _ChannelPostImage extends StatefulWidget {
  final Attachment attachment;
  final List<Attachment> allMedia;
  const _ChannelPostImage({required this.attachment, required this.allMedia});

  @override
  State<_ChannelPostImage> createState() => _ChannelPostImageState();
}

class _ChannelPostImageState extends State<_ChannelPostImage> {
  double? _ratio;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolveRatio();
  }

  void _resolveRatio() {
    final path = widget.attachment.path;
    final ImageProvider provider;
    if (ApiConfig.isServerMediaPath(path)) {
      provider = NetworkImage(ApiConfig.resolveMediaUrl(path)!);
    } else {
      final file = File(path);
      if (!file.existsSync()) return;
      provider = FileImage(file);
    }
    final stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener(
      (info, _) {
        if (mounted) {
          setState(() {
            _ratio = info.image.width / info.image.height;
          });
        }
      },
      onError: (_, __) {},
    );
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    // нет способа получить stream снова без провайдера, но listener GC-ится сам
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.attachment.path;

    // ── Максимальная высота изображения ────────────────────────────────────
    // Резервируем место для: app-titlebar(32) + chat-topbar(56) + input(68)
    //   + header поста(52) + footer поста(44) + padding(28) + запас(20) = 300 px
    final viewportH = MediaQuery.of(context).size.height;
    final maxImgH = (viewportH - 300).clamp(140.0, 720.0);

    void openViewer() =>
        MediaViewerScreen.open(context, widget.attachment, allMedia: widget.allMedia);

    // Строим изображение (одинаково для сети и файла)
    Widget buildImage() {
      if (ApiConfig.isServerMediaPath(path)) {
        final url = ApiConfig.resolveMediaUrl(path)!;
        return Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, prog) {
            if (prog == null) return child;
            return Container(
              color: Colors.grey[300],
              alignment: Alignment.center,
              child: const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey[300],
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      } else {
        final file = File(path);
        if (!file.existsSync()) {
          return Container(
            color: Colors.grey[300],
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          );
        }
        return Image.file(
          file,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey[300],
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      }
    }

    return LayoutBuilder(builder: (ctx, constraints) {
      final availW = constraints.maxWidth;

      // Натуральные пропорции (пока не загружены — заглушка 4:3)
      final naturalRatio = _ratio ?? (4 / 3);

      // Высота при полной ширине с натуральными пропорциями
      final naturalH = availW / naturalRatio;

      // Ограничиваем высоту: изображение масштабируется так, чтобы весь пост
      // вписывался во вьюпорт. Пропорции сохраняются — cover кадрирует только
      // крайние пиксели при достижении лимита.
      final displayH = naturalH.clamp(0.0, maxImgH);

      // Пересчитываем отношение сторон от реальной ширины и ограниченной высоты
      final displayRatio = availW / displayH;

      return GestureDetector(
        onTap: openViewer,
        child: Hero(
          tag: 'media_$path',
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: AspectRatio(aspectRatio: displayRatio, child: buildImage()),
          ),
        ),
      );
    });
  }
}

/// Полупрозрачный фон-рамка вокруг медиа (фото / видео) — Telegram-style.
/// Создаёт лёгкое «стекло» вокруг контента с скруглёнными углами 13 px,
/// внутрь добавляется 3 px padding, поэтому дочерний ClipRRect должен
/// использовать borderRadius ≈ 10 px.
class _MediaFrame extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const _MediaFrame({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
      ),
      padding: const EdgeInsets.all(3),
      child: child,
    );
  }
}

class _VideoPreview extends StatelessWidget {
  final Attachment attachment;
  final List<Attachment> allMedia;
  const _VideoPreview({required this.attachment, this.allMedia = const []});

  // ── UI ───────────────────────────────────────────────────────────────────

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _buildBackdrop(double w, double h) {
    final thumbUrl = ApiConfig.resolveMediaUrl(attachment.thumbnailPath);
    if (thumbUrl != null) {
      return Image.network(
        thumbUrl,
        width: w,
        height: h,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (ctx, err, stack) => _placeholderBackdrop(w, h),
      );
    }
    return _placeholderBackdrop(w, h);
  }

  Widget _placeholderBackdrop(double w, double h) => Container(
        width: w,
        height: h,
        color: const Color(0xFF1A1A1A),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.videocam_outlined, color: Colors.white24, size: 44),
            SizedBox(height: 6),
            Text('Видео', style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width > AppSizes.desktopBreakpoint;
    final w = isDesktop ? 340.0 : 220.0;
    final h = isDesktop ? 240.0 : 160.0;
    final dur = attachment.duration;

    return GestureDetector(
      onTap: () =>
          MediaViewerScreen.open(context, attachment, allMedia: allMedia),
      child: _MediaFrame(
        isDark: isDark,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Фоновый кадр ─────────────────────────────────────────────
              _buildBackdrop(w, h),

              // ── Кнопка Play ──────────────────────────────────────────────
              Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white60, width: 2),
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 34),
                ),

              // ── Нижняя полоса: имя файла + длительность ──────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(10)),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        Colors.transparent
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam, color: Colors.white60, size: 13),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          attachment.fileName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Длительность
                      if (dur != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _fmtDuration(dur),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        )
                      else if (attachment.fileSize != null)
                        Text(
                          attachment.readableSize,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Превью документа-вложения. Поддерживает скачивание с сервера с показом
/// прогресса (как в Telegram/WhatsApp):
/// - idle: иконка «скачать» → по тапу запускается загрузка.
/// - downloading: круговой прогресс, по тапу — отмена.
/// - completed: иконка типа файла, по тапу — открыть; долгое нажатие —
///   удалить локальную копию.
/// - failed: иконка повтора, по тапу — повторная попытка.
///
/// Локальные вложения (ещё не загруженные на сервер) показываются статично.
class _DocumentPreview extends StatefulWidget {
  final Attachment attachment;
  final bool isMe;

  const _DocumentPreview({required this.attachment, required this.isMe});

  @override
  State<_DocumentPreview> createState() => _DocumentPreviewState();
}

class _DocumentPreviewState extends State<_DocumentPreview> {
  StreamSubscription<DownloadProgress>? _sub;
  DownloadProgress _progress = const DownloadProgress(state: DownloadState.idle);

  bool get _isRemote => ApiConfig.isServerMediaPath(widget.attachment.path);

  @override
  void initState() {
    super.initState();
    if (_isRemote) {
      _sub = FileDownloadService.instance
          .watch(widget.attachment.path)
          .listen((p) {
        if (!mounted) return;
        setState(() => _progress = p);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Иконка по расширению файла
  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf,
      'doc' || 'docx' => Icons.description,
      'xls' || 'xlsx' => Icons.table_chart,
      'zip' || 'rar' || '7z' => Icons.folder_zip,
      'mp3' || 'wav' || 'ogg' => Icons.audio_file,
      'mp4' || 'mov' || 'avi' => Icons.video_file,
      _ => Icons.insert_drive_file,
    };
  }

  Future<void> _onTap() async {
    if (!_isRemote) return;
    final svc = FileDownloadService.instance;
    switch (_progress.state) {
      case DownloadState.idle:
      case DownloadState.failed:
        try {
          await svc.download(
            widget.attachment.path,
            fileName: widget.attachment.fileName,
          );
        } catch (_) {
          // Ошибка попадёт в стрим — UI уже обновился.
        }
        break;
      case DownloadState.downloading:
        // Отмена загрузки.
        await svc.cancel(widget.attachment.path);
        break;
      case DownloadState.completed:
        final path = _progress.localPath;
        if (path != null) {
          await OpenFilex.open(path);
        }
        break;
    }
  }

  Future<void> _onLongPress() async {
    if (!_isRemote) return;
    final canDelete = _progress.state == DownloadState.completed;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(widget.attachment.fileName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          if (canDelete)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'open'),
              child: Row(
                children: [
                  Icon(Icons.open_in_new, size: 20, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 12),
                  Text('Открыть'),
                ],
              ),
            ),
          if (canDelete)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'share'),
              child: Row(
                children: [
                  Icon(Icons.share_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 12),
                  Text('Открыть в программе…'),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'save_default'),
            child: Row(
              children: [
                Icon(Icons.download_done_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('Сохранить'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'save_as'),
            child: Row(
              children: [
                Icon(Icons.folder_open_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('Сохранить как…'),
              ],
            ),
          ),
          if (canDelete)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Удалить с устройства',
                      style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final path = _progress.localPath;
    if (action == 'open' && path != null) {
      await OpenFilex.open(path);
    } else if (action == 'share' && path != null) {
      await Share.shareXFiles([XFile(path)]);
    } else if (action == 'save_default') {
      await _saveAttachmentDefault(context, widget.attachment);
    } else if (action == 'save_as') {
      await _saveAttachmentAs(context, widget.attachment);
    } else if (action == 'delete') {
      await FileDownloadService.instance.removeLocal(widget.attachment.path);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Widget _buildLeadingIcon(Color color) {
    const size = 28.0;
    if (!_isRemote) {
      return Icon(_iconForFile(widget.attachment.fileName),
          color: color, size: size);
    }
    switch (_progress.state) {
      case DownloadState.idle:
        return Icon(Icons.file_download_outlined, color: color, size: size);
      case DownloadState.downloading:
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _progress.progress,
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              Icon(Icons.close, color: color, size: 14),
            ],
          ),
        );
      case DownloadState.completed:
        return Icon(_iconForFile(widget.attachment.fileName),
            color: color, size: size);
      case DownloadState.failed:
        return Icon(Icons.refresh, color: color, size: size);
    }
  }

  String? _buildSubtitle() {
    final fullSize = widget.attachment.readableSize;
    if (!_isRemote) {
      return fullSize.isEmpty ? null : fullSize;
    }
    switch (_progress.state) {
      case DownloadState.downloading:
        final received = _formatBytes(_progress.received);
        if (_progress.total > 0) {
          final total = _formatBytes(_progress.total);
          final pct = _progress.progress == null
              ? ''
              : ' • ${(_progress.progress! * 100).toStringAsFixed(0)}%';
          return '$received / $total$pct';
        }
        return received.isEmpty ? 'Загрузка…' : '$received • загрузка…';
      case DownloadState.failed:
        return 'Ошибка — нажмите, чтобы повторить';
      case DownloadState.completed:
        return fullSize.isEmpty ? 'На устройстве' : '$fullSize • на устройстве';
      case DownloadState.idle:
        return fullSize.isEmpty ? 'Нажмите, чтобы скачать' : fullSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isMe ? AppColors.textLight : AppColors.textDark;
    final subtleColor =
        widget.isMe ? const Color(0xB3FFFFFF) : AppColors.subtle;
    final subtitle = _buildSubtitle();

    return InkWell(
      onTap: _isRemote ? _onTap : null,
      onLongPress: _isRemote ? _onLongPress : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.15)
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLeadingIcon(textColor),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.attachment.fileName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: subtleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Кнопка сохранения (только для не-web, файл уже скачан)
            if (_isRemote && !kIsWeb &&
                _progress.state == DownloadState.completed) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => showSaveOptions(context, widget.attachment),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.save_alt, size: 18, color: subtleColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Медиаальбом (несколько фото/видео в одном сообщении) ────────────────────

/// Telegram-style grid из нескольких медиавложений.
/// Раскладка:
///   1  → полная ширина
///   2  → два равных столбца
///   3  → первый на всю ширину + два ниже
///   4+ → сетка 2 столбца
class _MediaAlbum extends StatelessWidget {
  final List<Attachment> attachments;
  /// Все медиафайлы чата — для полноэкранного просмотра со стрелками.
  final List<Attachment> allMedia;
  final bool isMe;

  const _MediaAlbum({
    required this.attachments,
    required this.isMe,
    this.allMedia = const [],
  });

  static const double _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final n = attachments.length;

    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final isDesktop = MediaQuery.of(ctx).size.width > AppSizes.desktopBreakpoint;

      // Высоты адаптируются к ширине пузыря — как в Telegram:
      //   • «большое» фото ≈ соотношение 4:3
      //   • «маленькое» (строка) ≈ половина большого
      final bigH  = (w * 0.75).clamp(120.0, isDesktop ? 340.0 : 200.0);
      final rowH  = (w * 0.38).clamp(80.0,  isDesktop ? 200.0 : 120.0);
      final pairH = (w * 0.56).clamp(100.0, isDesktop ? 260.0 : 160.0); // для N=2

      // ── 1 файл ──────────────────────────────────────────────────────────────
      if (n == 1) {
        return _tile(ctx, attachments[0],
            width: w, height: bigH,
            tl: true, tr: true, bl: true, br: true);
      }

      // ── 2 файла ─────────────────────────────────────────────────────────────
      if (n == 2) {
        final hw = (w - _gap) / 2;
        return Row(children: [
          _tile(ctx, attachments[0], width: hw, height: pairH,
              tl: true, bl: true),
          const SizedBox(width: _gap),
          _tile(ctx, attachments[1], width: hw, height: pairH,
              tr: true, br: true),
        ]);
      }

      // ── 3 файла ─────────────────────────────────────────────────────────────
      if (n == 3) {
        final hw = (w - _gap) / 2;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _tile(ctx, attachments[0], width: w, height: bigH,
              tl: true, tr: true),
          const SizedBox(height: _gap),
          Row(children: [
            _tile(ctx, attachments[1], width: hw, height: rowH,
                bl: true),
            const SizedBox(width: _gap),
            _tile(ctx, attachments[2], width: hw, height: rowH,
                br: true),
          ]),
        ]);
      }

      // ── 4 файла ─────────────────────────────────────────────────────────────
      if (n == 4) {
        final hw = (w - _gap) / 2;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _tile(ctx, attachments[0], width: hw, height: pairH,
                tl: true),
            const SizedBox(width: _gap),
            _tile(ctx, attachments[1], width: hw, height: pairH,
                tr: true),
          ]),
          const SizedBox(height: _gap),
          Row(children: [
            _tile(ctx, attachments[2], width: hw, height: pairH,
                bl: true),
            const SizedBox(width: _gap),
            _tile(ctx, attachments[3], width: hw, height: pairH,
                br: true),
          ]),
        ]);
      }

      // ── 5 и более: первое большое + остальные по 3 в ряд ───────────────────
      final rest = attachments.sublist(1);
      final cols = <Widget>[];
      for (int i = 0; i < rest.length; i += 3) {
        final chunk = rest.sublist(i, (i + 3).clamp(0, rest.length));
        final tw = (w - _gap * (chunk.length - 1)) / chunk.length;
        final isLastRow = i + 3 >= rest.length;
        cols.add(Row(children: [
          for (int j = 0; j < chunk.length; j++) ...[
            if (j > 0) const SizedBox(width: _gap),
            _tile(ctx, chunk[j],
                width: tw, height: rowH,
                bl: isLastRow && j == 0,
                br: isLastRow && j == chunk.length - 1),
          ],
        ]));
        cols.add(const SizedBox(height: _gap));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _tile(ctx, attachments[0], width: w, height: bigH,
            tl: true, tr: true),
        const SizedBox(height: _gap),
        ...cols,
      ]);
    });
  }

  // ── Строит одну плитку с точными размерами ──────────────────────────────────

  Widget _tile(BuildContext context, Attachment att, {
    required double width, required double height,
    bool tl = false, bool tr = false,
    bool bl = false, bool br = false,
  }) {
    const r = Radius.circular(8);
    final radius = BorderRadius.only(
      topLeft:     tl ? r : Radius.zero,
      topRight:    tr ? r : Radius.zero,
      bottomLeft:  bl ? r : Radius.zero,
      bottomRight: br ? r : Radius.zero,
    );

    Widget content;
    if (att.type == AttachmentType.video) {
      final thumbUrl = ApiConfig.resolveMediaUrl(att.thumbnailPath);
      content = Stack(fit: StackFit.expand, children: [
        if (thumbUrl != null)
          Image.network(thumbUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black54))
        else
          const ColoredBox(color: Colors.black54,
              child: Center(child: Icon(Icons.movie_outlined,
                  size: 36, color: Colors.white24))),
        Center(child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.55),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
        )),
      ]);
    } else {
      Widget img;
      if (ApiConfig.isServerMediaPath(att.path)) {
        final url = ApiConfig.resolveMediaUrl(att.path);
        img = url != null
            ? Image.network(url,
                width: width, height: height, fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null
                    ? child
                    : ColoredBox(color: Colors.grey.shade300,
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2))),
                errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26))
            : const ColoredBox(color: Colors.black26);
      } else {
        img = Image.file(File(att.path),
            width: width, height: height, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26));
      }
      content = img;
    }

    return GestureDetector(
      onTap: () => MediaViewerScreen.open(
          context, att,
          allMedia: allMedia.isNotEmpty ? allMedia : attachments),
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(width: width, height: height, child: content),
      ),
    );
  }
}

// ─── Пост канала/сообщества (Telegram-style) ─────────────────────────────────

/// Карточка-пост в стиле Telegram-канала: полная ширина, шапка с аватаром
/// канала и именем, контент, нижняя панель с кнопкой комментариев.
class ChannelPostCard extends StatefulWidget {
  final Message message;
  final String channelName;
  final String? channelAvatarPath;

  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final VoidCallback? onOpenComments;
  final List<Attachment> allMedia;
  final String? currentUserId;
  final void Function(List<String>)? onVotePoll;
  final VoidCallback? onClosePoll;
  final bool canClosePoll;
  final void Function(Mention)? onMentionTap;

  const ChannelPostCard({
    super.key,
    required this.message,
    required this.channelName,
    this.channelAvatarPath,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onLongPress,
    required this.onTap,
    this.onOpenComments,
    this.allMedia = const [],
    this.currentUserId,
    this.onVotePoll,
    this.onClosePoll,
    this.canClosePoll = false,
    this.onMentionTap,
  });

  @override
  State<ChannelPostCard> createState() => _ChannelPostCardState();
}

class _ChannelPostCardState extends State<ChannelPostCard> {
  @override
  Widget build(BuildContext context) {
    final msg     = widget.message;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final isAlbum = msg.attachments != null && msg.attachments!.length > 1;
    final isPoll  = msg.poll != null;
    final cardColor = isDark ? const Color(0xFF1E2128) : Colors.white;

    // Поддержка серверного формата: attachment=null + attachments=[item]
    final effectiveAttachment = msg.attachment ??
        (!isAlbum && (msg.attachments?.length == 1)
            ? msg.attachments!.first
            : null);
    final attType    = effectiveAttachment?.type;
    final isMediaAtt = attType == AttachmentType.image ||
        attType == AttachmentType.video;

    // Карточка — полная ширина с небольшим горизонтальным отступом
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? primary.withValues(alpha: 0.08)
            : cardColor,
        borderRadius: BorderRadius.circular(14),
        border: widget.isSelected
            ? Border.all(color: primary.withValues(alpha: 0.35), width: 1.5)
            : Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Шапка ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  ChatAvatar(
                    type: ChatType.community,
                    avatarPath: widget.channelAvatarPath,
                    chatName: widget.channelName,
                    radius: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.channelName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _formatPostTime(msg.time),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),

            // ── Опрос ───────────────────────────────────────────────────────
            if (isPoll) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PollCard(
                  key: ValueKey('poll_${msg.poll!.id}'),
                  poll: msg.poll!,
                  isMe: false,
                  currentUserId: widget.currentUserId,
                  onVote: widget.onVotePoll != null
                      ? (ids) async => widget.onVotePoll!(ids)
                      : null,
                  onClose: widget.onClosePoll != null
                      ? () async => widget.onClosePoll!()
                      : null,
                  canClose: widget.canClosePoll,
                ),
              ),
              const SizedBox(height: 8),

            // ── Медиаальбом (без ограничения высоты — виджет сам считает её) ─
            ] else if (isAlbum) ...[
              _MediaAlbum(
                attachments: msg.attachments!,
                allMedia: widget.allMedia,
                isMe: false,
              ),
              if (msg.text.isNotEmpty) const SizedBox(height: 4),

            // ── Фото: естественные пропорции (портрет/альбом). Видео: 16:9. ──
            ] else if (effectiveAttachment != null && isMediaAtt) ...[
              if (effectiveAttachment.type == AttachmentType.image)
                _ChannelPostImage(
                  attachment: effectiveAttachment,
                  allMedia: widget.allMedia,
                )
              else
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _AttachmentPreview(
                    attachment: effectiveAttachment,
                    isMe: false,
                    allMedia: widget.allMedia,
                  ),
                ),
              if (msg.text.isNotEmpty) const SizedBox(height: 4),

            // ── Документ / аудио (с отступами) ─────────────────────────────
            ] else if (effectiveAttachment != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _AttachmentPreview(
                  attachment: effectiveAttachment,
                  isMe: false,
                  allMedia: widget.allMedia,
                ),
              ),
              if (msg.text.isNotEmpty) const SizedBox(height: 4),
            ],

            // ── Текст ────────────────────────────────────────────────────────
            if (msg.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text.rich(
                  buildMentionText(
                    msg.text,
                    msg.mentions,
                    baseStyle: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                      height: 1.45,
                    ),
                    mentionColor: primary,
                    onMentionTap: widget.onMentionTap,
                  ),
                ),
              ),

            // ── Нижняя панель ────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      if (msg.text.isNotEmpty) Share.share(msg.text);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(children: [
                        Icon(Icons.forward,
                            size: 15,
                            color: isDark ? Colors.white54 : Colors.black38),
                        const SizedBox(width: 4),
                        Text('Переслать',
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.black38)),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  if (widget.onOpenComments != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: widget.onOpenComments,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Row(children: [
                          Icon(Icons.mode_comment_outlined,
                              size: 15, color: primary),
                          const SizedBox(width: 4),
                          Text(
                            msg.comments.isEmpty
                                ? 'Комментарии'
                                : '${msg.comments.length}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: primary),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isSelectionMode ? widget.onTap : null,
      onLongPress: widget.isSelectionMode ? null : widget.onLongPress,
      onSecondaryTap: widget.isSelectionMode ? null : widget.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          // Ширина поста: 60% чата на десктопе, полная ширина на мобиле.
          // Минимум 260px, максимум 560px.
          final postWidth = (constraints.maxWidth *
                  (constraints.maxWidth > 600 ? 0.60 : 1.0))
              .clamp(260.0, 560.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          widget.isSelected ? primary : Colors.transparent,
                      border: Border.all(
                        color: widget.isSelected
                            ? primary
                            : AppColors.subtle,
                        width: 2,
                      ),
                    ),
                    child: widget.isSelected
                        ? const Icon(Icons.check,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              SizedBox(width: postWidth, child: card),
            ],
          );
        }),
      ),
    );
  }

  /// Формат времени поста: сегодня → "14:32", иначе → "10 мая"
  static String _formatPostTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

// ─── Поле ввода сообщения ─────────────────────────────────────────────────────

/// Панель ввода текста в нижней части экрана чата.
///
/// Поведение правой кнопки:
/// - Текст набран или режим редактирования  → кнопка «Отправить/✓» (обычный тап).
/// - Поле пусто + [onSendAudio] передан     → кнопка 🎤 (удержание = запись,
///   свайп влево = отмена, отпускание = отправить голосовое).
///
/// Важно: GestureDetector кнопки микрофона **остаётся в дереве** во время
/// записи, чтобы Flutter не прерывал жест при перестройке виджета.
class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool isEditing;
  /// Нажатие на кнопку 😊 — родитель управляет панелью эмодзи/GIF.
  final VoidCallback? onEmojiTap;
  /// Если true — кнопка эмодзи подсвечена (панель открыта).
  final bool emojiPanelOpen;

  /// Вызывается при завершении записи голосового сообщения.
  /// [path] — путь к m4a файлу, [durationMs] — длительность в мс.
  final Future<void> Function(String path, int durationMs)? onSendAudio;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    this.isEditing = false,
    this.onSendAudio,
    this.onEmojiTap,
    this.emojiPanelOpen = false,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _audioService = AudioService.instance;

  bool _isRecording = false;
  bool _cancelMode  = false;
  double _slideX    = 0;    // px сдвига влево (≤ 0)
  bool _pressing    = false; // палец нажат, но long-press ещё не сработал

  // ── Закрепление записи (свайп вверх → фиксируем, отпускаем кнопку) ──────
  bool   _locked     = false; // запись закреплена
  double _lockSlideY = 0;     // px сдвига вверх (≤ 0, ≥ -60)

  Timer? _recordTimer;
  int   _recordedSeconds = 0;

  // Показывать кнопку «Отправить / ✓» или кнопку «🎤»
  bool get _showSendBtn =>
      (widget.controller.text.trim().isNotEmpty || widget.isEditing) &&
      !_isRecording;

  String get _recordTime {
    final m = _recordedSeconds ~/ 60;
    final s = (_recordedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(MessageInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _recordTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  // ── Жесты на кнопке микрофона ────────────────────────────────────────────
  //
  // ВАЖНО: GestureDetector кнопки 🎤 должен оставаться в дереве на протяжении
  // всего жеста. Поэтому он рендерится в ветке `else` (когда `_showSendBtn`
  // ложен), которая НЕ меняется во время записи (текст не набирается,
  // пока палец удерживает кнопку).

  Future<void> _onLongPressStart(LongPressStartDetails _) async {
    if (widget.onSendAudio == null) return;
    setState(() => _pressing = false);
    try {
      await _audioService.startRecording();
    } catch (_) {
      if (mounted) _showMicError();
      return;
    }
    if (!mounted) return;
    _recordedSeconds = 0;
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordedSeconds++);
    });
    setState(() {
      _isRecording = true;
      _cancelMode  = false;
      _slideX      = 0;
      _locked      = false;
      _lockSlideY  = 0;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (!_isRecording || _locked) return;
    final dx = d.offsetFromOrigin.dx.clamp(-160.0, 0.0);
    final dy = d.offsetFromOrigin.dy; // отрицательное = вверх

    // Свайп вверх на 60 px → закрепляем запись
    if (dy < -60) {
      setState(() {
        _locked     = true;
        _lockSlideY = 0;
        _cancelMode = false;
        _slideX     = 0;
      });
      return;
    }
    setState(() {
      _lockSlideY = dy.clamp(-60.0, 0.0);
      _slideX     = dx;
      _cancelMode = _slideX < -72;
    });
  }

  /// Отпускание кнопки — если запись закреплена, продолжаем; иначе завершаем.
  Future<void> _onLongPressEnd(LongPressEndDetails _) async {
    if (_locked) return; // продолжаем запись
    await _finish(cancel: _cancelMode);
  }

  Future<void> _onLongPressCancel() async {
    setState(() => _pressing = false);
    if (_isRecording && !_locked) await _finish(cancel: true);
  }

  Future<void> _finish({required bool cancel}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    try {
      if (cancel) {
        await _audioService.cancelRecording();
      } else {
        final res = await _audioService.stopRecording();
        if (res != null && widget.onSendAudio != null && mounted) {
          await widget.onSendAudio!(res.path, res.durationMs);
        }
      }
    } finally {
      // Сбрасываем UI в любом случае — даже если выброшено исключение,
      // чтобы пользователь не застрял в режиме записи.
      if (mounted) {
        setState(() {
          _isRecording = false;
          _cancelMode  = false;
          _slideX      = 0;
          _locked      = false;
          _lockSlideY  = 0;
        });
      }
    }
  }

  void _showMicError() =>   AppSnack.error(context, 'Нет доступа к микрофону');

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).cardColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Левая кнопка: прикрепить / удалить запись ──────────────────
          if (!widget.isEditing)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isRecording
                  ? GestureDetector(
                      key: const ValueKey('del'),
                      onTap: () => _finish(cancel: true),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.delete_outline,
                          color: _cancelMode ? Colors.red : AppColors.subtle,
                          size: 26,
                        ),
                      ),
                    )
                  : IconButton(
                      key: const ValueKey('attach'),
                      icon: const Icon(Icons.attach_file, color: AppColors.subtle),
                      onPressed: widget.onAttach,
                      splashRadius: 20,
                    ),
            ),

          // ── Поле ввода / индикатор записи ──────────────────────────────
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: _isRecording
                  ? _RecordingContent(
                      recordTime: _recordTime,
                      slideX: _slideX,
                      cancelMode: _cancelMode,
                      locked: _locked,
                    )
                  : Focus(
                      // Ctrl+Enter → новая строка; Enter → отправить.
                      // Работает только на десктопе (физическая клавиатура).
                      // На мобильных onKeyEvent не вызывается для виртуальной
                      // клавиатуры, поэтому поведение там не меняется.
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent) return KeyEventResult.ignored;
                        if (event.logicalKey != LogicalKeyboardKey.enter) {
                          return KeyEventResult.ignored;
                        }
                        final isCtrl = HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed; // macOS Cmd
                        final isShift = HardwareKeyboard.instance.isShiftPressed;
                        if (!isCtrl && !isShift) return KeyEventResult.ignored; // → onSubmitted
                        // Ctrl+Enter: вставляем перенос строки в позицию курсора
                        final ctrl = widget.controller;
                        final sel  = ctrl.selection;
                        if (!sel.isValid) return KeyEventResult.ignored;
                        final before = ctrl.text.substring(0, sel.start);
                        final after  = ctrl.text.substring(sel.end);
                        ctrl.value = TextEditingValue(
                          text: '$before\n$after',
                          selection: TextSelection.collapsed(
                            offset: sel.start + 1,
                          ),
                        );
                        return KeyEventResult.handled;
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: widget.controller,
                              onSubmitted: (_) => widget.onSend(),
                              textInputAction: TextInputAction.send,
                              maxLines: null,
                              minLines: 1,
                              decoration: const InputDecoration(
                                hintText: 'Сообщение',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          // Кнопка эмодзи / GIF
                          if (widget.onEmojiTap != null)
                            GestureDetector(
                              onTap: widget.onEmojiTap,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 2, 8),
                                child: Text(
                                  '😊',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: widget.emojiPanelOpen
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Правая кнопка: отправить текст ИЛИ микрофон ───────────────
          //
          // Ветки `if`/`else` намеренно разделены, чтобы GestureDetector
          // микрофона всегда находился в одной позиции дерева во время
          // жеста записи (иначе Flutter прерывает long-press).
          if (_showSendBtn)
            // Обычная кнопка — без long-press, без задержки
            CircleAvatar(
              backgroundColor: Theme.of(context).extension<CustomChatTheme>()?.sendButtonColor ?? Theme.of(context).colorScheme.primary,
              child: IconButton(
                icon: Icon(
                  widget.isEditing ? Icons.check : Icons.send,
                  color: AppColors.textLight,
                  size: 20,
                ),
                onPressed: widget.onSend,
              ),
            )
          else if (_isRecording && _locked)
            // ── LOCKED: кнопка «Отправить» ─────────────────────────────────
            GestureDetector(
              onTap: () => _finish(cancel: false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48, height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red,
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            )
          else
            // ── Кнопка микрофона + замок над ней ───────────────────────────
            // Остаётся в дереве ВСЁ время жеста (иначе Flutter прерывает long-press).
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onTapDown:        (_) => setState(() => _pressing = true),
                  onTapUp:          (_) => setState(() => _pressing = false),
                  onTapCancel:      ()  => setState(() => _pressing = false),
                  onTap:            ()  => setState(() => _pressing = false),
                  onLongPressStart:      _onLongPressStart,
                  onLongPressMoveUpdate: _onLongPressMoveUpdate,
                  onLongPressEnd:        _onLongPressEnd,
                  onLongPressCancel:     _onLongPressCancel,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? (_cancelMode
                              ? Colors.red
                              : Colors.red.shade400)
                          : (_pressing
                              ? (Theme.of(context).extension<CustomChatTheme>()?.sendButtonColor
                                    ?? Theme.of(context).colorScheme.primary)
                                  .withAlpha(200)
                              : (Theme.of(context).extension<CustomChatTheme>()?.sendButtonColor
                                    ?? Theme.of(context).colorScheme.primary)),
                    ),
                    child: Icon(
                      Icons.mic,
                      color: Colors.white,
                      size: _isRecording ? 26 : 22,
                    ),
                  ),
                ),

                // Иконка замка — появляется при начале записи
                if (_isRecording)
                  Positioned(
                    bottom: 54 + (-_lockSlideY * 0.5),
                    child: _LockIndicator(
                      progress: (-_lockSlideY / 60).clamp(0.0, 1.0),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Контент внутри поля во время записи ────────────────────────────────────

class _RecordingContent extends StatefulWidget {
  final String recordTime;
  final double slideX;
  final bool   cancelMode;
  final bool   locked;

  const _RecordingContent({
    required this.recordTime,
    required this.slideX,
    required this.cancelMode,
    required this.locked,
  });

  @override
  State<_RecordingContent> createState() => _RecordingContentState();
}

class _RecordingContentState extends State<_RecordingContent> {
  // Кольцевой буфер амплитуд — последние 40 отсчётов (обновляются каждые 100 мс)
  final _amps = List<double>.filled(40, 0.0);
  StreamSubscription<double>? _ampSub;

  @override
  void initState() {
    super.initState();
    _ampSub = AudioService.instance.onAmplitude.listen((v) {
      if (!mounted) return;
      setState(() {
        _amps.removeAt(0);
        _amps.add(v);
      });
    });
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final cancelProg = widget.locked
        ? 0.0
        : (-widget.slideX / 72).clamp(0.0, 1.0);
    final hintColor =
        Color.lerp(AppColors.subtle, Colors.red, cancelProg)!;

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          // Мигающая точка
          const _RecordingDot(),
          const SizedBox(width: 8),

          // Таймер
          Text(
            widget.recordTime,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 10),

          // Осциллограмма
          Expanded(
            child: _WaveformBars(amplitudes: _amps, color: primary),
          ),

          // Правая часть: замок или подсказка отмены
          if (widget.locked)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.lock_rounded, size: 15, color: primary),
            )
          else
            Transform.translate(
              offset: Offset(widget.slideX * 0.30, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, color: hintColor, size: 15),
                  Text(
                    widget.cancelMode ? 'Отпустить — отмена' : 'Отмена',
                    style: TextStyle(fontSize: 11, color: hintColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Осциллограмма записи ────────────────────────────────────────────────────

class _WaveformBars extends StatelessWidget {
  final List<double> amplitudes;
  final Color color;

  const _WaveformBars({required this.amplitudes, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      const barW = 2.5;
      const gap  = 1.5;
      final maxBars = (constraints.maxWidth / (barW + gap)).floor().clamp(1, amplitudes.length);
      final visible = amplitudes.skip(amplitudes.length - maxBars).toList();
      final n = visible.length;

      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(n, (i) {
          final amp = visible[i];
          final age  = (n - 1 - i) / n; // 0 = newest, 1 = oldest
          final h    = (amp * 30 + 3).clamp(3.0, 32.0);
          return Container(
            width: barW,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: gap / 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25 + 0.75 * (1 - age)),
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      );
    });
  }
}

// ─── Индикатор замка над кнопкой микрофона ───────────────────────────────────

class _LockIndicator extends StatelessWidget {
  /// 0.0 = открыт (свайп не начат), 1.0 = закрыт (порог достигнут)
  final double progress;

  const _LockIndicator({required this.progress});

  @override
  Widget build(BuildContext context) {
    final primary  = Theme.of(context).colorScheme.primary;
    final cardColor = Theme.of(context).cardColor;
    final locked   = progress > 0.85;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 34, height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: locked ? primary : cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        locked ? Icons.lock_rounded : Icons.lock_open_rounded,
        size: 16,
        color: locked ? Colors.white : AppColors.subtle,
      ),
    );
  }
}

// ─── Анимированная точка записи (мигает красным) ─────────────────────────────

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _ctrl,
    child: Container(
      width: 10, height: 10,
      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    ),
  );
}

// ─── Индикатор редактирования над полем ввода ────────────────────────────────

class _EditingIndicator extends StatelessWidget {
  final Message message;
  final VoidCallback onCancel;

  const _EditingIndicator({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Редактирование',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppColors.subtle),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// ─── Заглушка для не-админов в сообществе ────────────────────────────────────

class _LockedInput extends StatelessWidget {
  const _LockedInput();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      color: Theme.of(context).cardColor,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 16, color: AppColors.subtle),
          SizedBox(width: 6),
          Text(
            'Только администратор может писать',
            style: TextStyle(color: AppColors.subtle, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Полноэкранный просмотр медиа (Telegram-style) ─────────────────────────

class MediaViewerScreen extends StatefulWidget {
  final Attachment attachment;
  final List<Attachment> allMedia;
  final int initialIndex;

  const MediaViewerScreen({
    super.key,
    required this.attachment,
    this.allMedia = const [],
    this.initialIndex = 0,
  });

  static void open(BuildContext context, Attachment attachment,
      {List<Attachment> allMedia = const []}) {
    int idx = allMedia.indexWhere((a) => a.path == attachment.path);
    if (idx < 0) idx = 0;
    final media = allMedia.isNotEmpty ? allMedia : [attachment];
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) =>
            MediaViewerScreen(attachment: attachment, allMedia: media, initialIndex: idx),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

// ═══════════════════════════════════════════════════════════════════════════
// VIDEO PLAYER — video_player package (Android / iOS / Web / Windows / macOS)
// ═══════════════════════════════════════════════════════════════════════════
class _MediaViewerScreenState extends State<MediaViewerScreen>
    with WidgetsBindingObserver {
  late int _currentPage;
  late ScrollController _thumbScrollCtrl;

  // ── video_player ──────────────────────────────────────────────────────
  VideoPlayerController? _vpc;
  bool _vpReady = false;
  bool _vpError = false;
  String? _vpErrorMsg;

  // ── Controls overlay ──────────────────────────────────────────────────
  bool _showControls = true;
  Timer? _controlsTimer;
  bool _isFullscreen = false;

  // ── Volume (desktop only) ─────────────────────────────────────────────
  bool _showVolumeSlider = false;
  // Инициализируется в initState из VolumeService (по умолчанию 0.7).
  double _volume = VolumeService.defaultVolume;

  // ── Playback speed ────────────────────────────────────────────────────
  static const List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  int _speedIdx = 2; // 1.0× by default

  // ── Seek drag ─────────────────────────────────────────────────────────
  bool _isDragging = false;
  double _dragValue = 0.0;

  // ── Double-tap seek indicator ─────────────────────────────────────────
  // null = hidden; true = forward (+10s); false = backward (-10s)
  bool? _seekIndicatorForward;
  Timer? _seekIndicatorTimer;

  Attachment get _att => widget.allMedia[_currentPage];
  bool get _isVideo => _att.type == AttachmentType.video;
  bool get _hasMultiple => widget.allMedia.length > 1;
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  // video_player has no Windows/Linux plugin → use media_kit there instead
  bool get _useMediaKit =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  // ── media_kit state (Windows / Linux only) ────────────────────────────
  Player? _mkPlayer;
  VideoController? _mkController;
  StreamSubscription<Duration>? _mkPosSub;

  @override
  void initState() {
    super.initState();
    _volume = VolumeService.instance.volume; // восстанавливаем сохранённую громкость
    _currentPage = widget.initialIndex;
    _thumbScrollCtrl = ScrollController();
    WidgetsBinding.instance.addObserver(this);
    if (_isVideo) _initVideo();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollThumbToView());
  }

  // Автопауза при уходе приложения в фон.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_isPlaying) {
        if (_useMediaKit) {
          _mkPlayer?.pause();
        } else {
          _vpc?.pause();
        }
      }
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────
  void _goTo(int index) {
    if (index < 0 || index >= widget.allMedia.length || index == _currentPage) return;
    _disposeVideo();
    setState(() {
      _currentPage = index;
      _vpReady = false;
      _vpError = false;
      _vpErrorMsg = null;
      _isDragging = false;
      _showControls = true;
    });
    if (_isVideo) _initVideo();
    _scrollThumbToView();
  }

  void _scrollThumbToView() {
    if (!_hasMultiple || !_thumbScrollCtrl.hasClients) return;
    const thumbW = 72.0;
    final target = _currentPage * thumbW - (_thumbScrollCtrl.position.viewportDimension / 2) + thumbW / 2;
    _thumbScrollCtrl.animateTo(
      target.clamp(0, _thumbScrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  // ── Video lifecycle ───────────────────────────────────────────────────

  Future<void> _initVideo() async {
    if (_useMediaKit) {
      await _initVideoMediaKit();
    } else {
      await _initVideoPlayer();
    }
  }

  /// video_player backend — Android / iOS / macOS / Web
  Future<void> _initVideoPlayer() async {
    final path = _att.path;
    VideoPlayerController vpc;
    if (kIsWeb || ApiConfig.isServerMediaPath(path)) {
      final url = ApiConfig.isServerMediaPath(path)
          ? ApiConfig.resolveMediaUrl(path)!
          : path;
      vpc = VideoPlayerController.networkUrl(Uri.parse(url));
    } else {
      vpc = VideoPlayerController.file(File(path));
    }
    _vpc = vpc;
    vpc.addListener(_onVpcUpdate);
    try {
      await vpc.initialize();
      if (!mounted || _vpc != vpc) {
        vpc.removeListener(_onVpcUpdate);
        vpc.dispose();
        return;
      }
      setState(() { _vpReady = true; _speedIdx = 2; });
      await vpc.setPlaybackSpeed(_speeds[_speedIdx]);
      await vpc.setVolume(_volume);
      await vpc.play();
      _scheduleHideControls();
    } catch (e) {
      if (!mounted) return;
      setState(() { _vpError = true; _vpErrorMsg = e.toString(); });
    }
  }

  /// media_kit backend — Windows / Linux
  Future<void> _initVideoMediaKit() async {
    final path = _att.path;
    final source = ApiConfig.isServerMediaPath(path)
        ? ApiConfig.resolveMediaUrl(path)!
        : path;
    try {
      final player = Player();
      final controller = VideoController(player);
      _mkPlayer = player;
      _mkController = controller;

      StreamSubscription<String>? errorSub;
      errorSub = player.stream.error.listen((err) {
        if (mounted) setState(() { _vpError = true; _vpErrorMsg = err; });
      });

      await player.open(Media(source), play: false);
      errorSub.cancel();

      if (!mounted || _mkPlayer != player) return;

      setState(() { _vpReady = true; _speedIdx = 2; });
      await player.setRate(_speeds[_speedIdx]);
      await player.setVolume(_volume * 100);

      // Drive UI rebuilds from position stream (~100 ms cadence)
      _mkPosSub = player.stream.position.listen((_) {
        if (mounted) setState(() {});
      });

      player.play();
      _scheduleHideControls();
    } catch (e) {
      if (!mounted) return;
      setState(() { _vpError = true; _vpErrorMsg = e.toString(); });
    }
  }

  void _disposeVideo() {
    _controlsTimer?.cancel();
    _controlsTimer = null;
    // video_player
    final vpc = _vpc;
    if (vpc != null) {
      vpc.removeListener(_onVpcUpdate);
      vpc.dispose();
      _vpc = null;
    }
    // media_kit
    _mkPosSub?.cancel();
    _mkPosSub = null;
    _mkPlayer?.dispose();
    _mkPlayer = null;
    _mkController = null;

    _vpReady = false;
    _vpError = false;
    _vpErrorMsg = null;
  }

  void _onVpcUpdate() {
    if (mounted) setState(() {});
  }

  // ── Controls auto-hide ────────────────────────────────────────────────

  bool get _isPlaying => _useMediaKit
      ? (_mkPlayer?.state.playing ?? false)
      : (_vpc?.value.isPlaying ?? false);

  void _scheduleHideControls() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && _isPlaying) {
      _scheduleHideControls();
    } else {
      _controlsTimer?.cancel();
    }
  }

  /// Double-tap на левую/правую половину экрана — перемотка ±10 с.
  void _onDoubleTap(bool forward) {
    final seconds = forward ? 10 : -10;
    if (_useMediaKit) {
      final pos = _mkPlayer!.state.position;
      final dur = _mkPlayer!.state.duration;
      final target = Duration(
          milliseconds: (pos.inMilliseconds + seconds * 1000)
              .clamp(0, dur.inMilliseconds));
      _mkPlayer!.seek(target);
    } else if (_vpc != null && _vpc!.value.isInitialized) {
      final pos = _vpc!.value.position;
      final dur = _vpc!.value.duration;
      final target = Duration(
          milliseconds: (pos.inMilliseconds + seconds * 1000)
              .clamp(0, dur.inMilliseconds));
      _vpc!.seekTo(target);
    }
    _seekIndicatorTimer?.cancel();
    setState(() => _seekIndicatorForward = forward);
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _seekIndicatorForward = null);
    });
    // После перемотки показываем контролы
    setState(() => _showControls = true);
    _scheduleHideControls();
  }

  // ── Playback ──────────────────────────────────────────────────────────

  void _togglePlay() {
    if (_useMediaKit) {
      final p = _mkPlayer;
      if (p == null) return;
      if (p.state.playing) {
        p.pause();
        _controlsTimer?.cancel();
        setState(() => _showControls = true);
      } else {
        if (p.state.completed) p.seek(Duration.zero);
        p.play();
        _scheduleHideControls();
      }
    } else {
      final vpc = _vpc;
      if (vpc == null || !vpc.value.isInitialized) return;
      if (vpc.value.isPlaying) {
        vpc.pause();
        _controlsTimer?.cancel();
        setState(() => _showControls = true);
      } else {
        if (vpc.value.position >= vpc.value.duration && vpc.value.duration > Duration.zero) {
          vpc.seekTo(Duration.zero);
        }
        vpc.play();
        _scheduleHideControls();
      }
    }
  }

  void _cycleSpeed() {
    setState(() => _speedIdx = (_speedIdx + 1) % _speeds.length);
    final speed = _speeds[_speedIdx];
    if (_useMediaKit) {
      _mkPlayer?.setRate(speed);
    } else {
      _vpc?.setPlaybackSpeed(speed);
    }
  }

  // ── Fullscreen ────────────────────────────────────────────────────────

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      _showControls = true;
    });
    if (!kIsWeb) {
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
        if (!_isDesktop) {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        if (!_isDesktop) {
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        }
      }
    }
    if (_isFullscreen && (_vpc?.value.isPlaying ?? false)) {
      _scheduleHideControls();
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _seekIndicatorTimer?.cancel();
    _disposeVideo();
    _thumbScrollCtrl.dispose();
    if (!kIsWeb && !_isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Fullscreen: only the video area fills the whole screen
    if (_isFullscreen) {
      return Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _buildVideoArea(),
        ),
      );
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: _isVideo ? Colors.black : Colors.transparent,
        body: _isVideo
            ? _buildViewerBody()
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.84),
                  child: _buildViewerBody(),
                ),
              ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_isFullscreen) {
        _toggleFullscreen();
      } else {
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (_isVideo && (_vpc != null || _mkPlayer != null)) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        final pos = _useMediaKit ? _mkPlayer!.state.position : _vpc!.value.position;
        final dur = _useMediaKit ? _mkPlayer!.state.duration.inSeconds : _vpc!.value.duration.inSeconds;
        final target = Duration(seconds: (pos.inSeconds - 10).clamp(0, dur));
        if (_useMediaKit) _mkPlayer!.seek(target); else _vpc!.seekTo(target);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        final pos = _useMediaKit ? _mkPlayer!.state.position : _vpc!.value.position;
        final dur = _useMediaKit ? _mkPlayer!.state.duration.inSeconds : _vpc!.value.duration.inSeconds;
        final target = Duration(seconds: (pos.inSeconds + 10).clamp(0, dur));
        if (_useMediaKit) _mkPlayer!.seek(target); else _vpc!.seekTo(target);
        return KeyEventResult.handled;
      }
    } else {
      if (key == LogicalKeyboardKey.arrowLeft) { _goTo(_currentPage - 1); return KeyEventResult.handled; }
      if (key == LogicalKeyboardKey.arrowRight) { _goTo(_currentPage + 1); return KeyEventResult.handled; }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildViewerBody() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(child: _buildMainContent()),
        if (_hasMultiple) _buildThumbStrip(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _att.fileName,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_hasMultiple)
                  Text(
                    '${_currentPage + 1} из ${widget.allMedia.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white70),
              tooltip: 'Сохранить',
              onPressed: () => showSaveOptions(context, _att),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Stack(
      children: [
        _isVideo ? _buildVideoArea() : _buildImageArea(),
        // Navigation arrows: desktop only, not in fullscreen
        if (_hasMultiple && _isDesktop) ...[
          if (_currentPage > 0)
            Positioned(
              left: 12, top: 0, bottom: 0,
              child: Center(child: _NavArrow(icon: Icons.chevron_left, onTap: () => _goTo(_currentPage - 1))),
            ),
          if (_currentPage < widget.allMedia.length - 1)
            Positioned(
              right: 12, top: 0, bottom: 0,
              child: Center(child: _NavArrow(icon: Icons.chevron_right, onTap: () => _goTo(_currentPage + 1))),
            ),
        ],
      ],
    );
  }

  // ── Image area ────────────────────────────────────────────────────────

  Widget _buildImageArea() {
    final path = _att.path;
    final img = ApiConfig.isServerMediaPath(path)
        ? Image.network(
            ApiConfig.resolveMediaUrl(path)!,
            fit: BoxFit.contain,
            loadingBuilder: (ctx, child, p) => p == null
                ? child
                : Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
            errorBuilder: (ctx, e, s) =>
                const Icon(Icons.broken_image, color: Colors.white38, size: 64),
          )
        : Image.file(File(path), fit: BoxFit.contain,
            errorBuilder: (ctx, e, s) =>
                const Icon(Icons.broken_image, color: Colors.white38, size: 64));

    if (!_isDesktop && _hasMultiple) {
      return GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -200) _goTo(_currentPage + 1);
          if (details.primaryVelocity! > 200) _goTo(_currentPage - 1);
        },
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5, maxScale: 6.0,
            child: Hero(tag: 'media_$path', child: img),
          ),
        ),
      );
    }
    return Center(
      child: InteractiveViewer(
        minScale: 0.5, maxScale: 6.0,
        child: Hero(tag: 'media_$path', child: img),
      ),
    );
  }

  // ── Video area (Telegram-like overlay player) ─────────────────────────

  Widget _buildVideoArea() {
    if (_vpError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 64),
            const SizedBox(height: 12),
            const Text('Ошибка воспроизведения',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 4),
            if (_vpErrorMsg != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _vpErrorMsg!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
        ),
      );
    }

    if (!_vpReady || (_vpc == null && _mkController == null)) {
      // Пока видео инициализируется — показываем серверное превью.
      final thumbUrl = ApiConfig.resolveMediaUrl(_att.thumbnailPath);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumbUrl != null)
            Image.network(thumbUrl, fit: BoxFit.cover, gaplessPlayback: true)
          else
            const ColoredBox(color: Colors.black),
          Center(
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Tap/double-tap handler ──
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video frame ──
              if (_useMediaKit)
                Video(controller: _mkController!, controls: NoVideoControls)
              else
                Center(
                  child: AspectRatio(
                    aspectRatio: _vpc!.value.aspectRatio,
                    child: VideoPlayer(_vpc!),
                  ),
                ),

              // ── Buffering spinner ──
              if (_useMediaKit)
                if (_mkPlayer!.state.buffering)
                  const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2))
                else
                  const SizedBox.shrink()
              else
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _vpc!,
                  builder: (_, val, __) => val.isBuffering
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white70, strokeWidth: 2))
                      : const SizedBox.shrink(),
                ),

              // ── Controls overlay (auto-hide with AnimatedOpacity) ──
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControlsOverlay(),
                ),
              ),
            ],
          ),
        ),

        // ── Double-tap зоны: левая −10с / правая +10с ──
        if (_vpReady)
          Row(
            children: [
              // Левая зона — -10 с
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () => _onDoubleTap(false),
                  child: const SizedBox.expand(),
                ),
              ),
              // Правая зона — +10 с
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: () => _onDoubleTap(true),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),

        // ── Seek indicator (ripple + текст) ──
        if (_seekIndicatorForward != null)
          AnimatedOpacity(
            opacity: _seekIndicatorForward != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: Align(
              alignment: _seekIndicatorForward!
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _SeekIndicator(forward: _seekIndicatorForward!),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControlsOverlay() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Bottom gradient: transparent → dark
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            height: 160,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xEE000000)],
              ),
            ),
          ),
        ),

        // Center play/pause button
        Center(child: _buildCenterButton()),

        // Bottom bar: progress + controls row
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _buildBottomBar(),
        ),
      ],
    );
  }

  Widget _buildCenterButton() {
    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.50),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white, size: 44,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressBar(),
          const SizedBox(height: 2),
          Row(
            children: [
              // Play / Pause
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 26,
                ),
                onPressed: _togglePlay,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 6),
              // Current / total time
              Text(
                '${_fmt(_useMediaKit ? _mkPlayer!.state.position : _vpc!.value.position)} / '
                '${_fmt(_useMediaKit ? _mkPlayer!.state.duration : _vpc!.value.duration)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Spacer(),
              // Speed selector (cycles on tap)
              GestureDetector(
                onTap: _cycleSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_speeds[_speedIdx]}×',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Volume control (desktop only)
              if (_isDesktop) ..._buildVolumeControl(),
              // Fullscreen toggle
              IconButton(
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white, size: 24,
                ),
                onPressed: _toggleFullscreen,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final dur = (_useMediaKit
            ? _mkPlayer!.state.duration
            : _vpc!.value.duration)
        .inMilliseconds
        .toDouble();
    final pos = (_useMediaKit
            ? _mkPlayer!.state.position
            : _vpc!.value.position)
        .inMilliseconds
        .toDouble();

    final sliderVal = _isDragging
        ? _dragValue
        : (dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0);

    // Buffered fraction
    double buffered = 0.0;
    if (_useMediaKit) {
      final buf = _mkPlayer!.state.buffer.inMilliseconds.toDouble();
      if (dur > 0) buffered = (buf / dur).clamp(0.0, 1.0);
    } else {
      for (final r in _vpc!.value.buffered) {
        if (dur > 0) {
          final end = (r.end.inMilliseconds / dur).clamp(0.0, 1.0);
          if (end > buffered) buffered = end;
        }
      }
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Buffered track (underneath)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: buffered,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white38),
              minHeight: 3,
            ),
          ),
        ),
        // Playback slider (on top)
        SliderTheme(
          data: SliderThemeData(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            trackHeight: 3,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Theme.of(context).colorScheme.primary,
            overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: sliderVal,
            onChangeStart: (v) =>
                setState(() { _isDragging = true; _dragValue = v; }),
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              if (dur > 0) {
                final target = Duration(milliseconds: (v * dur).round());
                if (_useMediaKit) {
                  _mkPlayer!.seek(target);
                } else {
                  _vpc!.seekTo(target);
                }
              }
              setState(() => _isDragging = false);
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildVolumeControl() {
    return [
      IconButton(
        icon: Icon(
          _volume == 0
              ? Icons.volume_off
              : (_volume < 0.5 ? Icons.volume_down : Icons.volume_up),
          color: Colors.white, size: 22,
        ),
        onPressed: () => setState(() => _showVolumeSlider = !_showVolumeSlider),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
      if (_showVolumeSlider)
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderThemeData(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              trackHeight: 2,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white38,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _volume,
              onChanged: (v) {
                setState(() => _volume = v);
                if (_useMediaKit) {
                  _mkPlayer?.setVolume(v * 100);
                } else {
                  _vpc?.setVolume(v);
                }
              },
              onChangeEnd: (v) => VolumeService.instance.save(v),
            ),
          ),
        ),
      const SizedBox(width: 4),
    ];
  }

  // ── Полоска миниатюр ──────────────────────────────────────────────────

  Widget _buildThumbStrip() {
    return Container(
      height: 64,
      color: const Color(0xFF1A1A1A),
      child: ListView.builder(
        controller: _thumbScrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: widget.allMedia.length,
        itemBuilder: (_, i) {
          final att = widget.allMedia[i];
          final selected = i == _currentPage;
          return GestureDetector(
            onTap: () => _goTo(i),
            child: Container(
              width: 64,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: selected
                    ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 4 : 6),
                child: _buildThumbContent(att),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThumbContent(Attachment att) {
    if (att.type == AttachmentType.video) {
      final thumbUrl = ApiConfig.resolveMediaUrl(att.thumbnailPath);
      if (thumbUrl != null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.network(thumbUrl, fit: BoxFit.cover, gaplessPlayback: true),
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 20),
            ),
          ],
        );
      }
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Icon(Icons.videocam, color: Colors.white38, size: 20),
        ),
      );
    }
    final path = att.path;
    if (ApiConfig.isServerMediaPath(path)) {
      return Image.network(
        ApiConfig.resolveMediaUrl(path)!,
        fit: BoxFit.cover,
        errorBuilder: (ctx, e, s) =>
            Container(color: Colors.grey[900], child: const Icon(Icons.image, color: Colors.white38, size: 20)),
      );
    }
    return Image.file(File(path), fit: BoxFit.cover,
        errorBuilder: (ctx, e, s) =>
            Container(color: Colors.grey[900], child: const Icon(Icons.image, color: Colors.white38, size: 20)));
  }
}

/// Стрелка навигации для десктопа.
class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

// ─── Bottom sheet комментариев ─────────────────────────────────────────────────

/// Показывает тред комментариев к [message] в модальном bottom sheet.
/// При отправке комментария вызывает [onSend] с текстом.
void showCommentsSheet({
  required BuildContext context,
  required Message message,
  required Future<Message?> Function(String text) onSend,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => _CommentsSheetContent(
        message: message,
        scrollController: scrollCtrl,
        onSend: onSend,
      ),
    ),
  );
}

class _CommentsSheetContent extends StatefulWidget {
  final Message message;
  final ScrollController scrollController;
  final Future<Message?> Function(String text) onSend;

  const _CommentsSheetContent({
    required this.message,
    required this.scrollController,
    required this.onSend,
  });

  @override
  State<_CommentsSheetContent> createState() => _CommentsSheetContentState();
}

class _CommentsSheetContentState extends State<_CommentsSheetContent> {
  final _controller = TextEditingController();
  late Message _message;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final updated = await widget.onSend(text);
    if (updated != null && mounted) {
      setState(() => _message = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = _message.comments;
    return Column(
      children: [
        // ── Хэндл ──────────────────────────────────────────
        const SizedBox(height: 8),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.mode_comment_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Комментарии (${comments.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
        const Divider(height: 16),
        // ── Исходное сообщение (превью) ────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            widget.message.text.length > 200
                ? '${widget.message.text.substring(0, 200)}…'
                : widget.message.text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        // ── Список комментариев (Telegram-стиль) ───────────
        Expanded(
          child: comments.isEmpty
              ? const Center(
                  child: Text('Пока нет комментариев',
                      style: TextStyle(color: AppColors.subtle)),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  itemCount: comments.length,
                  itemBuilder: (ctx, i) {
                    final c = comments[i];
                    final isDark =
                        Theme.of(ctx).brightness == Brightness.dark;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Аватар
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: c.isMe
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                            child: Text(
                              c.senderName.isNotEmpty
                                  ? c.senderName[0]
                                  : '?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: c.isMe
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Пузырь сообщения
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 8, 12, 6),
                              decoration: BoxDecoration(
                                color: c.isMe
                                    ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.15)
                                    : isDark
                                        ? Colors.white
                                            .withValues(alpha: 0.08)
                                        : const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomRight: const Radius.circular(14),
                                  bottomLeft: const Radius.circular(4),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  // Имя отправителя
                                  Text(
                                    c.senderName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: _senderColor(c.senderName),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  // Текст + время
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Flexible(
                                        child: Text(c.text,
                                            style: const TextStyle(
                                                fontSize: 14)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        formatTime(c.time),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.subtle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        // ── Поле ввода ─────────────────────────────────────
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Написать комментарий…',
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Карточка-приглашение в группу (Discord-style) ──────────────────────────

class _GroupInviteCard extends StatefulWidget {
  final GroupInvite invite;
  final bool isMe;
  /// null — кнопка «Принять» недоступна (не передан колбэк).
  final VoidCallback? onAccept;

  const _GroupInviteCard({
    required this.invite,
    required this.isMe,
    this.onAccept,
  });

  @override
  State<_GroupInviteCard> createState() => _GroupInviteCardState();
}

class _GroupInviteCardState extends State<_GroupInviteCard> {
  bool _joining = false;

  Future<void> _handleAccept() async {
    if (widget.onAccept == null || _joining) return;
    setState(() => _joining = true);
    try {
      widget.onAccept!();
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invite = widget.invite;
    final isMe = widget.isMe;

    final typeLabel = switch (invite.chatType) {
      ChatType.community => 'Сообщество',
      ChatType.group     => 'Группа',
      _                  => 'Группа',
    };

    // Цвета адаптируются под сторону пузыря
    final borderColor = isMe
        ? Colors.white.withValues(alpha: 0.25)
        : theme.colorScheme.outline.withValues(alpha: 0.35);
    final nameColor   = isMe ? Colors.white        : theme.colorScheme.onSurface;
    final metaColor   = isMe ? Colors.white60      : theme.hintColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
        color: isMe
            ? Colors.black.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        // mainAxisSize.max — пузырь имеет фиксированную ширину, Flexible корректно
        // получает оставшееся пространство. mainAxisSize.min здесь нельзя использовать
        // т.к. IntrinsicWidth посчитает ширину без Flexible-столбца и текст исчезнет.
        children: [
          // ── Аватар ────────────────────────────────────
          ChatAvatar(
            type: invite.chatType,
            radius: 18,
            avatarPath: invite.avatarPath,
            chatName: invite.chatName,
          ),
          const SizedBox(width: 9),
          // ── Название + мета ───────────────────────────
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  invite.chatName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: nameColor,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$typeLabel · ${invite.memberCount} уч.',
                  style: TextStyle(fontSize: 11, color: metaColor, height: 1.2),
                ),
              ],
            ),
          ),
          // ── Кнопка «Вступить» (только у получателя) ──
          if (!isMe) ...[
            const SizedBox(width: 10),
            _JoinPill(joining: _joining, onTap: _handleAccept),
          ],
        ],
      ),
    );
  }
}

/// Компактная пилюля «Вступить →» / индикатор загрузки.
class _JoinPill extends StatelessWidget {
  final bool joining;
  final VoidCallback onTap;

  const _JoinPill({required this.joining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: joining ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: joining
              ? primary.withValues(alpha: 0.4)
              : primary,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: joining
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Вступить',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.white),
                ],
              ),
      ),
    );
  }
}

// ─── Индикатор перемотки (double-tap) ────────────────────────────────────────

class _SeekIndicator extends StatefulWidget {
  final bool forward;
  const _SeekIndicator({required this.forward});
  @override
  State<_SeekIndicator> createState() => _SeekIndicatorState();
}

class _SeekIndicatorState extends State<_SeekIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.forward
                  ? Icons.forward_10_rounded
                  : Icons.replay_10_rounded,
              color: Colors.white,
              size: 36,
            ),
            Text(
              widget.forward ? '+10с' : '−10с',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Реэкспорт вспомогательных элементов для экранов ────────────────────────

// Открываем внутренние виджеты, необходимые chat_screen.dart
// ignore: library_private_types_in_public_api
typedef EditingIndicator = _EditingIndicator;
// ignore: library_private_types_in_public_api
typedef LockedInput = _LockedInput;
