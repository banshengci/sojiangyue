import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/models/book_notes_state.dart';

/// 笔记列表/导出排序与批注默认样式的领域访问层。
class NotesPrefs {
  NotesPrefs._();

  static const String exportMergeChaptersKey = 'notesExportMergeChapters';
  static const String exportSortFieldKey = 'notesExportSortField';
  static const String exportSortDirectionKey = 'notesExportSortDirection';
  static const String viewSortFieldKey = 'notesViewSortField';
  static const String viewSortDirectionKey = 'notesViewSortDirection';
  static const String annotationTypeKey = 'annotationType';
  static const String annotationColorKey = 'annotationColor';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'NotesPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static bool get exportMergeChapters =>
      _require.getBool(exportMergeChaptersKey) ?? true;

  static set exportMergeChapters(bool value) {
    _require.setBool(exportMergeChaptersKey, value);
  }

  static NotesSortField get exportSortField =>
      NotesSortField.values.firstWhere(
        (f) => f.name == _require.getString(exportSortFieldKey),
        orElse: () => NotesSortField.cfi,
      );

  static set exportSortField(NotesSortField field) {
    _require.setString(exportSortFieldKey, field.name);
  }

  static SortDirection get exportSortDirection =>
      SortDirection.values.firstWhere(
        (d) => d.name == _require.getString(exportSortDirectionKey),
        orElse: () => SortDirection.asc,
      );

  static set exportSortDirection(SortDirection direction) {
    _require.setString(exportSortDirectionKey, direction.name);
  }

  static NotesSortField get viewSortField => NotesSortField.values.firstWhere(
        (f) => f.name == _require.getString(viewSortFieldKey),
        orElse: () => NotesSortField.cfi,
      );

  static set viewSortField(NotesSortField field) {
    _require.setString(viewSortFieldKey, field.name);
  }

  static SortDirection get viewSortDirection =>
      SortDirection.values.firstWhere(
        (d) => d.name == _require.getString(viewSortDirectionKey),
        orElse: () => SortDirection.asc,
      );

  static set viewSortDirection(SortDirection direction) {
    _require.setString(viewSortDirectionKey, direction.name);
  }

  static String get annotationType =>
      _require.getString(annotationTypeKey) ?? 'highlight';

  static set annotationType(String style) {
    _require.setString(annotationTypeKey, style);
  }

  static String get annotationColor =>
      _require.getString(annotationColorKey) ?? '66CCFF';

  static set annotationColor(String color) {
    _require.setString(annotationColorKey, color);
  }
}
