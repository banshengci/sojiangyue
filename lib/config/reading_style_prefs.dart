import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/convert_chinese_mode.dart';
import 'package:songjiang_reader/enums/text_alignment.dart';
import 'package:songjiang_reader/enums/writing_mode.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/models/reading_rules.dart';
import 'package:songjiang_reader/widgets/reading_page/style_widget.dart'
    show PageTurn;

/// 阅读样式相关配置的领域访问层。
///
/// 须在 `Prefs().initPrefs()` 之后使用。
/// readingInfo 因旧数据迁移依赖 MediaQuery，暂仍留在 Prefs。
class ReadingStylePrefs {
  ReadingStylePrefs._();

  static const String bookStyleKey = 'readStyle';
  static const String readingRulesKey = 'readingRules';
  static const String useBookStylesKey = 'useBookStyles';
  static const String writingModeKey = 'writingMode';
  static const String textAlignmentKey = 'textAlignment';
  static const String pageTurnStyleKey = 'pageTurnStyle';
  static const String pageTurnModeKey = 'pageTurnMode';
  static const String pageTurningTypeKey = 'pageTurningType';
  static const String customPageTurnConfigKey = 'customPageTurnConfig';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'ReadingStylePrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  // ---- book style ----

  static BookStyle get bookStyle {
    final json = _require.getString(bookStyleKey);
    if (json == null) return BookStyle();
    return BookStyle.fromJson(json);
  }

  static Future<void> saveBookStyle(BookStyle bookStyle) async {
    await _require.setString(bookStyleKey, bookStyle.toJson());
  }

  static void removeBookStyle() {
    _require.remove(bookStyleKey);
  }

  static bool get useBookStyles =>
      _require.getBool(useBookStylesKey) ?? false;

  static set useBookStyles(bool status) {
    _require.setBool(useBookStylesKey, status);
  }

  // ---- reading rules ----

  static set readingRules(ReadingRules rules) {
    _require.setString(readingRulesKey, rules.toJson().toString());
  }

  static ReadingRules get readingRules {
    final json = _require.getString(readingRulesKey);
    if (json == null) {
      return ReadingRules(
        convertChineseMode: ConvertChineseMode.none,
        bionicReading: false,
      );
    }
    return ReadingRules.fromJson(json);
  }

  // ---- writing / alignment ----

  static WritingModeEnum get writingMode =>
      WritingModeEnum.fromCode(_require.getString(writingModeKey) ?? 'auto');

  static set writingMode(WritingModeEnum mode) {
    _require.setString(writingModeKey, mode.code);
  }

  static TextAlignmentEnum get textAlignment => TextAlignmentEnum.fromCode(
      _require.getString(textAlignmentKey) ?? 'auto');

  static set textAlignment(TextAlignmentEnum alignment) {
    _require.setString(textAlignmentKey, alignment.code);
  }

  // ---- page turn ----

  static PageTurn get pageTurnStyle {
    final name = _require.getString(pageTurnStyleKey);
    if (name == null) return PageTurn.slide;
    return PageTurn.values.firstWhere(
      (e) => e.name == name,
      orElse: () => PageTurn.slide,
    );
  }

  static set pageTurnStyle(PageTurn style) {
    _require.setString(pageTurnStyleKey, style.name);
  }

  static String get pageTurnMode =>
      _require.getString(pageTurnModeKey) ?? 'simple';

  static set pageTurnMode(String mode) {
    _require.setString(pageTurnModeKey, mode);
  }

  static int get pageTurningType =>
      _require.getInt(pageTurningTypeKey) ?? 0;

  static set pageTurningType(int type) {
    _require.setInt(pageTurningTypeKey, type);
  }

  static List<int> get customPageTurnConfig {
    final raw = _require.getString(customPageTurnConfigKey);
    if (raw == null) {
      // Index: 0=none, 1=next, 2=prev, 3=menu
      return [2, 3, 1, 2, 3, 1, 2, 3, 1];
    }
    return raw.split(',').map(int.parse).toList();
  }

  static set customPageTurnConfig(List<int> config) {
    _require.setString(customPageTurnConfigKey, config.join(','));
  }
}
