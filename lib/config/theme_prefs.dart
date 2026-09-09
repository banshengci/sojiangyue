import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';

/// 主题外观配置的领域访问层。
///
/// 主要在 UI 层同步读写；须在 `Prefs().initPrefs()` 之后使用。
class ThemePrefs {
  ThemePrefs._();

  static const String themeColorKey = 'themeColor';
  static const String themeModeKey = 'themeMode';
  static const String trueDarkModeKey = 'trueDarkMode';
  static const String eInkModeKey = 'eInkMode';
  static const String autoAdjustReadingThemeKey = 'autoAdjustReadingTheme';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'ThemePrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  // ---- theme color ----

  static Color get themeColor {
    final colorValue =
        _require.getInt(themeColorKey) ?? SongJiangColors.pine.toARGB32();
    return Color(colorValue);
  }

  static Future<void> saveThemeColor(int colorValue) async {
    await _require.setInt(themeColorKey, colorValue);
  }

  // ---- theme mode ----

  static ThemeMode get themeMode {
    final mode = _require.getString(themeModeKey) ?? 'system';
    switch (mode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(String themeMode) async {
    await _require.setString(themeModeKey, themeMode);
  }

  // ---- true dark / e-ink / auto adjust ----

  static bool get trueDarkMode =>
      _require.getBool(trueDarkModeKey) ?? false;

  static set trueDarkMode(bool status) {
    _require.setBool(trueDarkModeKey, status);
  }

  static bool get eInkMode => _require.getBool(eInkModeKey) ?? false;

  static set eInkMode(bool status) {
    _require.setBool(eInkModeKey, status);
  }

  static bool get autoAdjustReadingTheme =>
      _require.getBool(autoAdjustReadingThemeKey) ?? false;

  static set autoAdjustReadingTheme(bool status) {
    _require.setBool(autoAdjustReadingThemeKey, status);
  }
}
