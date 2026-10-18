import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/plugin/plugin_npc_runner.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

/// 临时角色生成与会话级增强器。
///
/// 临时角色的风险在于「模型输出不可控」：它可能加围栏、加解释、
/// 或干脆只回一个名字。解析必须能救回来，且**认不出时返回 null**，
/// 不能把一段解释当成人名塞进会话。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parseNpcOutput', () {
    test('标准 JSON', () {
      final npc = parseNpcOutput('{"name":"柳三娘","why":"来还伞"}');
      expect(npc?.name, '柳三娘');
      expect(npc?.why, '来还伞');
    });

    test('带代码块围栏', () {
      final npc = parseNpcOutput('```json\n{"name":"柳三娘","why":"来还伞"}\n```');
      expect(npc?.name, '柳三娘');
    });

    test('前后有解释也能捞出 JSON', () {
      final npc = parseNpcOutput(
        '好的，我想到了这样一个人：\n{"name":"柳三娘","why":"来还伞"}\n希望合适。',
      );
      expect(npc?.name, '柳三娘');
    });

    test('只回一个名字时兜底', () {
      final npc = parseNpcOutput('柳三娘');
      expect(npc?.name, '柳三娘');
      expect(npc?.why, '');
    });

    test('名字过长不认（多半是解释而不是名字）', () {
      final npc = parseNpcOutput('这是一个很长的句子，用来测试长度限制是否生效。');
      expect(npc, isNull);
    });

    test('空输入返回 null', () {
      expect(parseNpcOutput(''), isNull);
      expect(parseNpcOutput('   '), isNull);
    });

    test('JSON 缺 name 时走兜底而不是崩', () {
      final npc = parseNpcOutput('{"why":"没有名字"}');
      // 第一行是整段 JSON，超长 → null
      expect(npc, isNull);
    });
  });

  group('buildNpcPrompt', () {
    const gen = PluginNpcGenerator(
      id: 'visitor',
      title: '引入来客',
      direction: '生成一名与当前冲突有关的来客',
    );

    test('包含方向、在场人物与情境', () {
      final p = buildNpcPrompt(
        generator: gen,
        bookTitle: '红楼梦',
        members: ['林黛玉', '贾宝玉'],
        scene: '雨夜书房',
      );
      expect(p, contains('红楼梦'));
      expect(p, contains('林黛玉、贾宝玉'));
      expect(p, contains('雨夜书房'));
      expect(p, contains('与当前冲突有关'));
      expect(p, contains('JSON'));
    });

    test('没有情境时不出现空情境行', () {
      final p = buildNpcPrompt(
        generator: gen,
        bookTitle: '红楼梦',
        members: const [],
      );
      expect(p, isNot(contains('当前情境')));
    });

    test('要求避免占位名与重名', () {
      final p = buildNpcPrompt(
        generator: gen,
        bookTitle: '红楼梦',
        members: const ['林黛玉'],
      );
      expect(p, contains('不能和在场的人重名'));
      expect(p, contains('占位名'));
    });
  });

  group('会话级增强器开关', () {
    test('默认关闭，开启后读得到', () {
      final reg = PluginRegistry.instance;
      expect(reg.isEnhancerEnabledIn(123, 'p.one', 'short'), isFalse);
      reg.setEnhancerEnabledIn(123, 'p.one', 'short', true);
      expect(reg.isEnhancerEnabledIn(123, 'p.one', 'short'), isTrue);
    });

    test('按会话隔离', () {
      final reg = PluginRegistry.instance;
      reg.setEnhancerEnabledIn(1, 'p.one', 'short', true);
      expect(reg.isEnhancerEnabledIn(2, 'p.one', 'short'), isFalse);
    });

    test('清掉会话后回到关闭', () {
      final reg = PluginRegistry.instance;
      reg.setEnhancerEnabledIn(9, 'p.one', 'short', true);
      reg.clearSessionEnhancers(9);
      expect(reg.isEnhancerEnabledIn(9, 'p.one', 'short'), isFalse);
    });

    test('没有任何插件时，会话规则为空（不崩）', () {
      expect(
        PluginRegistry.instance.enhancerRulesForSession(1),
        isEmpty,
      );
    });
  });
}
