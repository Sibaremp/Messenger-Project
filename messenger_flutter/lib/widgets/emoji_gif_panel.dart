import 'dart:async';
import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart' hide DownloadProgress;
import '../services/tenor_service.dart';

/// Панель выбора эмодзи / GIF (появляется над полем ввода).
///
/// [onEmojiSelected]  — вставить эмодзи в поле ввода.
/// [onGifSelected]    — отправить GIF (передаётся `gifUrl`).
/// [controller]       — `TextEditingController` чата.
class EmojiGifPanel extends StatefulWidget {
  final void Function(String emoji) onEmojiSelected;
  final void Function(String gifUrl) onGifSelected;
  final TextEditingController controller;
  /// Высота панели (по умолчанию 280).
  final double height;

  const EmojiGifPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onGifSelected,
    required this.controller,
    this.height = 280,
  });

  @override
  State<EmojiGifPanel> createState() => _EmojiGifPanelState();
}

class _EmojiGifPanelState extends State<EmojiGifPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _tenor      = TenorService();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<TenorGif> _gifs    = [];
  bool           _loading = false;
  bool           _initial = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && _initial) _loadTrending();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── GIF-логика ──────────────────────────────────────────────────────────────

  Future<void> _loadTrending() async {
    if (_loading) return;
    setState(() { _loading = true; _initial = false; });
    final gifs = await _tenor.trending();
    if (mounted) setState(() { _gifs = gifs; _loading = false; });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      _loadTrending();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _loading = true);
      final gifs = await _tenor.search(q.trim());
      if (mounted) setState(() { _gifs = gifs; _loading = false; });
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);

    return SizedBox(
      height: widget.height,
      child: Material(
        color: bg,
        child: Column(
          children: [
            // ── Вкладки ───────────────────────────────────
            TabBar(
              controller: _tabs,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.hintColor,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabAlignment: TabAlignment.center,
              tabs: const [
                Tab(text: 'Эмодзи', height: 36),
                Tab(text: 'GIF',    height: 36),
              ],
            ),
            const Divider(height: 1),
            // ── Содержимое ────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildEmojiTab(isDark),
                  _buildGifTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Вкладка «Эмодзи» ───────────────────────────────────────────────────────

  Widget _buildEmojiTab(bool isDark) {
    return EmojiPicker(
      textEditingController: widget.controller,
      onEmojiSelected: (_, emoji) => widget.onEmojiSelected(emoji.emoji),
      onBackspacePressed: () {
        final ctrl = widget.controller;
        final text = ctrl.text;
        final sel  = ctrl.selection;
        if (text.isEmpty) return;
        final start = sel.isValid ? sel.start : text.length;
        if (start == 0) return;
        final before    = text.substring(0, start);
        final chars     = before.characters;
        if (chars.isEmpty) return;
        final newBefore = chars.skipLast(1).string;
        final newText   = newBefore + text.substring(start);
        ctrl.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newBefore.length),
        );
      },
      config: Config(
        // Высота передаётся через SizedBox выше, здесь null = займёт всё место
        height: null,
        emojiViewConfig: EmojiViewConfig(
          emojiSizeMax: 22,          // чуть меньше эмодзи
          columns: 10,
          backgroundColor: Colors.transparent,
          buttonMode: ButtonMode.MATERIAL,
          verticalSpacing: 0,
          horizontalSpacing: 0,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: Colors.transparent,
          indicatorColor: Theme.of(context).colorScheme.primary,
          iconColorSelected: Theme.of(context).colorScheme.primary,
          recentTabBehavior: RecentTabBehavior.RECENT,
          tabBarHeight: 40,
        ),
        // Только кнопка backspace, строку поиска убираем
        bottomActionBarConfig: BottomActionBarConfig(
          showBackspaceButton: true,
          showSearchViewButton: false,
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          buttonIconColor: Theme.of(context).colorScheme.primary,
          buttonColor: Theme.of(context).colorScheme.primary,
        ),
        skinToneConfig: const SkinToneConfig(),
      ),
    );
  }

  // ── Вкладка «GIF» ──────────────────────────────────────────────────────────

  Widget _buildGifTab(ThemeData theme) {
    return Column(
      children: [
        // Компактная строка поиска
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 3),
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Поиск GIF…',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                filled: true,
                fillColor: theme.cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
        ),
        // Сетка GIF
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _gifs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.gif_box_outlined, size: 36, color: theme.hintColor),
                          const SizedBox(height: 6),
                          Text('Введите запрос для поиска GIF',
                              style: TextStyle(fontSize: 12, color: theme.hintColor)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,     // 4 колонки вместо 3
                        crossAxisSpacing: 3,
                        mainAxisSpacing: 3,
                        childAspectRatio: 1.5, // шире, чем высокие
                      ),
                      itemCount: _gifs.length,
                      itemBuilder: (ctx, i) => _GifTile(
                        gif: _gifs[i],
                        onTap: () => widget.onGifSelected(_gifs[i].gifUrl),
                      ),
                    ),
        ),
        // Атрибуция Tenor (обязательна по условиям использования)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            'Powered by Tenor',
            style: TextStyle(fontSize: 9, color: theme.hintColor),
          ),
        ),
      ],
    );
  }
}

// ── Ячейка GIF в сетке ────────────────────────────────────────────────────────

class _GifTile extends StatelessWidget {
  final TenorGif gif;
  final VoidCallback onTap;
  const _GifTile({required this.gif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: gif.previewUrl,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, __) => Container(
            color: Theme.of(context).cardColor,
            child: const Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Theme.of(context).cardColor,
            child: const Icon(Icons.broken_image_outlined, size: 18),
          ),
        ),
      ),
    );
  }
}
