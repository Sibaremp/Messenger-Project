import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_constants.dart';

/// Пользовательское предпочтение темы (сохраняется в SharedPreferences).
enum AppThemeMode { light, dark, system }

// ─── ThemeExtension для кастомных цветов чата ────────────────────────────────

/// Расширение темы: цвета пузырьков, кнопки отправки, фон чата.
/// Используется в chat_widgets.dart и chat_screen.dart через
/// Theme.of(context).extension<CustomChatTheme>()
@immutable
class CustomChatTheme extends ThemeExtension<CustomChatTheme> {
  final Color myBubbleColor;
  final Color otherBubbleColor;
  final Color sendButtonColor;
  final Color? chatBgColor;
  final String? wallpaperPath;
  final String? fontFamily;

  const CustomChatTheme({
    required this.myBubbleColor,
    required this.otherBubbleColor,
    required this.sendButtonColor,
    this.chatBgColor,
    this.wallpaperPath,
    this.fontFamily,
  });

  @override
  CustomChatTheme copyWith({
    Color? myBubbleColor,
    Color? otherBubbleColor,
    Color? sendButtonColor,
    Color? chatBgColor,
    String? wallpaperPath,
    String? fontFamily,
    bool clearWallpaper = false,
    bool clearChatBg = false,
  }) =>
      CustomChatTheme(
        myBubbleColor:    myBubbleColor    ?? this.myBubbleColor,
        otherBubbleColor: otherBubbleColor ?? this.otherBubbleColor,
        sendButtonColor:  sendButtonColor  ?? this.sendButtonColor,
        chatBgColor:      clearChatBg  ? null : (chatBgColor  ?? this.chatBgColor),
        wallpaperPath:    clearWallpaper ? null : (wallpaperPath ?? this.wallpaperPath),
        fontFamily:       fontFamily    ?? this.fontFamily,
      );

  @override
  CustomChatTheme lerp(CustomChatTheme? other, double t) {
    if (other == null) return this;
    return CustomChatTheme(
      myBubbleColor:    Color.lerp(myBubbleColor,    other.myBubbleColor,    t)!,
      otherBubbleColor: Color.lerp(otherBubbleColor, other.otherBubbleColor, t)!,
      sendButtonColor:  Color.lerp(sendButtonColor,  other.sendButtonColor,  t)!,
      chatBgColor:      Color.lerp(chatBgColor, other.chatBgColor, t),
      wallpaperPath:    other.wallpaperPath,
      fontFamily:       other.fontFamily,
    );
  }
}

// ─── AppThemePreset ───────────────────────────────────────────────────────────

/// Полный снимок настроек оформления, который можно сохранить и применить.
/// Заводские пресеты имеют id '__light' и '__dark' и не удаляются.
@immutable
class AppThemePreset {
  final String id;
  final String name;
  final AppThemeMode mode;
  final Color primaryColor;
  final Color? myBubbleColor;
  final Color? otherBubbleColor;
  final Color? sendButtonColor;
  final Color? chatBgColor;
  final String? wallpaperPath;
  final String? fontFamily;

  const AppThemePreset({
    required this.id,
    required this.name,
    required this.mode,
    required this.primaryColor,
    this.myBubbleColor,
    this.otherBubbleColor,
    this.sendButtonColor,
    this.chatBgColor,
    this.wallpaperPath,
    this.fontFamily,
  });

  bool get isFactory => id == '__light' || id == '__dark';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': mode.name,
    'primary': primaryColor.toARGB32(),
    if (myBubbleColor    != null) 'myBubble':    myBubbleColor!.toARGB32(),
    if (otherBubbleColor != null) 'otherBubble': otherBubbleColor!.toARGB32(),
    if (sendButtonColor  != null) 'sendButton':  sendButtonColor!.toARGB32(),
    if (chatBgColor      != null) 'chatBg':      chatBgColor!.toARGB32(),
    if (wallpaperPath    != null) 'wallpaper':   wallpaperPath,
    if (fontFamily       != null) 'font':        fontFamily,
  };

  factory AppThemePreset.fromJson(Map<String, dynamic> j) => AppThemePreset(
    id:              j['id']   as String,
    name:            j['name'] as String,
    mode: AppThemeMode.values.firstWhere(
        (e) => e.name == j['mode'], orElse: () => AppThemeMode.system),
    primaryColor:    Color(j['primary']    as int),
    myBubbleColor:   j['myBubble']    != null ? Color(j['myBubble']    as int) : null,
    otherBubbleColor:j['otherBubble'] != null ? Color(j['otherBubble'] as int) : null,
    sendButtonColor: j['sendButton']  != null ? Color(j['sendButton']  as int) : null,
    chatBgColor:     j['chatBg']      != null ? Color(j['chatBg']      as int) : null,
    wallpaperPath:   j['wallpaper'] as String?,
    fontFamily:      j['font']      as String?,
  );
}

// ─── Fallback AppTheme (статика) ──────────────────────────────────────────────

class AppTheme {
  static ThemeData get light => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1A1A1A),
      elevation: 0.5,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.light,
    ),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE0E0E0),
  );

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1F1F1F),
      foregroundColor: AppColors.textLight,
      elevation: 0,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.dark,
    ),
    cardColor: const Color(0xFF1E1E1E),
    dividerColor: const Color(0xFF2C2C2C),
  );
}

// ─── ThemeProvider ────────────────────────────────────────────────────────────

class ThemeProvider extends StatefulWidget {
  final Widget child;
  const ThemeProvider({super.key, required this.child});

  static ThemeProviderState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ThemeInherited>()!.state;

  @override
  State<ThemeProvider> createState() => ThemeProviderState();
}

class ThemeProviderState extends State<ThemeProvider> {
  AppThemeMode _mode        = AppThemeMode.system;
  Color _primaryColor       = AppColors.primary;
  double _textScale         = 1.0;
  int _lightHour            = -1;
  int _darkHour             = -1;
  Locale? _locale;

  // Chat customisation
  Color? _myBubbleColor;
  Color? _otherBubbleColor;
  Color? _sendButtonColor;
  Color? _chatBgColor;
  String? _wallpaperPath;
  String? _fontFamily;

  // Presets
  List<AppThemePreset> _customPresets = [];
  String? _activePresetId;

  // ── Factory presets (hardcoded, undeletable) ─────────────────────────────────
  static final factoryPresets = [
    const AppThemePreset(
      id: '__light', name: 'Светлая',
      mode: AppThemeMode.light, primaryColor: AppColors.primary),
    const AppThemePreset(
      id: '__dark', name: 'Тёмная',
      mode: AppThemeMode.dark, primaryColor: AppColors.primary),
  ];

  // ── Prefs keys ──────────────────────────────────────────────────────────────
  static const _kMode           = 'app_theme_mode';
  static const _kPrimary        = 'app_primary_color';
  static const _kTextScale      = 'app_text_scale';
  static const _kLightHour      = 'app_light_hour';
  static const _kDarkHour       = 'app_dark_hour';
  static const _kLanguage       = 'app_language';
  static const _kMyBubble       = 'app_my_bubble_color';
  static const _kOtherBubble    = 'app_other_bubble_color';
  static const _kSendButton     = 'app_send_button_color';
  static const _kChatBg         = 'app_chat_bg_color';
  static const _kWallpaper      = 'app_wallpaper_path';
  static const _kFont           = 'app_font_family';
  static const _kPresets        = 'app_theme_presets';
  static const _kActivePreset   = 'app_active_preset';

  // ── Getters ─────────────────────────────────────────────────────────────────
  AppThemeMode get mode         => _mode;
  Color get primaryColor        => _primaryColor;
  double get textScale          => _textScale;
  int get lightHour             => _lightHour;
  int get darkHour              => _darkHour;
  bool get autoNightEnabled     => _lightHour >= 0 && _darkHour >= 0;
  Locale? get locale            => _locale;
  Color? get myBubbleColor      => _myBubbleColor;
  Color? get otherBubbleColor   => _otherBubbleColor;
  Color? get sendButtonColor    => _sendButtonColor;
  Color? get chatBgColor        => _chatBgColor;
  String? get wallpaperPath     => _wallpaperPath;
  String? get fontFamily        => _fontFamily;

  // Preset getters
  List<AppThemePreset> get customPresets  => List.unmodifiable(_customPresets);
  List<AppThemePreset> get allPresets     => [...factoryPresets, ..._customPresets];
  String? get activePresetId             => _activePresetId;

  // Effective values (fallback to primary/defaults)
  Color get effectiveMyBubble      => _myBubbleColor    ?? _primaryColor;
  Color get effectiveOtherBubble   => _otherBubbleColor ?? const Color(0xFFFFFFFF);
  Color get effectiveSendButton    => _sendButtonColor  ?? _primaryColor;

  ThemeMode get themeMode {
    if (autoNightEnabled) {
      final h = TimeOfDay.now().hour;
      final inDark = _darkHour < _lightHour
          ? h >= _darkHour && h < _lightHour
          : h >= _darkHour || h < _lightHour;
      return inDark ? ThemeMode.dark : ThemeMode.light;
    }
    return switch (_mode) {
      AppThemeMode.light  => ThemeMode.light,
      AppThemeMode.dark   => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };
  }

  // ── Theme builders ───────────────────────────────────────────────────────────

  ThemeData lightTheme(Color primary) => _buildTheme(
    primary: primary,
    brightness: Brightness.light,
    scaffoldBg: _chatBgColor ?? AppColors.background,
    appBarBg: Colors.white,
    appBarFg: const Color(0xFF1A1A1A),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE0E0E0),
  );

  ThemeData darkTheme(Color primary) => _buildTheme(
    primary: primary,
    brightness: Brightness.dark,
    scaffoldBg: _chatBgColor ?? const Color(0xFF121212),
    appBarBg: const Color(0xFF1F1F1F),
    appBarFg: AppColors.textLight,
    cardColor: const Color(0xFF1E1E1E),
    dividerColor: const Color(0xFF2C2C2C),
  );

  ThemeData _buildTheme({
    required Color primary,
    required Brightness brightness,
    required Color scaffoldBg,
    required Color appBarBg,
    required Color appBarFg,
    required Color cardColor,
    required Color dividerColor,
  }) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        elevation: isDark ? 0 : 0.5,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: appBarFg),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        brightness: brightness,
      ),
      cardColor: cardColor,
      dividerColor: dividerColor,
      extensions: [
        CustomChatTheme(
          myBubbleColor:    effectiveMyBubble,
          otherBubbleColor: isDark
              ? (_otherBubbleColor ?? const Color(0xFF2A2A2A))
              : (_otherBubbleColor ?? Colors.white),
          sendButtonColor:  effectiveSendButton,
          chatBgColor:      _chatBgColor,
          wallpaperPath:    _wallpaperPath,
          fontFamily:       _fontFamily,
        ),
      ],
    );
  }

  // ── Load / Save ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    Color? loadColor(String key) {
      final v = prefs.getInt(key);
      return v != null ? Color(v) : null;
    }

    final saved  = prefs.getString(_kMode);
    final mode   = AppThemeMode.values.firstWhere(
        (e) => e.name == saved, orElse: () => AppThemeMode.system);
    final primary = loadColor(_kPrimary) ?? AppColors.primary;
    final scale   = prefs.getDouble(_kTextScale) ?? 1.0;
    final lh      = prefs.getInt(_kLightHour) ?? -1;
    final dh      = prefs.getInt(_kDarkHour)  ?? -1;
    final langCode = prefs.getString(_kLanguage);

    // Load custom presets
    List<AppThemePreset> customPresets = [];
    try {
      final presetsJson = prefs.getString(_kPresets);
      if (presetsJson != null) {
        final list = jsonDecode(presetsJson) as List<dynamic>;
        customPresets = list
            .map((e) => AppThemePreset.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    final activePresetId = prefs.getString(_kActivePreset);

    if (mounted) {
      setState(() {
        _mode             = mode;
        _primaryColor     = primary;
        _textScale        = scale;
        _lightHour        = lh;
        _darkHour         = dh;
        _locale           = langCode != null ? Locale(langCode) : null;
        _myBubbleColor    = loadColor(_kMyBubble);
        _otherBubbleColor = loadColor(_kOtherBubble);
        _sendButtonColor  = loadColor(_kSendButton);
        _chatBgColor      = loadColor(_kChatBg);
        _wallpaperPath    = prefs.getString(_kWallpaper);
        _fontFamily       = prefs.getString(_kFont);
        _customPresets    = customPresets;
        _activePresetId   = activePresetId;
      });
    }
  }

  // ── Setters ──────────────────────────────────────────────────────────────────

  // ── Preset management ────────────────────────────────────────────────────────

  /// Применяет пресет: сбрасывает все кастомные параметры к значениям пресета.
  Future<void> applyPreset(AppThemePreset preset) async {
    setState(() {
      _activePresetId   = preset.id;
      _mode             = preset.mode;
      _primaryColor     = preset.primaryColor;
      _myBubbleColor    = preset.myBubbleColor;
      _otherBubbleColor = preset.otherBubbleColor;
      _sendButtonColor  = preset.sendButtonColor;
      _chatBgColor      = preset.chatBgColor;
      _wallpaperPath    = preset.wallpaperPath;
      _fontFamily       = preset.fontFamily;
    });
    final p = await SharedPreferences.getInstance();
    p.setString(_kMode,    preset.mode.name);
    p.setInt(_kPrimary,    preset.primaryColor.toARGB32());
    preset.myBubbleColor    != null ? p.setInt(_kMyBubble,    preset.myBubbleColor!.toARGB32())    : p.remove(_kMyBubble);
    preset.otherBubbleColor != null ? p.setInt(_kOtherBubble, preset.otherBubbleColor!.toARGB32()) : p.remove(_kOtherBubble);
    preset.sendButtonColor  != null ? p.setInt(_kSendButton,  preset.sendButtonColor!.toARGB32())  : p.remove(_kSendButton);
    preset.chatBgColor      != null ? p.setInt(_kChatBg,      preset.chatBgColor!.toARGB32())      : p.remove(_kChatBg);
    preset.wallpaperPath    != null ? p.setString(_kWallpaper, preset.wallpaperPath!)               : p.remove(_kWallpaper);
    preset.fontFamily       != null ? p.setString(_kFont,      preset.fontFamily!)                  : p.remove(_kFont);
    p.setString(_kActivePreset, preset.id);
  }

  /// Сохраняет текущие настройки как новый кастомный пресет.
  Future<AppThemePreset> saveCurrentAsPreset(String name) async {
    final preset = AppThemePreset(
      id:              'custom_${DateTime.now().millisecondsSinceEpoch}',
      name:            name,
      mode:            _mode,
      primaryColor:    _primaryColor,
      myBubbleColor:   _myBubbleColor,
      otherBubbleColor:_otherBubbleColor,
      sendButtonColor: _sendButtonColor,
      chatBgColor:     _chatBgColor,
      wallpaperPath:   _wallpaperPath,
      fontFamily:      _fontFamily,
    );
    setState(() {
      _customPresets.add(preset);
      _activePresetId = preset.id;
    });
    final p = await SharedPreferences.getInstance();
    p.setString(_kPresets,      jsonEncode(_customPresets.map((e) => e.toJson()).toList()));
    p.setString(_kActivePreset, preset.id);
    return preset;
  }

  /// Удаляет кастомный пресет по id.
  Future<void> deleteCustomPreset(String id) async {
    setState(() {
      _customPresets.removeWhere((e) => e.id == id);
      if (_activePresetId == id) _activePresetId = null;
    });
    final p = await SharedPreferences.getInstance();
    p.setString(_kPresets, jsonEncode(_customPresets.map((e) => e.toJson()).toList()));
    if (_activePresetId == null) p.remove(_kActivePreset);
  }

  void _clearActivePreset() {
    if (_activePresetId != null) {
      _activePresetId = null;
      SharedPreferences.getInstance().then((p) => p.remove(_kActivePreset));
    }
  }

  // ── Setters (clear active preset when user manually changes anything) ────────

  Future<void> setMode(AppThemeMode mode) async {
    setState(() { _mode = mode; _clearActivePreset(); });
    (await SharedPreferences.getInstance()).setString(_kMode, mode.name);
  }

  Future<void> setPrimaryColor(Color color) async {
    setState(() { _primaryColor = color; _clearActivePreset(); });
    (await SharedPreferences.getInstance()).setInt(_kPrimary, color.toARGB32());
  }

  Future<void> setTextScale(double scale) async {
    final clamped = scale.clamp(0.7, 1.5);
    setState(() => _textScale = clamped);
    (await SharedPreferences.getInstance()).setDouble(_kTextScale, clamped);
  }

  Future<void> setMyBubbleColor(Color? color) async {
    setState(() { _myBubbleColor = color; _clearActivePreset(); });
    final p = await SharedPreferences.getInstance();
    color != null ? p.setInt(_kMyBubble, color.toARGB32()) : p.remove(_kMyBubble);
  }

  Future<void> setOtherBubbleColor(Color? color) async {
    setState(() { _otherBubbleColor = color; _clearActivePreset(); });
    final p = await SharedPreferences.getInstance();
    color != null ? p.setInt(_kOtherBubble, color.toARGB32()) : p.remove(_kOtherBubble);
  }

  Future<void> setSendButtonColor(Color? color) async {
    setState(() { _sendButtonColor = color; _clearActivePreset(); });
    final p = await SharedPreferences.getInstance();
    color != null ? p.setInt(_kSendButton, color.toARGB32()) : p.remove(_kSendButton);
  }

  Future<void> setChatBgColor(Color? color) async {
    setState(() { _chatBgColor = color; _clearActivePreset(); });
    final p = await SharedPreferences.getInstance();
    color != null ? p.setInt(_kChatBg, color.toARGB32()) : p.remove(_kChatBg);
  }

  Future<void> setWallpaper(String? path) async {
    setState(() { _wallpaperPath = path; _clearActivePreset(); });
    final p = await SharedPreferences.getInstance();
    path != null ? p.setString(_kWallpaper, path) : p.remove(_kWallpaper);
  }

  Future<void> setFontFamily(String? family) async {
    setState(() { _fontFamily = family; _clearActivePreset(); });
    final p = await SharedPreferences.getInstance();
    family != null ? p.setString(_kFont, family) : p.remove(_kFont);
  }

  Future<void> setAutoNight({required int lightHour, required int darkHour}) async {
    setState(() { _lightHour = lightHour; _darkHour = darkHour; });
    final p = await SharedPreferences.getInstance();
    p.setInt(_kLightHour, lightHour);
    p.setInt(_kDarkHour,  darkHour);
  }

  Future<void> disableAutoNight() async {
    setState(() { _lightHour = -1; _darkHour = -1; });
    final p = await SharedPreferences.getInstance();
    p.setInt(_kLightHour, -1);
    p.setInt(_kDarkHour,  -1);
  }

  Future<void> setLocale(String? languageCode) async {
    setState(() => _locale = languageCode != null ? Locale(languageCode) : null);
    final p = await SharedPreferences.getInstance();
    languageCode != null
        ? p.setString(_kLanguage, languageCode)
        : p.remove(_kLanguage);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => _ThemeInherited(
        state:        this,
        mode:         _mode,
        primaryColor: _primaryColor,
        textScale:    _textScale,
        locale:       _locale,
        chatHash: Object.hashAll([
          _myBubbleColor, _otherBubbleColor, _sendButtonColor,
          _chatBgColor, _wallpaperPath, _fontFamily,
        ]),
        presetsHash: Object.hashAll([
          _activePresetId,
          ..._customPresets.map((e) => e.id),
        ]),
        child: widget.child,
      );
}

class _ThemeInherited extends InheritedWidget {
  final ThemeProviderState state;
  final AppThemeMode mode;
  final Color primaryColor;
  final double textScale;
  final Locale? locale;
  final int chatHash;
  final int presetsHash;

  const _ThemeInherited({
    required this.state,
    required this.mode,
    required this.primaryColor,
    required this.textScale,
    required this.locale,
    required this.chatHash,
    required this.presetsHash,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ThemeInherited old) =>
      old.mode         != mode         ||
      old.primaryColor != primaryColor ||
      old.textScale    != textScale    ||
      old.locale       != locale       ||
      old.chatHash     != chatHash     ||
      old.presetsHash  != presetsHash;
}
