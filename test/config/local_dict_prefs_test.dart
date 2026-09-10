import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/config/local_dict_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDictPrefs.ensureInitialized();
    await ReadingUiPrefs.ensureInitialized();
    LocalDictPrefs.clearCache();
  });

  group('ReadingUiPrefs.dailyGoalMinutes', () {
    test('默认 0', () {
      expect(ReadingUiPrefs.dailyGoalMinutes, 0);
    });

    test('写入并 clamp', () {
      ReadingUiPrefs.dailyGoalMinutes = 30;
      expect(ReadingUiPrefs.dailyGoalMinutes, 30);
      ReadingUiPrefs.dailyGoalMinutes = 999;
      expect(ReadingUiPrefs.dailyGoalMinutes, 240);
      ReadingUiPrefs.dailyGoalMinutes = -5;
      expect(ReadingUiPrefs.dailyGoalMinutes, 0);
    });
  });

  group('LocalDictPrefs lookup', () {
    test('无词典时 lookup 返回 null', () async {
      expect(await LocalDictPrefs.lookup('hello'), isNull);
      expect(LocalDictPrefs.path, isNull);
    });

    test('从 JSON 文件加载并查询', () async {
      final dir = Directory.systemTemp.createTempSync('dict_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/d.json');
      await file.writeAsString('{"hello": "你好", "serendipity": "机缘巧合"}');

      final ok = await LocalDictPrefs.loadFromFile(file.path);
      expect(ok, isTrue);
      expect(await LocalDictPrefs.entryCount, 2);
      expect(await LocalDictPrefs.lookup('hello'), '你好');
      expect(await LocalDictPrefs.lookup('Hello'), '你好');
      expect(await LocalDictPrefs.lookup('serendipity'), '机缘巧合');
      expect(await LocalDictPrefs.lookup('unknown'), isNull);
    });

    test('清除词典后查询为空', () async {
      final dir = Directory.systemTemp.createTempSync('dict2_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/d.json');
      await file.writeAsString('{"a": "1"}');
      await LocalDictPrefs.loadFromFile(file.path);
      LocalDictPrefs.path = null;
      LocalDictPrefs.clearCache();
      expect(await LocalDictPrefs.lookup('a'), isNull);
    });
  });
}
