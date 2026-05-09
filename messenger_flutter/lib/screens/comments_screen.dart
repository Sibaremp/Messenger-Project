import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/api_config.dart' show ApiConfig;
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/file_download_service.dart';
import '../widgets/chat_widgets.dart' show MediaViewerScreen, saveAttachmentToFolder;
import '../utils/profanity_filter.dart';
import 'chat_screen.dart' show MediaPreviewPage, MultiMediaPreviewDialog, MultiMediaResult;

/// Полноэкранный раздел комментариев к посту (стиль Telegram-канала).
/// Пост показывается вверху как карточка, комментарии ниже — как обычный чат:
/// чужие — слева с аватаром, свои — справа в оранжевом пузырьке.
class CommentsScreen extends StatefulWidget {
  final Message message;
  final Chat chat;
  final ChatService service;
  final Future<Message?> Function(String text,
      {Attachment? attachment, ReplyInfo? replyTo}) onSend;
  final Future<Message?> Function(String commentId, String newText)? onEdit;
  final Future<Message?> Function(List<String> commentIds)? onDelete;
  /// Если true — встроен в панель (desktop), кнопка «назад» вызывает onBack.
  final bool embedded;
  final VoidCallback? onBack;
  /// Имя текущего пользователя — для правильного определения isMe у комментариев.
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
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late Message _message;

  Comment? _replyingTo;
  Comment? _editingComment;
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  static const _nameColors = [
    Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2), Color(0xFFE64A19),
    Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC2185B), Color(0xFF455A64),
  ];

  Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
    return _nameColors[hash.abs() % _nameColors.length];
  }

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

  // ── Отправка / редактирование ────────────────────────────────────────

  void _sendOrEdit({Attachment? attachment}) {
    _editingComment != null ? _saveEdit() : _sendComment(attachment: attachment);
  }

  Future<void> _sendComment({Attachment? attachment}) async {
    final rawText = _controller.text.trim();
    if (rawText.isEmpty && attachment == null) return;
    _controller.clear();
    // Академическая цензура: заменяем бранные слова до отправки.
    final text = widget.chat.isAcademic
        ? ProfanityFilter.censor(rawText)
        : rawText;
    if (widget.chat.isAcademic && text != rawText && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Комментарий содержал недопустимые слова и был автоматически отредактирован.'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
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
      setState(() {
        _message = updated;
        _replyingTo = null;
      });
      _scrollToEnd();
    }
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

  // ── Пересылка ────────────────────────────────────────────────────────

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Нет других чатов для пересылки'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Переслать в...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            ...others.map((ch) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(ch.name.isNotEmpty ? ch.name[0] : '?',
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              title: Text(ch.name),
              onTap: () async {
                Navigator.pop(context);
                for (final cmt in list) {
                  await widget.service.sendMessage(
                      chatId: ch.id, text: cmt.text,
                      senderName: cmt.senderName, attachment: cmt.attachment);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Переслано в «${ch.name}»'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.primary,
                  ));
                }
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Выделение ────────────────────────────────────────────────────────

  void _enterSelectionMode(Comment first) =>
      setState(() { _isSelectionMode = true; _selectedIds.add(first.id); });
  void _exitSelectionMode() =>
      setState(() { _isSelectionMode = false; _selectedIds.clear(); });
  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // ── Контекстное меню ─────────────────────────────────────────────────

  void _showCommentActions(Comment c, {bool isMe = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: const Icon(Icons.reply, color: AppColors.primary, size: 20),
              ),
              title: const Text('Ответить'),
              onTap: () { Navigator.pop(context); _startReply(c); },
            ),
            if (isMe && c.text.isNotEmpty && c.attachment == null)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                ),
                title: const Text('Редактировать'),
                onTap: () { Navigator.pop(context); _startEdit(c); },
              ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.shortcut, color: Colors.white, size: 20),
              ),
              title: const Text('Переслать'),
              onTap: () { Navigator.pop(context); _forwardComment(c); },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: const Icon(Icons.check_circle_outline,
                    color: AppColors.primary, size: 20),
              ),
              title: const Text('Выделить'),
              onTap: () { Navigator.pop(context); _enterSelectionMode(c); },
            ),
            if (isMe)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFEBEE),
                  child: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                ),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(context); _deleteComment(c); },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Вложения ─────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
        source: source, maxWidth: 1280, imageQuality: 85);
    if (picked == null || !mounted) return;
    final size = await File(picked.path).length();
    await _sendCommentWithPreview(Attachment(
      path: picked.path, type: AttachmentType.image,
      fileName: picked.name, fileSize: size,
    ));
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
        allowMultiple: false, type: FileType.any, withData: false);
    if (result == null || result.files.isEmpty || !mounted) return;
    final f = result.files.first;
    if (f.path == null) return;
    final ext = f.name.split('.').last.toLowerCase();
    // Документы отправляем сразу (без превью), видео — через превью
    final att = Attachment(
      path: f.path!,
      type: kVideoExtensions.contains(ext) ? AttachmentType.video : AttachmentType.document,
      fileName: f.name, fileSize: f.size,
    );
    if (att.type == AttachmentType.video) {
      await _sendCommentWithPreview(att);
    } else {
      _sendComment(attachment: att);
    }
  }

  /// Галерея с мультиселектом — показывает диалог предпросмотра поверх экрана.
  Future<void> _pickMediaFromGallery() async {
    final List<Attachment> attachments = [];

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final picked = await ImagePicker()
            .pickMultipleMedia(maxWidth: 1280, imageQuality: 85);
        for (final p in picked) {
          final size = await File(p.path).length();
          final ext  = p.name.split('.').last.toLowerCase();
          attachments.add(Attachment(
            path:     p.path,
            type:     kVideoExtensions.contains(ext)
                          ? AttachmentType.video
                          : AttachmentType.image,
            fileName: p.name,
            fileSize: size,
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
            'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif',
            'mp4', 'mov', 'avi', 'mkv', 'webm', 'wmv', 'flv', 'mpeg', 'm4v',
          ],
          allowMultiple: true,
          withData: false,
        );
      } catch (_) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any, allowMultiple: true, withData: false);
      }
      if (result == null || result.files.isEmpty) return;
      for (final f in result.files) {
        if (f.path == null) continue;
        final ext = f.name.split('.').last.toLowerCase();
        attachments.add(Attachment(
          path:     f.path!,
          type:     kVideoExtensions.contains(ext)
                        ? AttachmentType.video
                        : AttachmentType.image,
          fileName: f.name,
          fileSize: f.size,
        ));
      }
    }

    if (attachments.isEmpty || !mounted) return;

    final existingText = _controller.text.trim();
    if (existingText.isNotEmpty) _controller.clear();

    final result = await showDialog<MultiMediaResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MultiMediaPreviewDialog(
        initialAttachments: attachments,
        initialCaption: existingText,
      ),
    );

    if (!mounted) return;
    if (result == null) {
      if (existingText.isNotEmpty) _controller.text = existingText;
      return;
    }
    await _sendMultipleComments(result);
  }

  /// Отправляет несколько медиафайлов как отдельные комментарии.
  Future<void> _sendMultipleComments(MultiMediaResult result) async {
    final atts = result.asFiles
        ? result.attachments.map((a) => Attachment(
              path: a.path,
              type: AttachmentType.document,
              fileName: a.fileName,
              fileSize: a.fileSize,
            )).toList()
        : result.attachments;

    for (int i = 0; i < atts.length; i++) {
      _controller.text = (i == atts.length - 1) ? result.caption : '';
      await _sendComment(attachment: atts[i]);
    }
  }

  /// Показывает превью перед отправкой (используется только для камеры).
  Future<void> _sendCommentWithPreview(Attachment attachment) async {
    if (!mounted) return;
    final existingText = _controller.text.trim();
    if (existingText.isNotEmpty) _controller.clear();

    final caption = await Navigator.of(context, rootNavigator: true).push<String?>(
      PageRouteBuilder<String?>(
        fullscreenDialog: true,
        opaque: true,
        pageBuilder: (_, __, ___) => MediaPreviewPage(
          attachment: attachment,
          initialCaption: existingText,
        ),
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

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            // Фото/видео из галереи — единая кнопка с мультиселектом
            ListTile(
              leading: const CircleAvatar(backgroundColor: AppColors.primary,
                  child: Icon(Icons.photo_library, color: Colors.white)),
              title: const Text('Фото или видео'),
              onTap: () { Navigator.pop(context); _pickMediaFromGallery(); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: AppColors.primary,
                  child: Icon(Icons.camera_alt, color: Colors.white)),
              title: const Text('Камера'),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: AppColors.primary,
                  child: Icon(Icons.insert_drive_file, color: Colors.white)),
              title: const Text('Документ'),
              onTap: () { Navigator.pop(context); _pickDocument(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Всегда сортируем по времени, чтобы порядок не зависел от порядка добавления
    final comments = [..._message.comments]
      ..sort((a, b) => a.time.compareTo(b.time));
    final countText = comments.isEmpty
        ? 'Нет комментариев'
        : '${comments.length} ${_commentWord(comments.length)}';

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0E0E0E) : const Color(0xFFEFEFEF),
      appBar: _isSelectionMode
          ? AppBar(
              automaticallyImplyLeading: false,
              leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode),
              title: Text('${_selectedIds.length} выбрано'),
              actions: [
                if (_selectedIds.isNotEmpty) ...[
                  IconButton(
                      icon: const Icon(Icons.shortcut),
                      tooltip: 'Переслать',
                      onPressed: _forwardSelected),
                  IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Удалить',
                      onPressed: _deleteSelected),
                ],
              ],
            )
          : AppBar(
              backgroundColor:
                  isDark ? const Color(0xFF1E1E1E) : AppColors.primary,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: !widget.embedded,
              leading: widget.embedded
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: widget.onBack)
                  : null,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Обсуждение',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(countText,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.normal)),
                ],
              ),
            ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                // ── Исходный пост (карточка) ─────────────────────────────
                _PostCard(
                  message: widget.message,
                  chat: widget.chat,
                  isDark: isDark,
                ),
                // ── Разделитель ──────────────────────────────────────────
                _DividerPill(
                  label: comments.isEmpty
                      ? 'Будьте первым, кто прокомментирует'
                      : 'Начало обсуждения',
                  isDark: isDark,
                ),
                // ── Комментарии ──────────────────────────────────────────
                ...comments.map((c) {
                  final isMe = c.isMe ||
                      (widget.currentUserName != null &&
                          widget.currentUserName!.isNotEmpty &&
                          c.senderName == widget.currentUserName);
                  return _CommentBubble(
                    key: ValueKey(c.id),
                    comment: c,
                    isDark: isDark,
                    isMe: isMe,
                    nameColor: _colorFor(c.senderName),
                    isSelected: _selectedIds.contains(c.id),
                    isSelectionMode: _isSelectionMode,
                    onLongPress: () => _showCommentActions(c, isMe: isMe),
                    onTap: () => _toggleSelect(c.id),
                    onReply: () => _startReply(c),
                    isAcademic: widget.chat.isAcademic,
                  );
                }),
                const SizedBox(height: 4),
              ],
            ),
          ),
          // ── Панель ввода ─────────────────────────────────────────────
          if (!_isSelectionMode) ...[
            if (_replyingTo != null) _buildReplyIndicator(isDark),
            if (_editingComment != null) _buildEditIndicator(isDark),
            _buildInput(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyIndicator(bool isDark) {
    final accent = _colorFor(_replyingTo!.senderName);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 2.5, height: 34,
            decoration: BoxDecoration(
                color: accent, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_replyingTo!.senderName,
                    style: TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  _replyingTo!.text.isEmpty
                      ? (_replyingTo!.attachment != null ? 'Вложение' : '')
                      : _replyingTo!.text,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.black45),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 36, height: 36,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: _cancelReply,
              color: AppColors.subtle,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 3, height: 36,
            decoration: BoxDecoration(
                color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Редактирование',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_editingComment!.text,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppColors.subtle),
            onPressed: _cancelEdit,
          ),
        ],
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            children: [
              if (_editingComment == null)
                IconButton(
                  icon: const Icon(Icons.attach_file, color: AppColors.subtle),
                  onPressed: _showAttachmentOptions,
                  splashRadius: 20,
                ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendOrEdit(),
                    maxLines: null,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Комментарий…',
                      hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppColors.primary,
                child: IconButton(
                  icon: Icon(
                    _editingComment != null ? Icons.check : Icons.send,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _sendOrEdit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Карточка исходного поста (Telegram-style)
// ═══════════════════════════════════════════════════════════════════════════════

class _PostCard extends StatelessWidget {
  final Message message;
  final Chat chat;
  final bool isDark;

  const _PostCard({
    required this.message,
    required this.chat,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final authorName = message.senderName ?? chat.name;
    final nameHash = authorName.codeUnits.fold<int>(0, (h, c) => h + c);
    const nameColors = [
      Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2), Color(0xFFE64A19),
      Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC2185B), Color(0xFF455A64),
    ];
    final nameColor = nameColors[nameHash % nameColors.length];
    final subtleColor = isDark ? Colors.white38 : Colors.black45;
    final isAuthor = chat.adminName == authorName ||
        (message.senderName != null && message.senderName == chat.adminName);

    // ── Telegram-style карточка поста ─────────────────────────────────────
    // Align передаёт дочернему виджету LOOSE-ограничения, поэтому maxWidth
    // на Container реально работает (без Align ListView даёт tight-constraints
    // и maxWidth игнорируется).
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 48, 0),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        // clipBehavior нужен, чтобы изображение не выходило за скруглённые углы
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Шапка: аватар + имя автора + название канала ───────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildAvatar(nameColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: nameColor,
                          ),
                        ),
                        // Показываем название сообщества если автор != сообщество
                        if (message.senderName != null &&
                            message.senderName != chat.name)
                          Text(
                            chat.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: subtleColor),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Вложение(я): изображение/альбом внутри карточки ───────────
            if (message.attachments != null && message.attachments!.isNotEmpty)
              _buildAlbum(message.attachments!)
            else if (message.attachment != null)
              _buildAttachment(message.attachment!),
            // ── Текст поста ────────────────────────────────────────────────
            if (message.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  (message.attachment != null || (message.attachments != null && message.attachments!.isNotEmpty)) ? 10 : 2,
                  12,
                  8,
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            // ── Футер: метка «Автор» + комментарии + время ─────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Row(
                children: [
                  // Метка «Автор» для постов администратора
                  if (isAuthor)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: nameColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Автор',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: nameColor,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Счётчик комментариев
                  Icon(Icons.chat_bubble_outline_rounded,
                      size: 13, color: subtleColor),
                  const SizedBox(width: 3),
                  Text(
                    '${message.comments.length}',
                    style: TextStyle(fontSize: 12, color: subtleColor),
                  ),
                  const SizedBox(width: 10),
                  // Время
                  Text(
                    formatTime(message.time),
                    style: TextStyle(fontSize: 12, color: subtleColor),
                  ),
                ],
              ),
            ),
          ],
        ), // Column
      ), // Container
    ), // Padding
    ); // Align
  }

  /// Аватар: сначала аватар отправителя поста, затем аватар сообщества, затем инициалы.
  Widget _buildAvatar(Color fallbackColor) {
    final avatarPath = message.senderAvatarPath ?? chat.avatarPath;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      if (ApiConfig.isServerMediaPath(avatarPath)) {
        final url = ApiConfig.resolveMediaUrl(avatarPath);
        if (url != null) {
          return CircleAvatar(
            radius: 18,
            backgroundColor: fallbackColor.withValues(alpha: 0.18),
            backgroundImage: NetworkImage(url),
            onBackgroundImageError: (e, s) {},
          );
        }
      } else if (!kIsWeb) {
        final file = File(avatarPath);
        if (file.existsSync()) {
          return CircleAvatar(radius: 18, backgroundImage: FileImage(file));
        }
      }
    }
    final initial = (message.senderName ?? chat.name);
    return CircleAvatar(
      radius: 18,
      backgroundColor: fallbackColor.withValues(alpha: 0.2),
      child: Text(
        initial.isNotEmpty ? initial[0].toUpperCase() : '?',
        style: TextStyle(
          color: fallbackColor,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildAttachment(Attachment att) {
    if (att.type == AttachmentType.image) {
      // fit: BoxFit.fitWidth — показываем полностью (без кропа), потолок 640 px.
      // Изображение обёрнуто в Padding + ClipRRect чтобы были скруглённые углы
      // и виден фон карточки как лёгкая рамка (Telegram-style).
      // GestureDetector позволяет открыть полноэкранный просмотр по тапу.
      Widget wrapImage(BuildContext ctx, Widget img) => GestureDetector(
            onTap: () => MediaViewerScreen.open(ctx, att),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: img,
              ),
            ),
          );

      if (ApiConfig.isServerMediaPath(att.path)) {
        final url = ApiConfig.resolveMediaUrl(att.path);
        if (url != null) {
          return Builder(builder: (ctx) => wrapImage(ctx, ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 640),
            child: Image.network(
              url,
              fit: BoxFit.fitWidth,
              width: double.infinity,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _loadingBox(),
              errorBuilder: (context, e, s) => _fallbackBox(att),
            ),
          )));
        }
      } else if (!kIsWeb) {
        final file = File(att.path);
        if (file.existsSync()) {
          return Builder(builder: (ctx) => wrapImage(ctx, ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 640),
            child: Image.file(file, fit: BoxFit.fitWidth, width: double.infinity),
          )));
        }
      }
    }

    if (att.type == AttachmentType.video) {
      return Builder(
        builder: (ctx) => GestureDetector(
          onTap: () => MediaViewerScreen.open(ctx, att),
          child: _buildVideoTile(att),
        ),
      );
    }

    return _fallbackBox(att);
  }

  /// Плитка видео-файла в посте (без нативного плеера в карточке).
  Widget _buildVideoTile(Attachment att) {
    final thumbUrl = ApiConfig.resolveMediaUrl(att.thumbnailPath);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Фон: thumbnail с сервера или тёмный плейсхолдер
            if (thumbUrl != null)
              SizedBox(
                height: 180,
                width: double.infinity,
                child: Image.network(
                  thumbUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    width: double.infinity,
                    color: isDark ? Colors.black54 : Colors.black87,
                    child: const Icon(Icons.movie_outlined,
                        size: 60, color: Colors.white24),
                  ),
                ),
              )
            else
              Container(
                height: 180,
                width: double.infinity,
                color: isDark ? Colors.black54 : Colors.black87,
                child: const Icon(Icons.movie_outlined,
                    size: 60, color: Colors.white24),
              ),
            // Кнопка воспроизведения
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.55),
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
            ),
            // Имя файла + длительность
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.videocam, size: 14, color: Colors.white70),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        att.fileName,
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (att.durationMs != null)
                      Text(
                        _fmtDuration(att.durationMs!),
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Сетка альбома для карточки поста: показывает до 4 изображений,
  /// остальные скрываются за счётчиком «+N».
  Widget _buildAlbum(List<Attachment> attachments) {
    // Максимум 4 плитки в посте; если больше — последняя покрывается счётчиком.
    const maxVisible = 4;
    final tiles = attachments.take(maxVisible).toList();
    final extra = attachments.length - maxVisible;

    Widget tile(Attachment att, {bool showExtra = false}) {
      Widget img;
      if (att.type == AttachmentType.image) {
        if (ApiConfig.isServerMediaPath(att.path)) {
          final url = ApiConfig.resolveMediaUrl(att.path);
          img = url != null
              ? Image.network(url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1A1A1A),
                          child: Icon(Icons.broken_image, color: Colors.white38)))
              : const ColoredBox(color: Color(0xFF1A1A1A));
        } else if (!kIsWeb) {
          final f = File(att.path);
          img = f.existsSync()
              ? Image.file(f, fit: BoxFit.cover,
                  width: double.infinity, height: double.infinity)
              : const ColoredBox(color: Color(0xFF1A1A1A));
        } else {
          img = const ColoredBox(color: Color(0xFF1A1A1A));
        }
      } else {
        // Видео: thumbnail или заглушка
        final thumbUrl = ApiConfig.resolveMediaUrl(att.thumbnailPath);
        img = Stack(
          fit: StackFit.expand,
          children: [
            if (thumbUrl != null)
              Image.network(thumbUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1A1A1A)))
            else
              const ColoredBox(color: Color(0xFF1A1A1A)),
            const Align(
              alignment: Alignment.center,
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
            ),
          ],
        );
      }

      Widget cell = Builder(
        builder: (ctx) => GestureDetector(
          onTap: () => MediaViewerScreen.open(ctx, att, allMedia: attachments),
          child: showExtra && extra > 0
              ? Stack(fit: StackFit.expand, children: [
                  img,
                  ColoredBox(color: Colors.black.withValues(alpha: 0.55),
                      child: Center(
                        child: Text('+$extra',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                      )),
                ])
              : img,
        ),
      );
      return cell;
    }

    // Сетка: 1 → полная ширина; 2 → два столбца; 3 → 1 большая + 2 справа;
    // 4+ → 2×2.
    const h1 = 240.0;
    const h2 = 160.0;
    const gap = 2.0;

    Widget grid;
    if (tiles.length == 1) {
      grid = SizedBox(height: h1, child: tile(tiles[0]));
    } else if (tiles.length == 2) {
      grid = SizedBox(
        height: h2,
        child: Row(children: [
          Expanded(child: tile(tiles[0])),
          const SizedBox(width: gap),
          Expanded(child: tile(tiles[1], showExtra: extra > 0)),
        ]),
      );
    } else if (tiles.length == 3) {
      grid = SizedBox(
        height: h1,
        child: Row(children: [
          Expanded(flex: 2, child: tile(tiles[0])),
          const SizedBox(width: gap),
          Expanded(
            child: Column(children: [
              Expanded(child: tile(tiles[1])),
              const SizedBox(height: gap),
              Expanded(child: tile(tiles[2], showExtra: extra > 0)),
            ]),
          ),
        ]),
      );
    } else {
      // 4 плитки: 2×2
      grid = SizedBox(
        height: h1,
        child: Column(children: [
          Expanded(child: Row(children: [
            Expanded(child: tile(tiles[0])),
            const SizedBox(width: gap),
            Expanded(child: tile(tiles[1])),
          ])),
          const SizedBox(height: gap),
          Expanded(child: Row(children: [
            Expanded(child: tile(tiles[2])),
            const SizedBox(width: gap),
            Expanded(child: tile(tiles[3], showExtra: extra > 0)),
          ])),
        ]),
      );
    }

    // Обрезаем по скруглённым углам
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: grid,
    );
  }

  static String _fmtDuration(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  Widget _loadingBox() => Container(
        height: 180,
        color: Colors.grey[300],
        alignment: Alignment.center,
        child: const SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );

  Widget _fallbackBox(Attachment att) {
    final icon = switch (att.type) {
      AttachmentType.image    => Icons.image,
      AttachmentType.video    => Icons.videocam,
      AttachmentType.document => Icons.insert_drive_file,
      AttachmentType.audio    => Icons.mic,
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(att.fileName,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Разделитель-пилюля
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Пузырь комментария (Telegram-style: своё — справа, чужое — слева)
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentBubble extends StatefulWidget {
  final Comment comment;
  final bool isDark;
  /// Явно вычисленный флаг "мой комментарий" (учитывает currentUserName).
  final bool isMe;
  final Color nameColor;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final VoidCallback onReply;
  /// Если true — текст цензурируется при отображении.
  final bool isAcademic;

  const _CommentBubble({
    super.key,
    required this.comment,
    required this.isDark,
    required this.isMe,
    required this.nameColor,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onLongPress,
    required this.onTap,
    required this.onReply,
    this.isAcademic = false,
  });

  @override
  State<_CommentBubble> createState() => _CommentBubbleState();
}

class _CommentBubbleState extends State<_CommentBubble> {
  double _swipeOffset = 0;
  bool _swipeTriggered = false;
  static const _swipeThreshold = 64.0;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final isDark = widget.isDark;
    final isMe = widget.isMe;
    final timeColor = isMe
        ? const Color(0xB3FFFFFF)
        : (isDark ? Colors.white38 : Colors.black38);

    // ── Содержимое пузыря ─────────────────────────────────────────────────
    final bubbleContent = _buildBubble(c, isDark, isMe, timeColor);

    // ── Строка ────────────────────────────────────────────────────────────
    Widget row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isSelectionMode ? widget.onTap : null,
      onLongPress: widget.isSelectionMode ? null : widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        // width: double.infinity гарантирует, что Row получит ограниченную ширину
        // даже внутри Stack (который передаёт loose-constraints), тогда Spacer()
        // корректно отодвигает «свои» пузыри к правому краю.
        width: double.infinity,
        color: widget.isSelected
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Чекбокс выделения
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: widget.isSelectionMode
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: widget.isSelected
                                ? AppColors.primary
                                : AppColors.subtle,
                            width: 2,
                          ),
                        ),
                        child: widget.isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Чужое: аватар слева
            if (!isMe) ...[
              CircleAvatar(
                radius: 17,
                backgroundColor: widget.nameColor.withValues(alpha: 0.2),
                child: Text(
                  c.senderName.isNotEmpty ? c.senderName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: widget.nameColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            // Своё: отодвигаем пузырь вправо
            if (isMe) const Spacer(),
            // Пузырь (ограничен 75% ширины экрана).
            // Для «своих» — обычный ConstrainedBox (не Flexible), тогда Spacer()
            // берёт ВСЁ оставшееся место и пузырь прижимается к правому краю.
            // Для «чужих» — Flexible, чтобы длинный текст не вызывал overflow.
            if (isMe)
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75),
                child: bubbleContent,
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75),
                  child: bubbleContent,
                ),
              ),
            // Чужое: пространство справа чтобы не тянулся на всю ширину
            if (!isMe) const SizedBox(width: 44),
          ],
        ),
      ),
    );

    // ── Свайп для ответа ──────────────────────────────────────────────────
    if (!widget.isSelectionMode) {
      final progress = (_swipeOffset / _swipeThreshold).clamp(0.0, 1.0);
      row = GestureDetector(
        onHorizontalDragUpdate: (d) {
          setState(() {
            _swipeOffset =
                (_swipeOffset + d.delta.dx).clamp(0.0, _swipeThreshold + 20);
            if (!_swipeTriggered && _swipeOffset >= _swipeThreshold) {
              _swipeTriggered = true;
              HapticFeedback.lightImpact();
            }
          });
        },
        onHorizontalDragEnd: (_) {
          if (_swipeTriggered) widget.onReply();
          setState(() { _swipeOffset = 0; _swipeTriggered = false; });
        },
        onHorizontalDragCancel: () =>
            setState(() { _swipeOffset = 0; _swipeTriggered = false; }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_swipeOffset > 4)
              Positioned(
                left: _swipeOffset - 44, top: 0, bottom: 0,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _swipeTriggered
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.reply,
                      size: 18 + (progress * 4),
                      color: _swipeTriggered ? Colors.white : AppColors.primary,
                    ),
                  ),
                ),
              ),
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

  Widget _buildBubble(
      Comment c, bool isDark, bool isMe, Color timeColor) {
    // Академическая цензура: при отображении заменяем бранные слова «*».
    final displayText = widget.isAcademic
        ? ProfanityFilter.censor(c.text)
        : c.text;
    final bg = isMe
        ? AppColors.chatMe
        : (isDark ? const Color(0xFF2A2A2A) : Colors.white);

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 3, offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Имя отправителя (только для чужих)
          if (!isMe) ...[
            Text(
              c.senderName,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: widget.nameColor,
              ),
            ),
            const SizedBox(height: 2),
          ],
          // Превью ответа
          if (c.replyTo != null)
            _CommentReplyPreview(reply: c.replyTo!, isDark: isDark),
          // Вложение.
          // Если текста нет — время рисуем поверх изображения (overlay),
          // чтобы пузырь не раздувался до 75% ширины.
          // Если текст есть — вложение отдельно, время идёт в строку с текстом.
          if (c.attachment != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: c.text.isEmpty
                  ? Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        _CommentAttachment(
                            attachment: c.attachment!, isDark: isDark),
                        Padding(
                          padding: const EdgeInsets.all(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (c.isEdited)
                                  const Text('изм. ',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.white)),
                                Text(formatTime(c.time),
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : _CommentAttachment(
                      attachment: c.attachment!, isDark: isDark),
            ),
          // Небольшой отступ-разделитель между медиа и подписью
          if (c.attachment != null && c.text.isNotEmpty)
            const SizedBox(height: 3),
          // Подпись / текст + время (показываем если есть текст, или нет вложения вовсе)
          if (c.text.isNotEmpty || c.attachment == null)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (c.text.isNotEmpty)
                  Flexible(
                    child: Text(
                      displayText,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.3,
                        color: isMe
                            ? AppColors.textLight
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                if (c.isEdited)
                  Text('изм. ',
                      style: TextStyle(fontSize: 10, color: timeColor)),
                Text(formatTime(c.time),
                    style: TextStyle(fontSize: 11, color: timeColor)),
              ],
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Превью ответа в комментарии
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentReplyPreview extends StatelessWidget {
  final ReplyInfo reply;
  final bool isDark;

  const _CommentReplyPreview({required this.reply, required this.isDark});

  static const _colors = [
    Color(0xFFD32F2F), Color(0xFF388E3C), Color(0xFF1976D2), Color(0xFFE64A19),
    Color(0xFF7B1FA2), Color(0xFF00838F), Color(0xFFC2185B), Color(0xFF455A64),
  ];

  @override
  Widget build(BuildContext context) {
    final hash = reply.senderName.codeUnits.fold<int>(0, (h, c) => h * 31 + c);
    final accent = _colors[hash.abs() % _colors.length];

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: accent.withValues(alpha: 0.1),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 2.5, color: accent),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(reply.senderName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: accent,
                        )),
                    const SizedBox(height: 1),
                    Text(
                      reply.text.isEmpty ? 'Вложение' : reply.text,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Превью вложения в комментарии (с поддержкой сетевых изображений)
// ═══════════════════════════════════════════════════════════════════════════════

class _CommentAttachment extends StatefulWidget {
  final Attachment attachment;
  final bool isDark;

  const _CommentAttachment({required this.attachment, required this.isDark});

  @override
  State<_CommentAttachment> createState() => _CommentAttachmentState();
}

class _CommentAttachmentState extends State<_CommentAttachment> {
  StreamSubscription<DownloadProgress>? _sub;
  DownloadProgress _progress = const DownloadProgress(state: DownloadState.idle);

  Attachment get att => widget.attachment;
  bool get isDark => widget.isDark;
  bool get _isRemote => ApiConfig.isServerMediaPath(att.path);
  // Видео обрабатывается так же, как документ: скачивается и открывается внешне.
  bool get _isDoc => att.type == AttachmentType.document || att.type == AttachmentType.video;

  @override
  void initState() {
    super.initState();
    if (_isRemote && _isDoc) {
      _sub = FileDownloadService.instance.watch(att.path).listen((p) {
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

  // ── Картинки ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (att.type == AttachmentType.image) {
      void openViewer() => MediaViewerScreen.open(context, att);
      if (ApiConfig.isServerMediaPath(att.path)) {
        final url = ApiConfig.resolveMediaUrl(att.path);
        if (url != null) {
          return GestureDetector(
            onTap: openViewer,
            child: _wrapInFrame(ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url, width: 200, height: 185, fit: BoxFit.cover,
                loadingBuilder: (ctx, child, p) => p == null
                    ? child
                    : Container(
                        width: 200, height: 185, color: Colors.grey[300],
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                errorBuilder: (ctx, e, s) => _brokenImage(),
              ),
            )),
          );
        }
      }
      if (!kIsWeb) {
        final file = File(att.path);
        if (file.existsSync()) {
          return GestureDetector(
            onTap: openViewer,
            child: _wrapInFrame(ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(file, width: 200, height: 185, fit: BoxFit.cover),
            )),
          );
        }
      }
      return _brokenImage();
    }

    // ── Документы и видео ─────────────────────────────────────────────────
    if (att.type == AttachmentType.document || att.type == AttachmentType.video) {
      return _buildDocWidget(context);
    }

    return _fallbackIcon();
  }

  Widget _buildDocWidget(BuildContext context) {
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : AppColors.background;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = isDark ? Colors.white38 : Colors.black38;

    String subtitle;
    switch (_progress.state) {
      case DownloadState.idle:
        subtitle = att.fileSize != null
            ? '${att.readableSize} • нажмите, чтобы скачать'
            : 'Нажмите, чтобы скачать';
      case DownloadState.downloading:
        final pct = _progress.progress != null
            ? ' ${(_progress.progress! * 100).toStringAsFixed(0)}%'
            : '';
        subtitle = 'Загрузка…$pct';
      case DownloadState.completed:
        subtitle = att.fileSize != null
            ? '${att.readableSize} • на устройстве'
            : 'На устройстве';
      case DownloadState.failed:
        subtitle = 'Ошибка — нажмите, чтобы повторить';
    }

    Widget leadingIcon;
    const sz = 26.0;
    if (!_isRemote) {
      leadingIcon = Icon(_docIcon(att.fileName), color: AppColors.primary, size: sz);
    } else {
      switch (_progress.state) {
        case DownloadState.idle:
        case DownloadState.failed:
          leadingIcon = Icon(
            _progress.state == DownloadState.failed
                ? Icons.refresh
                : Icons.file_download_outlined,
            color: AppColors.primary, size: sz,
          );
        case DownloadState.downloading:
          leadingIcon = SizedBox(
            width: sz, height: sz,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _progress.progress,
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
                Icon(Icons.close, color: AppColors.primary, size: 14),
              ],
            ),
          );
        case DownloadState.completed:
          leadingIcon = Icon(_docIcon(att.fileName), color: AppColors.primary, size: sz);
      }
    }

    return InkWell(
      onTap: _isRemote ? _onDocTap : null,
      onLongPress: _isRemote ? () => _onDocLongPress(context) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leadingIcon,
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(att.fileName,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: subtleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDocTap() async {
    if (!_isRemote) return;
    final svc = FileDownloadService.instance;
    switch (_progress.state) {
      case DownloadState.idle:
      case DownloadState.failed:
        try {
          await svc.download(att.path, fileName: att.fileName);
        } catch (_) {}
      case DownloadState.downloading:
        await svc.cancel(att.path);
      case DownloadState.completed:
        final path = _progress.localPath;
        if (path != null) await OpenFilex.open(path);
    }
  }

  Future<void> _onDocLongPress(BuildContext context) async {
    final canAct = _progress.state == DownloadState.completed;
    final localPath = _progress.localPath;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(att.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          if (canAct)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'open'),
              child: const Row(children: [
                Icon(Icons.open_in_new, size: 20, color: AppColors.primary),
                SizedBox(width: 12),
                Text('Открыть'),
              ]),
            ),
          if (canAct)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'share'),
              child: const Row(children: [
                Icon(Icons.share_outlined, size: 20, color: AppColors.primary),
                SizedBox(width: 12),
                Text('Открыть в программе…'),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Row(children: [
              Icon(Icons.download, size: 20, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Сохранить в папку'),
            ]),
          ),
          if (canAct)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Row(children: [
                Icon(Icons.delete_outline, size: 20, color: Colors.red),
                SizedBox(width: 12),
                Text('Удалить', style: TextStyle(color: Colors.red)),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'open' && localPath != null) {
      await OpenFilex.open(localPath);
    } else if (action == 'share' && localPath != null) {
      await Share.shareXFiles([XFile(localPath)]);
    } else if (action == 'save') {
      // ignore: use_build_context_synchronously
      await saveAttachmentToFolder(context, att);
    } else if (action == 'delete') {
      await FileDownloadService.instance.removeLocal(att.path);
    }
  }

  IconData _docIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf'              => Icons.picture_as_pdf,
      'doc' || 'docx'    => Icons.description,
      'xls' || 'xlsx'    => Icons.table_chart,
      'zip' || 'rar' || '7z' => Icons.folder_zip,
      'mp3' || 'wav' || 'ogg' => Icons.audio_file,
      'mp4' || 'mov' || 'avi' => Icons.video_file,
      _                  => Icons.insert_drive_file,
    };
  }

  Widget _wrapInFrame(Widget child) => Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(13),
        ),
        padding: const EdgeInsets.all(3),
        child: child,
      );

  Widget _brokenImage() => Container(
        width: 200, height: 100,
        decoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.grey[300],
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );

  Widget _fallbackIcon() {
    final icon = switch (att.type) {
      AttachmentType.image    => Icons.image,
      AttachmentType.video    => Icons.videocam,
      AttachmentType.document => Icons.insert_drive_file,
      AttachmentType.audio    => Icons.mic,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(att.fileName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (att.fileSize != null)
                  Text(att.readableSize,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Вспомогательная функция
// ═══════════════════════════════════════════════════════════════════════════════

String _commentWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 19) return 'комментариев';
  if (mod10 == 1) return 'комментарий';
  if (mod10 >= 2 && mod10 <= 4) return 'комментария';
  return 'комментариев';
}
