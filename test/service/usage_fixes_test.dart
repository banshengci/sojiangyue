import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart'
    show chunkMentionsAny;

/// 这一轮修的四个使用问题里，能单测的两处：
/// 1. 蒸馏前按人物名筛切片（直接决定「要跑多久」）；
/// 2. 主题切换要能通知到根 MaterialApp（否则点了没反应）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('蒸馏切片过滤', () {
    test('没提到任何指定人物 → 跳过', () {
      expect(
        chunkMentionsAny('贾政在书房训话，宝玉低头不语。', ['林黛玉']),
        isFalse,
      );
    });

    test('提到任意一位 → 保留', () {
      expect(
        chunkMentionsAny('黛玉葬花，宝玉远远看着。', ['林黛玉', '宝玉']),
        isTrue,
      );
    });

    test('名字为空列表 → 全保留（等于不筛）', () {
      expect(chunkMentionsAny('随便一段', []), isTrue);
    });

    test('空白名字被忽略，不会因为空串而全保留', () {
      expect(chunkMentionsAny('随便一段', ['', '  ']), isFalse);
    });

    test('名字前后空格会被裁掉', () {
      expect(chunkMentionsAny('林黛玉来了。', ['  林黛玉  ']), isTrue);
    });
  });

  group('主题切换通知', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ThemePrefs.ensureInitialized();
    });

    test('保存 dark 后通知器变 dark', () async {
      await ThemePrefs.saveThemeMode('dark');
      expect(ThemePrefs.themeModeNotifier.value, ThemeMode.dark);
    });

    test('保存 light 后通知器变 light', () async {
      await ThemePrefs.saveThemeMode('light');
      expect(ThemePrefs.themeModeNotifier.value, ThemeMode.light);
    });

    test('未知值退回 system，而不是保持上一个', () async {
      await ThemePrefs.saveThemeMode('dark');
      await ThemePrefs.saveThemeMode('乱写的值');
      expect(ThemePrefs.themeModeNotifier.value, ThemeMode.system);
    });

    test('syncThemeModeNotifier 从 prefs 读回', () async {
      await ThemePrefs.saveThemeMode('dark');
      // 模拟重启：把通知器打回 system 再同步
      ThemePrefs.themeModeNotifier.value = ThemeMode.system;
      ThemePrefs.syncThemeModeNotifier();
      expect(ThemePrefs.themeModeNotifier.value, ThemeMode.dark);
    });
  });
}
