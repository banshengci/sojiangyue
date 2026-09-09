import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/bookshelf_folder_style.dart';
import 'package:songjiang_reader/enums/sort_field.dart';
import 'package:songjiang_reader/enums/sort_order.dart';

/// 书架排序 / 封面 / 底栏显示的领域访问层。
class BookshelfPrefs {
  BookshelfPrefs._();

  static const String sortFieldKey = 'sortField';
  static const String sortOrderKey = 'sortOrder';
  static const String folderStyleKey = 'bookshelfFolderStyle';
  static const String coverWidthKey = 'bookCoverWidth';
  static const String showTitleOnCoverKey = 'showBookTitleOnDefaultCover';
  static const String showAuthorOnCoverKey = 'showAuthorOnDefaultCover';
  static const String openBookAnimationKey = 'openBookAnimation';
  static const String bottomNavNoteKey = 'bottomNavigatorShowNote';
  static const String bottomNavStatsKey = 'bottomNavigatorShowStatistics';
  static const String bottomNavAiKey = 'bottomNavigatorShowAI';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'BookshelfPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static SortFieldEnum get sortField => SortFieldEnum.values.firstWhere(
        (e) => e.name == _require.getString(sortFieldKey),
        orElse: () => SortFieldEnum.lastReadTime,
      );

  static set sortField(SortFieldEnum field) {
    _require.setString(sortFieldKey, field.name);
  }

  static SortOrderEnum get sortOrder => SortOrderEnum.values.firstWhere(
        (e) => e.name == _require.getString(sortOrderKey),
        orElse: () => SortOrderEnum.descending,
      );

  static set sortOrder(SortOrderEnum order) {
    _require.setString(sortOrderKey, order.name);
  }

  static BookshelfFolderStyle get folderStyle => BookshelfFolderStyle.fromCode(
      _require.getString(folderStyleKey) ??
          BookshelfFolderStyle.stacked.code);

  static set folderStyle(BookshelfFolderStyle style) {
    _require.setString(folderStyleKey, style.code);
  }

  static double get coverWidth => _require.getDouble(coverWidthKey) ?? 120;

  static set coverWidth(double width) {
    _require.setDouble(coverWidthKey, width);
  }

  static bool get showTitleOnDefaultCover =>
      _require.getBool(showTitleOnCoverKey) ?? true;

  static set showTitleOnDefaultCover(bool status) {
    _require.setBool(showTitleOnCoverKey, status);
  }

  static bool get showAuthorOnDefaultCover =>
      _require.getBool(showAuthorOnCoverKey) ?? true;

  static set showAuthorOnDefaultCover(bool status) {
    _require.setBool(showAuthorOnCoverKey, status);
  }

  static bool get openBookAnimation =>
      _require.getBool(openBookAnimationKey) ?? true;

  static set openBookAnimation(bool status) {
    _require.setBool(openBookAnimationKey, status);
  }

  static bool get bottomNavShowNote =>
      _require.getBool(bottomNavNoteKey) ?? true;

  static set bottomNavShowNote(bool status) {
    _require.setBool(bottomNavNoteKey, status);
  }

  static bool get bottomNavShowStatistics =>
      _require.getBool(bottomNavStatsKey) ?? true;

  static set bottomNavShowStatistics(bool status) {
    _require.setBool(bottomNavStatsKey, status);
  }

  static bool get bottomNavShowAi =>
      _require.getBool(bottomNavAiKey) ?? true;

  static set bottomNavShowAi(bool status) {
    _require.setBool(bottomNavAiKey, status);
  }
}
