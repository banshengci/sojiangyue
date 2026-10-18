import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/plugin/builtin/reading_assistant_plugins.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

/// 钩子与安装策略的可验证部分。
///
/// 钩子最容易出的问题不是"分发写错了"，而是**根本没人触发**——
/// 声明了 onSelectText，阅读器却从不调用，插件装上去一声不响。
/// 这里钉住两件能静态验证的事：
/// 1. 内置插件确实声明了对应事件
/// 2. 没有任何插件监听时，宿主不该声称有钩子（否则每次划词都白跑）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('内置插件的钩子声明', () {
    test('摘句卡监听 onSelectText（阅读器划词会触发它）', () {
      const plugin = QuoteCardPlugin();
      expect(
        plugin.hooks.any((h) => h.event == PluginEventType.onSelectText),
        isTrue,
      );
      expect(plugin.hooks.single.toolId, 'make_quote_card');
    });

    test('章节回顾监听 onChapterEnter', () {
      const plugin = ChapterRecapPlugin();
      expect(
        plugin.hooks.any((h) => h.event == PluginEventType.onChapterEnter),
        isTrue,
      );
    });

    test('共读提问没有钩子（纯工具）', () {
      const plugin = DiscussionQuestionsPlugin();
      expect(plugin.hooks, isEmpty);
    });
  });

  group('hasHooksFor', () {
    test('没有动态插件时任何事件都返回 false', () {
      final reg = PluginRegistry.instance;
      for (final e in PluginEventType.values) {
        expect(reg.hasHooksFor(e), isFalse, reason: '$e 不该声称有监听者');
      }
    });
  });

  group('事件枚举', () {
    test('六个事件都存在，onAiQuery 仍在枚举里（保留）', () {
      expect(PluginEventType.values.length, 6);
      expect(PluginEventType.values, contains(PluginEventType.onAiQuery));
      expect(PluginEventType.values, contains(PluginEventType.onPageTurn));
    });

    test('fromJson 按名称解析，未知返回 null', () {
      expect(PluginEventType.fromJson('onSelectText'),
          PluginEventType.onSelectText);
      expect(PluginEventType.fromJson('nope'), isNull);
      expect(PluginEventType.fromJson(null), isNull);
    });
  });
}
