import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import '../app_constants.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart' as svc;
import '../services/signaling_service.dart';
import '../widgets/chat_widgets.dart';
import 'chat_screen.dart';

/// Полноэкранный поиск с тремя вкладками: Чаты, Сообщения, Файлы.
class SearchScreen extends StatefulWidget {
  final ChatService service;
  final List<AppContact> contacts;
  final ValueChanged<Chat>? onChatSelected;
  /// AuthService для передачи текущего пользователя в ChatScreen.
  final svc.AuthService? auth;
  /// SignalingService для передачи в ChatScreen (кнопки звонков).
  final SignalingService? signalingService;

  /// Если true — экран встроен в панель (desktop), не открывает чат через Navigator.
  final bool embedded;

  const SearchScreen({
    super.key,
    required this.service,
    this.contacts = const [],
    this.onChatSelected,
    this.auth,
    this.signalingService,
    this.embedded = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  Timer? _debounce;

  String _query = '';
  List<Chat> _chatResults = [];
  List<SearchMessageResult> _messageResults = [];
  List<SearchFileResult> _fileResults = [];
  bool _loading = false;

  // Фильтр типа файла
  AttachmentType? _fileTypeFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      if (_query.isNotEmpty) {
        _performSearch();
      } else {
        setState(() {
          _chatResults = [];
          _messageResults = [];
          _fileResults = [];
        });
      }
    });
  }

  Future<void> _performSearch() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.service.searchChats(_query),
      widget.service.searchMessages(_query),
      widget.service.searchFiles(
        type: _fileTypeFilter,
        nameQuery: _query,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _chatResults = results[0] as List<Chat>;
      _messageResults = results[1] as List<SearchMessageResult>;
      _fileResults = results[2] as List<SearchFileResult>;
      _loading = false;
    });
  }

  void _openChat(Chat chat) {
    if (widget.embedded && widget.onChatSelected != null) {
      widget.onChatSelected!(chat);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chat: chat,
            service: widget.service,
            onChatUpdated: (_) {},
            contacts: widget.contacts,
            auth: widget.auth,
            signalingService: widget.signalingService,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        backgroundColor: isDark ? null : Colors.white,
        foregroundColor: isDark ? null : Colors.black87,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _onQueryChanged,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: context.l10n.searchChatsMessagesFiles,
              hintStyle: TextStyle(
                color: AppColors.subtle.withValues(alpha: 0.6),
                fontSize: 14,
              ),
              prefixIcon: Icon(Icons.search,
                  size: 20,
                  color: isDark ? AppColors.subtle : Colors.grey[600]),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.black54),
                      onPressed: () {
                        _searchController.clear();
                        _onQueryChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFF2F2F2),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: AppColors.subtle,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: context.l10n.searchTabChats(_chatResults.length)),
            Tab(text: context.l10n.searchTabMessages(_messageResults.length)),
            Tab(text: context.l10n.searchTabFiles(_fileResults.length)),
          ],
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : _query.isEmpty
              ? _buildEmptyHint()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildChatResults(),
                    _buildMessageResults(),
                    _buildFileResults(),
                  ],
                ),
    );
  }

  Widget _buildEmptyHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search,
              size: 56, color: AppColors.subtle.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            context.l10n.enterQuery,
            style: const TextStyle(color: AppColors.subtle, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.searchHint,
            style: TextStyle(
                color: AppColors.subtle.withValues(alpha: 0.6), fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Результаты: Чаты ───────────────────────────────────────────

  Widget _buildChatResults() {
    if (_chatResults.isEmpty) return _noResults(context.l10n.chatsNotFound);
    return ListView.builder(
      itemCount: _chatResults.length,
      itemBuilder: (_, i) {
        final chat = _chatResults[i];
        return Column(
          children: [
            ListTile(
              leading:
                  ChatAvatar(type: chat.type, avatarPath: chat.avatarPath, chatName: chat.name),
              title: _highlightText(chat.name, _query),
              subtitle: chat.description != null
                  ? Text(chat.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.subtle))
                  : Text(
                      _chatTypeLabel(chat),
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.subtle),
                    ),
              trailing: chat.isAcademic
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(context.l10n.academicShort,
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600)),
                    )
                  : null,
              onTap: () => _openChat(chat),
            ),
            const Divider(height: 1, indent: 72),
          ],
        );
      },
    );
  }

  String _chatTypeLabel(Chat chat) {
    switch (chat.type) {
      case ChatType.direct:
        return context.l10n.directChat;
      case ChatType.group:
        return context.l10n.chatTypeGroup(chat.members.length + 1);
      case ChatType.community:
        return context.l10n.chatTypeCommunity(chat.members.length + 1);
    }
  }

  // ── Результаты: Сообщения ──────────────────────────────────────

  Widget _buildMessageResults() {
    if (_messageResults.isEmpty) return _noResults(context.l10n.messagesNotFound);
    return ListView.builder(
      itemCount: _messageResults.length,
      itemBuilder: (_, i) {
        final r = _messageResults[i];
        return Column(
          children: [
            ListTile(
              leading: ChatAvatar(
                  type: r.chat.type, avatarPath: r.chat.avatarPath, chatName: r.chat.name),
              title: Row(
                children: [
                  Expanded(
                    child: Text(r.chat.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  Text(
                    formatChatTime(r.message.time),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.subtle),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.message.senderName != null)
                    Text(r.message.senderName!,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500)),
                  _highlightText(r.message.text, _query,
                      maxLines: 2, fontSize: 13),
                ],
              ),
              onTap: () => _openChat(r.chat),
            ),
            const Divider(height: 1, indent: 72),
          ],
        );
      },
    );
  }

  // ── Результаты: Файлы ──────────────────────────────────────────

  Widget _buildFileResults() {
    if (_fileResults.isEmpty && _query.isNotEmpty) {
      return _noResults(context.l10n.filesNotFound);
    }
    return Column(
      children: [
        // Фильтры по типу файла
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _fileFilterChip(context.l10n.allFiles, _fileTypeFilter == null, () {
                setState(() => _fileTypeFilter = null);
                if (_query.isNotEmpty) _performSearch();
              }),
              const SizedBox(width: 6),
              _fileFilterChip(context.l10n.imageFiles, _fileTypeFilter == AttachmentType.image,
                  () {
                setState(() => _fileTypeFilter = AttachmentType.image);
                if (_query.isNotEmpty) _performSearch();
              }),
              const SizedBox(width: 6),
              _fileFilterChip(context.l10n.videoFiles, _fileTypeFilter == AttachmentType.video,
                  () {
                setState(() => _fileTypeFilter = AttachmentType.video);
                if (_query.isNotEmpty) _performSearch();
              }),
              const SizedBox(width: 6),
              _fileFilterChip(
                  context.l10n.documentFiles, _fileTypeFilter == AttachmentType.document, () {
                setState(() => _fileTypeFilter = AttachmentType.document);
                if (_query.isNotEmpty) _performSearch();
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _fileResults.isEmpty
              ? _noResults(context.l10n.filesNotFound)
              : ListView.builder(
                  itemCount: _fileResults.length,
                  itemBuilder: (_, i) {
                    final r = _fileResults[i];
                    return Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            child: Icon(_fileIcon(r.attachment.type),
                                color: Theme.of(context).colorScheme.primary, size: 20),
                          ),
                          title: _highlightText(
                              r.attachment.fileName, _query,
                              fontSize: 14),
                          subtitle: Text(
                            '${r.chat.name} • ${formatChatTime(r.message.time)}'
                            '${r.attachment.fileSize != null ? ' • ${_formatSize(r.attachment.fileSize!)}' : ''}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.subtle),
                          ),
                          onTap: () => _openChat(r.chat),
                        ),
                        const Divider(height: 1, indent: 72),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _fileFilterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : AppColors.subtle.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.subtle,
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(AttachmentType type) {
    return switch (type) {
      AttachmentType.image    => Icons.image,
      AttachmentType.video    => Icons.videocam,
      AttachmentType.document => Icons.insert_drive_file,
      AttachmentType.audio    => Icons.mic,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Утилиты ────────────────────────────────────────────────────

  Widget _noResults(String text) {
    return Center(
      child: Text(text, style: const TextStyle(color: AppColors.subtle)),
    );
  }

  /// Подсвечивает совпадения жёлтым в тексте.
  Widget _highlightText(String text, String query,
      {int maxLines = 1, double fontSize = 14}) {
    if (query.isEmpty) {
      return Text(text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize));
    }
    final lower = text.toLowerCase();
    final qLower = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lower.indexOf(qLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ));
      start = idx + query.length;
    }
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black87,
        ),
        children: spans,
      ),
    );
  }
}
