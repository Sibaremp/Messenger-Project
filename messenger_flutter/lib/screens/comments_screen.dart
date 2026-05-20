import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/api_config.dart' show ApiConfig;
import '../widgets/chat_widgets.dart'
    show MediaViewerScreen, ChannelPostCard, MessageBubble, MessageInput;
import '../widgets/emoji_gif_panel.dart';
import '../utils/profanity_filter.dart';
import 'chat_screen.dart' show MediaPreviewPage, MultiMediaPreviewDialog, MultiMediaResult;
import '../utils/app_snack.dart';
import '../l10n/app_localizations.dart';

/// Полноэкранный раздел комментариев к посту.
class CommentsScreen extends StatefulWidget {
  final Message message;
  final Chat chat;
  final ChatService service;
  final Future<Message?> Function(String text,
      {Attachment? attachment, ReplyInfo? replyTo}) onSend;
  final Future<Message?> Function(String commentId, String newText)? onEdit;
  final Future<Message?> Function(List<String> commentIds)? onDelete;
  final bool embedded;
  final VoidCallback? onBack;
  final String? currentUserName;

  const CommentsScreen({
    super.key,
    required this.message,
    required this.chat,
    required this.service,
    required this.onSend,
    this.onEdit,
    this.onDelete,
    this.embedded = false,
    this.onBack,
    this.currentUserName,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _controller      = TextEditingController();
  final _scrollController = ScrollController();
  late Message _message;

  Comment? _replyingTo;
  Comment? _editingComment;
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  // ── Панель эмодзи / GIF ───────────────────────────────
  bool _showEmojiPanel  = false;
  // ── Попап вложений (Telegram-style) ──────────────────
  bool _attachMenuOpen  = false;

  // ── Toast цензуры ─────────────────────────────────────
  bool   _censorToastVisible = false;
  String _censorToastMsg     = '';
  Timer? _censorTimer;

  void _showCensorToast(String message) {
    _censorTimer?.cancel();
    setState(() { _censorToastMsg = message; _censorToastVisible = true; });
    _censorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _censorToastVisible = false);
    });
  }

  static const _nameColors = [
    Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2), Color(0xFFE64A19),
    Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC2185B), Color(0xFF455A64),
  ];

  Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
    return _nameColors[hash.abs() % _nameColors.length];
  }

  Message _commentToMessage(Comment c, bool isMe) => Message(
    id: c.id,
    text: c.text,
    isMe: isMe,
    time: c.time,
    senderName: c.senderName,
    senderDisplayName: c.senderDisplayName,
    senderGroup: c.senderGroup,
    attachment: c.attachment,
    isEdited: c.isEdited,
    replyTo: c.replyTo,
  );

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(covariant CommentsScreen old) {
    super.didUpdateWidget(old);
    if (widget.message != old.message) _message = widget.message;
  }

  @override
  void dispose() {
    _censorTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  // ── Эмодзи / GIF ─────────────────────────────────────
  void _toggleEmojiPanel() =>
      setState(() { _showEmojiPanel = !_showEmojiPanel; _attachMenuOpen = false; });

  void _insertEmoji(String emoji) {
    final ctrl = _controller;
    final pos  = ctrl.selection.isValid ? ctrl.selection.baseOffset : ctrl.text.length;
    final newText = ctrl.text.substring(0, pos) + emoji + ctrl.text.substring(pos);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + emoji.length),
    );
  }

  Future<void> _sendGif(String gifUrl) async {
    setState(() { _showEmojiPanel = false; });
    final reply = _replyingTo != null
        ? ReplyInfo(
            messageId: _replyingTo!.id,
            senderName: _replyingTo!.senderName,
            text: _replyingTo!.text,
          )
        : null;
    setState(() => _replyingTo = null);
    final updated = await widget.onSend(
      Message.gifText(gifUrl),
      replyTo: reply,
    );
    if (updated != null && mounted) {
      setState(() => _message = updated);
      _scrollToEnd();
    }
  }

  // ── Попап вложений ────────────────────────────────────
  void _toggleAttachMenu() =>
      setState(() { _attachMenuOpen = !_attachMenuOpen; _showEmojiPanel = false; });
  void _closeAttachMenu() {
    if (_attachMenuOpen) setState(() => _attachMenuOpen = false);
  }

  // ── Отправка / редактирование ────────────────────────
  void _sendOrEdit({Attachment? attachment}) {
    if (_showEmojiPanel) setState(() => _showEmojiPanel = false);
    _editingComment != null ? _saveEdit() : _sendComment(attachment: attachment);
  }

  Future<void> _sendComment({Attachment? attachment}) async {
    final rawText = _controller.text.trim();
    if (rawText.isEmpty && attachment == null) return;
    _controller.clear();
    final text = widget.chat.isAcademic
        ? ProfanityFilter.censor(rawText)
        : rawText;
    if (widget.chat.isAcademic && text != rawText && mounted) {
      _showCensorToast(context.l10n.censoredComment);
    }
    final reply = _replyingTo != null
        ? ReplyInfo(
            messageId: _replyingTo!.id,
            senderName: _replyingTo!.senderName,
            text: _replyingTo!.text,
          )
        : null;
    final updated = await widget.onSend(text, attachment: attachment, replyTo: reply);
    if (updated != null && mounted) {
      setState(() { _message = updated; _replyingTo = null; });
      _scrollToEnd();
    }
  }

  /// Голосовой комментарий.
  Future<void> _sendAudioComment(String path, int durationMs) async {
    await _sendComment(attachment: Attachment(
      path: path,
      type: AttachmentType.audio,
      fileName: path.split('/').last,
      durationMs: durationMs,
    ));
  }

  void _startReply(Comment c) =>
      setState(() { _replyingTo = c; _editingComment = null; });
  void _cancelReply() => setState(() => _replyingTo = null);

  void _startEdit(Comment c) {
    setState(() { _editingComment = c; _replyingTo = null; });
    _controller.text = c.text;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
  }

  Future<void> _saveEdit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _editingComment == null) return;
    final id = _editingComment!.id;
    setState(() => _editingComment = null);
    _controller.clear();
    if (widget.onEdit != null) {
      final updated = await widget.onEdit!(id, text);
      if (updated != null && mounted) setState(() => _message = updated);
    }
  }

  void _cancelEdit() { setState(() => _editingComment = null); _controller.clear(); }

  Future<void> _deleteComment(Comment c) async {
    final updated = await widget.onDelete?.call([c.id]);
    if (updated != null && mounted) setState(() => _message = updated);
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    final updated = await widget.onDelete?.call(ids);
    if (updated != null && mounted) setState(() => _message = updated);
  }

  // ── Пересылка ─────────────────────────────────────────
  void _forwardComment(Comment c) => _showForwardDialog([c]);
  void _forwardSelected() {
    final list = _message.comments.where((c) => _selectedIds.contains(c.id)).toList();
    _exitSelectionMode();
    _showForwardDialog(list);
  }

  Future<void> _showForwardDialog(List<Comment> list) async {
    final all = await widget.service.loadChats();
    if (!mounted) return;
    final others = all.where((c) => c.id != widget.chat.id).toList();
    if (others.isEmpty) {
      AppSnack.warn(context, context.l10n.noChatsForForward);
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(alignment: Alignment.centerLeft,
              child: Text(context.l10n.forwardTo,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ),
          ...others.map((ch) => ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              child: Text(ch.name.isNotEmpty ? ch.name[0] : '?',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            ),
            title: Text(ch.name),
            onTap: () async {
              Navigator.pop(context);
              for (final cmt in list) {
                await widget.service.sendMessage(
                    chatId: ch.id, text: cmt.text,
                    senderName: cmt.senderName, attachment: cmt.attachment);
              }
              if (mounted) AppSnack.success(context, context.l10n.forwardedTo(ch.name));
            },
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Выделение ─────────────────────────────────────────
  void _enterSelectionMode(Comment first) =>
      setState(() { _isSelectionMode = true; _selectedIds.add(first.id); });
  void _exitSelectionMode() =>
      setState(() { _isSelectionMode = false; _selectedIds.clear(); });
  void _toggleSelect(String id) {
    setState(() {
      _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    });
  }

  // ── Контекстное меню ──────────────────────────────────
  void _showCommentActions(Comment c, {bool isMe = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.reply, color: Theme.of(context).colorScheme.primary, size: 20),
            ),
            title: Text(context.l10n.reply),
            onTap: () { Navigator.pop(context); _startReply(c); },
          ),
          if (isMe && c.text.isNotEmpty && c.attachment == null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
              ),
              title: Text(context.l10n.edit),
              onTap: () { Navigator.pop(context); _startEdit(c); },
            ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.shortcut, color: Colors.white, size: 20),
            ),
            title: Text(context.l10n.forward),
            onTap: () { Navigator.pop(context); _forwardComment(c); },
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary, size: 20),
            ),
            title: Text(context.l10n.selectAction),
            onTap: () { Navigator.pop(context); _enterSelectionMode(c); },
          ),
          if (isMe)
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFEBEE),
                  child: Icon(Icons.delete_outline, color: Colors.red, size: 20)),
              title: Text(context.l10n.delete, style: const TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _deleteComment(c); },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Выбор медиа ───────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    _closeAttachMenu();
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1280, imageQuality: 85);
    if (picked == null || !mounted) return;
    final size = await File(picked.path).length();
    await _sendCommentWithPreview(Attachment(
      path: picked.path, type: AttachmentType.image,
      fileName: picked.name, fileSize: size,
    ));
  }

  Future<void> _pickDocument() async {
    _closeAttachMenu();
    final result = await FilePicker.platform
        .pickFiles(allowMultiple: false, type: FileType.any, withData: false);
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.first;
    if (f.path == null) return;
    final ext = f.name.split('.').last.toLowerCase();
    final att = Attachment(
      path: f.path!,
      type: kVideoExtensions.contains(ext) ? AttachmentType.video : AttachmentType.document,
      fileName: f.name, fileSize: f.size,
    );
    att.type == AttachmentType.video
        ? await _sendCommentWithPreview(att)
        : _sendComment(attachment: att);
  }

  Future<void> _pickMediaFromGallery() async {
    _closeAttachMenu();
    final List<Attachment> attachments = [];
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final picked = await ImagePicker()
            .pickMultipleMedia(maxWidth: 1280, imageQuality: 85);
        for (final p in picked) {
          final size = await File(p.path).length();
          final ext  = p.name.split('.').last.toLowerCase();
          attachments.add(Attachment(
            path: p.path,
            type: kVideoExtensions.contains(ext) ? AttachmentType.video : AttachmentType.image,
            fileName: p.name, fileSize: size,
          ));
        }
      } catch (_) {}
    }
    if (attachments.isEmpty) {
      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const [
            'jpg','jpeg','png','gif','bmp','webp','heic','heif',
            'mp4','mov','avi','mkv','webm','wmv','flv','mpeg','m4v',
          ],
          allowMultiple: true, withData: false,
        );
      } catch (_) {
        result = await FilePicker.platform
            .pickFiles(type: FileType.any, allowMultiple: true, withData: false);
      }
      if (result == null || result.files.isEmpty) return;
      for (final f in result.files) {
        if (f.path == null) continue;
        final ext = f.name.split('.').last.toLowerCase();
        attachments.add(Attachment(
          path: f.path!,
          type: kVideoExtensions.contains(ext) ? AttachmentType.video : AttachmentType.image,
          fileName: f.name, fileSize: f.size,
        ));
      }
    }
    if (attachments.isEmpty || !mounted) return;
    final existingText = _controller.text.trim();
    if (existingText.isNotEmpty) _controller.clear();
    final res = await showDialog<MultiMediaResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MultiMediaPreviewDialog(
          initialAttachments: attachments, initialCaption: existingText),
    );
    if (!mounted) return;
    if (res == null) {
      if (existingText.isNotEmpty) _controller.text = existingText;
      return;
    }
    await _sendMultipleComments(res);
  }

  Future<void> _sendMultipleComments(MultiMediaResult result) async {
    final atts = result.asFiles
        ? result.attachments.map((a) => Attachment(
              path: a.path, type: AttachmentType.document,
              fileName: a.fileName, fileSize: a.fileSize)).toList()
        : result.attachments;
    for (int i = 0; i < atts.length; i++) {
      _controller.text = (i == atts.length - 1) ? result.caption : '';
      await _sendComment(attachment: atts[i]);
    }
  }

  Future<void> _sendCommentWithPreview(Attachment attachment) async {
    if (!mounted) return;
    final existingText = _controller.text.trim();
    if (existingText.isNotEmpty) _controller.clear();
    final caption = await Navigator.of(context, rootNavigator: true).push<String?>(
      PageRouteBuilder<String?>(
        fullscreenDialog: true,
        opaque: true,
        pageBuilder: (_, __, ___) => MediaPreviewPage(
            attachment: attachment, initialCaption: existingText),
        transitionsBuilder: (_, anim, __, child) =>
            SlideTransition(
              position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
      ),
    );
    if (!mounted) return;
    if (caption == null) {
      if (existingText.isNotEmpty) _controller.text = existingText;
      return;
    }
    _controller.text = caption;
    await _sendComment(attachment: attachment);
  }

  // ── Разделители по датам ──────────────────────────────
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateSeparator(DateTime date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final l = context.l10n;
    String label;
    if (_isSameDay(date, now)) {
      label = l.today;
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = l.yesterday;
    } else {
      label = l.shortMonthDate(date.day, date.month);
      if (date.year != now.year) label += ' ${date.year}';
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme  = Theme.of(context);
    final comments = [..._message.comments]
      ..sort((a, b) => a.time.compareTo(b.time));
    final l = context.l10n;
    final countText = comments.isEmpty
        ? l.noComments
        : l.commentCount(comments.length);
    final allMedia = comments
        .where((c) => c.attachment != null &&
            (c.attachment!.type == AttachmentType.image ||
             c.attachment!.type == AttachmentType.video))
        .map((c) => c.attachment!)
        .toList();

    // ── Список с датами ──
    final List<Widget> commentWidgets = [];
    DateTime? lastDate;
    for (final c in comments) {
      final day = DateTime(c.time.year, c.time.month, c.time.day);
      if (lastDate == null || day != lastDate) {
        commentWidgets.add(_buildDateSeparator(c.time));
        lastDate = day;
      }
      final isMe = c.isMe ||
          (widget.currentUserName != null &&
           widget.currentUserName!.isNotEmpty &&
           c.senderName == widget.currentUserName);
      commentWidgets.add(MessageBubble(
        key: ValueKey(c.id),
        message: _commentToMessage(c, isMe),
        showSenderName: !isMe,
        showInterlocutorAvatar: !isMe,
        isSelected: _selectedIds.contains(c.id),
        isSelectionMode: _isSelectionMode,
        onLongPress: () => _showCommentActions(c, isMe: isMe),
        onTap: () => _isSelectionMode ? _toggleSelect(c.id) : null,
        onReply: () => _startReply(c),
        allMedia: allMedia,
        isAcademic: widget.chat.isAcademic,
        currentUserId: widget.currentUserName,
      ));
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E0E) : const Color(0xFFEFEFEF),
      appBar: _isSelectionMode
          ? AppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                  icon: const Icon(Icons.close), onPressed: _exitSelectionMode),
              title: Text(l.selectedItems(_selectedIds.length)),
              actions: [
                if (_selectedIds.isNotEmpty) ...[
                  IconButton(icon: const Icon(Icons.shortcut),
                      tooltip: l.forwardTooltip, onPressed: _forwardSelected),
                  IconButton(icon: const Icon(Icons.delete_outline),
                      tooltip: l.deleteTooltip, onPressed: _deleteSelected),
                ],
              ],
            )
          : AppBar(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : theme.colorScheme.primary,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: !widget.embedded,
              leading: widget.embedded
                  ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
                  : null,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.discussion,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(countText,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
                ],
              ),
            ),
      body: Stack(
        children: [
          // ── Основной контент ──────────────────────────────────────────────
          Positioned.fill(
            child: Column(
              children: [
                // ── Список сообщений ───────────────────────────────────────
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _closeAttachMenu();
                      if (_showEmojiPanel) setState(() => _showEmojiPanel = false);
                    },
                    behavior: HitTestBehavior.translucent,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        // ── Исходный пост ────────────────────────────────
                        ChannelPostCard(
                          message: widget.message,
                          channelName: widget.chat.name,
                          channelAvatarPath: widget.chat.avatarPath,
                          onLongPress: () {},
                          onTap: () {},
                          onOpenComments: null,
                        ),
                        // ── Разделитель ──────────────────────────────────
                        _DividerPill(
                          label: comments.isEmpty
                              ? l.beFirstToComment
                              : l.discussionStart,
                          isDark: isDark,
                        ),
                        // ── Комментарии с датами ─────────────────────────
                        ...commentWidgets,
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),

                // ── Индикатор ответа / редактирования ─────────────────────
                if (!_isSelectionMode) ...[
                  if (_replyingTo != null) _buildReplyIndicator(isDark),
                  if (_editingComment != null) _buildEditIndicator(isDark),

                  // ── Панель эмодзи / GIF ──────────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: _showEmojiPanel
                        ? EmojiGifPanel(
                            controller: _controller,
                            onEmojiSelected: _insertEmoji,
                            onGifSelected: _sendGif,
                            height: 280,
                          )
                        : const SizedBox.shrink(),
                  ),

                  // ── Поле ввода ────────────────────────────────────────────
                  MessageInput(
                    controller: _controller,
                    onSend: _sendOrEdit,
                    onAttach: _toggleAttachMenu,
                    isEditing: _editingComment != null,
                    onSendAudio: _sendAudioComment,
                    onEmojiTap: _toggleEmojiPanel,
                    emojiPanelOpen: _showEmojiPanel,
                  ),
                ],
              ],
            ),
          ),

          // ── Попап вложений (Telegram-style) ──────────────────────────────
          if (_attachMenuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeAttachMenu,
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 68,
              child: _CommentAttachPopup(
                onPickGallery:  _pickMediaFromGallery,
                onPickCamera:   () => _pickImage(ImageSource.camera),
                onPickDocument: _pickDocument,
              ),
            ),
          ],

          // ── Toast цензуры ─────────────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            left: 16, right: 16,
            bottom: _censorToastVisible ? 72 : -120,
            child: IgnorePointer(
              ignoring: !_censorToastVisible,
              child: AnimatedOpacity(
                opacity: _censorToastVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _CensorToast(
                  message: _censorToastMsg,
                  onDismiss: () {
                    _censorTimer?.cancel();
                    setState(() => _censorToastVisible = false);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Индикатор ответа ──────────────────────────────────
  Widget _buildReplyIndicator(bool isDark) {
    final accent = _colorFor(_replyingTo!.senderName);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        )),
      ),
      child: Row(children: [
        Container(width: 2.5, height: 34,
            decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_replyingTo!.senderName,
                style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              _replyingTo!.text.isEmpty
                  ? (_replyingTo!.attachment != null ? context.l10n.attachment : '')
                  : _replyingTo!.text,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black45),
            ),
          ],
        )),
        SizedBox(width: 36, height: 36,
          child: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _cancelReply,
            color: AppColors.subtle,
            padding: EdgeInsets.zero,
          ),
        ),
      ]),
    );
  }

  // ── Индикатор редактирования ─────────────────────────
  Widget _buildEditIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(children: [
        Container(width: 3, height: 36,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.editing,
                style: TextStyle(color: Theme.of(context).colorScheme.primary,
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(_editingComment!.text,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ],
        )),
        IconButton(
          icon: const Icon(Icons.close, size: 20, color: AppColors.subtle),
          onPressed: _cancelEdit,
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Telegram-style попап вложений для комментариев
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentAttachPopup extends StatefulWidget {
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onPickDocument;

  const _CommentAttachPopup({
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onPickDocument,
  });

  @override
  State<_CommentAttachPopup> createState() => _CommentAttachPopupState();
}

class _CommentAttachPopupState extends State<_CommentAttachPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 180));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    (_scale as CurvedAnimation).dispose();
    (_fade  as CurvedAnimation).dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final l = context.l10n;
    final items = [
      (Icons.photo_library_outlined,     l.photoOrVideo,  widget.onPickGallery),
      (Icons.camera_alt_outlined,        l.camera,        widget.onPickCamera),
      (Icons.insert_drive_file_outlined, l.document,      widget.onPickDocument),
    ];
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.bottomLeft,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          shadowColor: Colors.black38,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.map((e) {
                  final (icon, label, onTap) = e;
                  return InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                              color: color, borderRadius: BorderRadius.circular(10)),
                          child: Icon(icon, color: Colors.white, size: 19),
                        ),
                        const SizedBox(width: 12),
                        Text(label, style: const TextStyle(fontSize: 15)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Разделитель-пилюля (начало обсуждения / «будьте первым»)
// ═══════════════════════════════════════════════════════════════════════════════

class _DividerPill extends StatelessWidget {
  final String label;
  final bool isDark;
  const _DividerPill({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
          style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Вспомогательные
// ═══════════════════════════════════════════════════════════════════════════════


class _CensorToast extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _CensorToast({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFFFA000);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: amber.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.13),
              blurRadius: 22, offset: const Offset(0, 5)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: amber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.shield_outlined, size: 19, color: amber),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(message,
          style: TextStyle(fontSize: 12.5, height: 1.4,
              color: isDark ? Colors.white70 : const Color(0xFF333333)))),
        GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.close_rounded, size: 17,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.35)),
          ),
        ),
      ]),
    );
  }
}
