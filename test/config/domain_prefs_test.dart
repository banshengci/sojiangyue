import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/notes_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/enums/hint_key.dart';
import 'package:songjiang_reader/enums/sync_protocol.dart';
import 'package:songjiang_reader/models/book_notes_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemePrefs.ensureInitialized();
    await SyncPrefs.ensureInitialized();
    await NotesPrefs.ensureInitialized();
    await ReadingUiPrefs.ensureInitialized();
    await AppMiscPrefs.ensureInitialized();
  });

  group('ThemePrefs', () {
    test('默认主题色为品牌松绿', () {
      // 对齐设计令牌松绿 #2E6B4F
      expect(ThemePrefs.themeColor.toARGB32(), 0xFF2E6B4F);
    });

    test('保存/读取主题模式', () async {
      await ThemePrefs.saveThemeMode('dark');
      expect(ThemePrefs.themeMode.name, 'dark');
      await ThemePrefs.saveThemeMode('light');
      expect(ThemePrefs.themeMode.name, 'light');
    });

    test('trueDark / eInk 默认 false', () {
      expect(ThemePrefs.trueDarkMode, isFalse);
      expect(ThemePrefs.eInkMode, isFalse);
      ThemePrefs.eInkMode = true;
      expect(ThemePrefs.eInkMode, isTrue);
    });
  });

  group('SyncPrefs', () {
    test('webdavStatus 默认关闭', () {
      expect(SyncPrefs.webdavStatus, isFalse);
      SyncPrefs.saveWebdavStatus(true);
      expect(SyncPrefs.webdavStatus, isTrue);
    });

    test('autoSync 默认开、仅 WiFi 默认关、完成 toast 默认开', () {
      expect(SyncPrefs.autoSync, isTrue);
      expect(SyncPrefs.onlySyncWhenWifi, isFalse);
      expect(SyncPrefs.syncCompletedToast, isTrue);
    });

    test('协议 info 读写往返', () {
      SyncPrefs.setSyncInfo(
        SyncProtocol.webdav,
        {'url': 'https://dav.example', 'username': 'u', 'password': 'p'},
      );
      final info = SyncPrefs.getSyncInfo(SyncProtocol.webdav);
      expect(info['url'], 'https://dav.example');
      expect(info['username'], 'u');
      expect(info['password'], 'p');
    });

    test('syncProtocol 可设为 null 清除', () {
      SyncPrefs.syncProtocol = 'webdav';
      expect(SyncPrefs.syncProtocol, 'webdav');
      SyncPrefs.syncProtocol = null;
      expect(SyncPrefs.syncProtocol, isNull);
    });
  });

  group('NotesPrefs', () {
    test('批注默认样式', () {
      expect(NotesPrefs.annotationType, 'highlight');
      expect(NotesPrefs.annotationColor, '66CCFF');
      NotesPrefs.annotationColor = 'FF0000';
      expect(NotesPrefs.annotationColor, 'FF0000');
    });

    test('导出合并章节默认 true', () {
      expect(NotesPrefs.exportMergeChapters, isTrue);
      NotesPrefs.exportMergeChapters = false;
      expect(NotesPrefs.exportMergeChapters, isFalse);
    });

    test('排序字段默认 cfi / asc', () {
      expect(NotesPrefs.viewSortField, NotesSortField.cfi);
      expect(NotesPrefs.viewSortDirection, SortDirection.asc);
      NotesPrefs.viewSortField = NotesSortField.createdTime;
      NotesPrefs.viewSortDirection = SortDirection.desc;
      expect(NotesPrefs.viewSortField, NotesSortField.createdTime);
      expect(NotesPrefs.viewSortDirection, SortDirection.desc);
    });
  });

  group('ReadingUiPrefs', () {
    test('提示条默认显示并可重置', () {
      expect(ReadingUiPrefs.shouldShowHint(HintKey.releaseLocalSpace), isTrue);
      ReadingUiPrefs.setShowHint(HintKey.releaseLocalSpace, false);
      expect(ReadingUiPrefs.shouldShowHint(HintKey.releaseLocalSpace), isFalse);
      ReadingUiPrefs.resetHints();
      expect(ReadingUiPrefs.shouldShowHint(HintKey.releaseLocalSpace), isTrue);
    });

    test('customCss 默认空且关闭', () {
      expect(ReadingUiPrefs.customCss, '');
      expect(ReadingUiPrefs.customCssEnabled, isFalse);
      ReadingUiPrefs.customCss = 'body { color: red; }';
      ReadingUiPrefs.customCssEnabled = true;
      expect(ReadingUiPrefs.customCss, contains('color: red'));
      expect(ReadingUiPrefs.customCssEnabled, isTrue);
    });

    test('hideStatusBar 默认 false', () {
      expect(ReadingUiPrefs.hideStatusBar, isFalse);
      ReadingUiPrefs.saveHideStatusBar(true);
      expect(ReadingUiPrefs.hideStatusBar, isTrue);
    });
  });

  group('AppMiscPrefs', () {
    test('beginDate 未写入时为 null', () {
      expect(AppMiscPrefs.beginDate, isNull);
    });

    test('lastAppVersion 读写', () {
      expect(AppMiscPrefs.lastAppVersion, isNull);
      AppMiscPrefs.lastAppVersion = '1.0.0';
      expect(AppMiscPrefs.lastAppVersion, '1.0.0');
      AppMiscPrefs.lastAppVersion = null;
      expect(AppMiscPrefs.lastAppVersion, isNull);
    });

    test('readTheme 缺省为宣纸', () {
      final theme = AppMiscPrefs.readTheme;
      expect(theme.name, '宣纸');
      expect(theme.backgroundColor.toUpperCase(), contains('FFFBF7EE'));
    });
  });
}
