import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/code_highlight_theme.dart';
import 'package:songjiang_reader/enums/hint_key.dart';

/// 阅读页杂项 UI 开关 / CSS / 代码高亮 / 提示条 的领域访问层。
class ReadingUiPrefs {
  ReadingUiPrefs._();

  static const String hideStatusBarKey = 'hideStatusBar';
  static const String awakeTimeKey = 'awakeTime';
  static const String autoHideBottomBarKey = 'autoHideBottomBar';
  static const String reduceVibrationKey = 'reduceVibrationFeedback';
  static const String autoTranslateSelectionKey = 'autoTranslateSelection';
  static const String autoMarkSelectionKey = 'autoMarkSelection';
  static const String autoSummaryPreviousKey = 'autoSummaryPreviousContent';
  static const String volumeKeyTurnPageKey = 'volumeKeyTurnPage';
  static const String keyboardShortcutTurnPageKey = 'keyboardShortcutTurnPage';
  static const String swapPageTurnAreaKey = 'swapPageTurnArea';
  static const String showMenuOnHoverKey = 'showMenuOnHover';
  static const String showActionLabelsKey = 'showActionLabels';
  static const String showTextUnderIconButtonKey = 'showTextUnderIconButton';
  static const String customCssKey = 'customCSS';
  static const String customCssEnabledKey = 'customCSSEnabled';
  static const String codeHighlightThemeKey = 'codeHighlightTheme';
  static const String enableJsForEpubKey = 'enableJsForEpub';
  static const String hintPrefix = 'hint_';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'ReadingUiPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static bool get hideStatusBar => _require.getBool(hideStatusBarKey) ?? false;

  static set hideStatusBar(bool status) {
    _require.setBool(hideStatusBarKey, status);
  }

  static void saveHideStatusBar(bool status) {
    hideStatusBar = status;
  }

  static int get awakeTime => _require.getInt(awakeTimeKey) ?? 0;

  static set awakeTime(int minutes) {
    _require.setInt(awakeTimeKey, minutes);
  }

  static bool get autoHideBottomBar =>
      _require.getBool(autoHideBottomBarKey) ?? false;

  static set autoHideBottomBar(bool status) {
    _require.setBool(autoHideBottomBarKey, status);
  }

  static bool get reduceVibrationFeedback =>
      _require.getBool(reduceVibrationKey) ?? false;

  static set reduceVibrationFeedback(bool value) {
    _require.setBool(reduceVibrationKey, value);
  }

  static bool get autoTranslateSelection =>
      _require.getBool(autoTranslateSelectionKey) ?? false;

  static set autoTranslateSelection(bool status) {
    _require.setBool(autoTranslateSelectionKey, status);
  }

  static bool get autoMarkSelection =>
      _require.getBool(autoMarkSelectionKey) ?? false;

  static set autoMarkSelection(bool status) {
    _require.setBool(autoMarkSelectionKey, status);
  }

  static bool get autoSummaryPreviousContent =>
      _require.getBool(autoSummaryPreviousKey) ?? false;

  static set autoSummaryPreviousContent(bool status) {
    _require.setBool(autoSummaryPreviousKey, status);
  }

  static bool get volumeKeyTurnPage =>
      _require.getBool(volumeKeyTurnPageKey) ?? false;

  static set volumeKeyTurnPage(bool status) {
    _require.setBool(volumeKeyTurnPageKey, status);
  }

  static bool get keyboardShortcutTurnPage =>
      _require.getBool(keyboardShortcutTurnPageKey) ?? false;

  static set keyboardShortcutTurnPage(bool status) {
    _require.setBool(keyboardShortcutTurnPageKey, status);
  }

  static bool get swapPageTurnArea =>
      _require.getBool(swapPageTurnAreaKey) ?? false;

  static set swapPageTurnArea(bool status) {
    _require.setBool(swapPageTurnAreaKey, status);
  }

  static bool get showMenuOnHover =>
      _require.getBool(showMenuOnHoverKey) ?? true;

  static set showMenuOnHover(bool status) {
    _require.setBool(showMenuOnHoverKey, status);
  }

  static bool get showActionLabels =>
      _require.getBool(showActionLabelsKey) ?? true;

  static set showActionLabels(bool status) {
    _require.setBool(showActionLabelsKey, status);
  }

  static bool get showTextUnderIconButton =>
      _require.getBool(showTextUnderIconButtonKey) ?? true;

  static set showTextUnderIconButton(bool show) {
    _require.setBool(showTextUnderIconButtonKey, show);
  }

  static String get customCss => _require.getString(customCssKey) ?? '';

  static set customCss(String css) {
    _require.setString(customCssKey, css);
  }

  static bool get customCssEnabled =>
      _require.getBool(customCssEnabledKey) ?? false;

  static set customCssEnabled(bool enabled) {
    _require.setBool(customCssEnabledKey, enabled);
  }

  static CodeHighlightThemeEnum get codeHighlightTheme =>
      CodeHighlightThemeEnum.fromCode(
          _require.getString(codeHighlightThemeKey) ?? 'default');

  static set codeHighlightTheme(CodeHighlightThemeEnum theme) {
    _require.setString(codeHighlightThemeKey, theme.code);
  }

  static bool get enableJsForEpub =>
      _require.getBool(enableJsForEpubKey) ?? false;

  static set enableJsForEpub(bool enable) {
    _require.setBool(enableJsForEpubKey, enable);
  }

  // ---- hints ----

  static bool shouldShowHint(HintKey key) =>
      _require.getBool('$hintPrefix${key.code}') ?? true;

  static void setShowHint(HintKey key, bool value) {
    _require.setBool('$hintPrefix${key.code}', value);
  }

  static void resetHints() {
    for (final hint in HintKey.values) {
      _require.remove('$hintPrefix${hint.code}');
    }
  }
}
