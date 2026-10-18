import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/plugin/plugin_rules.dart';

/// 插件规则引擎。
///
/// 这类"满足条件就自动做点什么"的逻辑，错法很集中：
/// 概率边界写反、轮数取模差一、重试时状态重复累计。
/// 所以测试重点在**边界与重入**，而不是"能不能跑通"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PluginRule rule({
    String id = 'r1',
    RuleEvent event = RuleEvent.afterTurn,
    RuleMatch match = const RuleMatch(),
    List<RuleAction> actions = const [
      RuleAction(type: RuleActionType.incrementState, key: 'refusals', amount: 1),
    ],
  }) =>
      PluginRule(id: id, title: id, event: event, match: match, actions: actions);

  List<({String pluginId, PluginRule rule})> rulesOf(List<PluginRule> rs,
          {String pluginId = 'p.one'}) =>
      [for (final r in rs) (pluginId: pluginId, rule: r)];

  group('解析', () {
    test('蛇形事件与字符串数字都能认', () {
      final r = PluginRule.fromJson({
        'id': 'x',
        'event': 'before_generation',
        'match': {'every_turns': '5', 'chance_percent': '30', 'keywords': ['拒绝']},
        'actions': [
          {'type': 'add_instruction', 'instruction': '来个商人'},
          {'type': 'increment_state', 'key': 'n', 'amount': 2},
        ],
      });
      expect(r, isNotNull);
      expect(r!.event, RuleEvent.beforeGeneration);
      expect(r.match.everyTurns, 5);
      expect(r.match.chancePercent, 30);
      expect(r.match.keywords, ['拒绝']);
      expect(r.actions.length, 2);
      expect(r.actions.last.amount, 2);
    });

    test('没有 actions / 事件非法的规则被丢弃', () {
      expect(PluginRule.fromJson({'id': 'a', 'event': 'after_turn'}), isNull);
      expect(
        PluginRule.fromJson({
          'id': 'b',
          'event': '不存在的时机',
          'actions': [
            {'type': 'increment_state', 'key': 'k'},
          ],
        }),
        isNull,
      );
    });

    test('空指令的 add_instruction 被丢弃', () {
      expect(
        PluginRule.fromJson({
          'id': 'c',
          'event': 'after_turn',
          'actions': [
            {'type': 'add_instruction', 'instruction': '   '},
          ],
        }),
        isNull,
      );
    });
  });

  group('匹配：每 N 轮', () {
    test('第 5 轮触发，第 4 轮不触发', () {
      final rules = rulesOf([rule(match: const RuleMatch(everyTurns: 5))]);
      final at4 = evaluateRules(
        rules: rules,
        event: RuleEvent.afterTurn,
        turn: 4,
        userInput: '',
      );
      final at5 = evaluateRules(
        rules: rules,
        event: RuleEvent.afterTurn,
        turn: 5,
        userInput: '',
      );
      expect(at4.stateDelta, isEmpty);
      expect(at5.stateDelta['refusals'], 1);
    });

    test('第 0 轮不因取模而误触发', () {
      final eval = evaluateRules(
        rules: rulesOf([rule(match: const RuleMatch(everyTurns: 5))]),
        event: RuleEvent.afterTurn,
        turn: 0,
        userInput: '',
      );
      expect(eval.stateDelta, isEmpty);
    });
  });

  group('匹配：概率', () {
    test('0% 永不触发，100% 必触发', () {
      final zero = evaluateRules(
        rules: rulesOf([rule(match: const RuleMatch(chancePercent: 0))]),
        event: RuleEvent.afterTurn,
        turn: 1,
        userInput: '',
        random: Random(1),
      );
      final hundred = evaluateRules(
        rules: rulesOf([rule(match: const RuleMatch(chancePercent: 100))]),
        event: RuleEvent.afterTurn,
        turn: 1,
        userInput: '',
        random: Random(1),
      );
      expect(zero.stateDelta, isEmpty);
      expect(hundred.stateDelta['refusals'], 1);
    });
  });

  group('匹配：关键词', () {
    test('命中任一关键词即触发', () {
      final rules = rulesOf([
        rule(match: const RuleMatch(keywords: ['拒绝', '不买'])),
      ]);
      expect(
        evaluateRules(
          rules: rules,
          event: RuleEvent.afterTurn,
          turn: 1,
          userInput: '我不买',
        ).stateDelta['refusals'],
        1,
      );
      expect(
        evaluateRules(
          rules: rules,
          event: RuleEvent.afterTurn,
          turn: 1,
          userInput: '再想想',
        ).stateDelta,
        isEmpty,
      );
    });
  });

  group('匹配：多条件取交集', () {
    test('轮数对但关键词不中 → 不触发', () {
      final eval = evaluateRules(
        rules: rulesOf([
          rule(
            match: const RuleMatch(everyTurns: 2, keywords: ['拒绝']),
          ),
        ]),
        event: RuleEvent.afterTurn,
        turn: 2,
        userInput: '好的',
      );
      expect(eval.stateDelta, isEmpty);
    });

    test('轮数与关键词都满足 → 触发', () {
      final eval = evaluateRules(
        rules: rulesOf([
          rule(
            match: const RuleMatch(everyTurns: 2, keywords: ['拒绝']),
          ),
        ]),
        event: RuleEvent.afterTurn,
        turn: 2,
        userInput: '我拒绝',
      );
      expect(eval.stateDelta['refusals'], 1);
    });
  });

  group('事件分离', () {
    test('before_generation 的规则不会在 after_turn 结算里生效', () {
      final before = rule(
        event: RuleEvent.beforeGeneration,
        actions: const [
          RuleAction(type: RuleActionType.addInstruction, instruction: '来个商人'),
        ],
      );
      final evalAfter = evaluateRules(
        rules: rulesOf([before]),
        event: RuleEvent.afterTurn,
        turn: 1,
        userInput: '',
      );
      expect(evalAfter.instructions, isEmpty);
    });

    test('指令只出现在对应事件', () {
      final evalBefore = evaluateRules(
        rules: rulesOf([
          rule(
            event: RuleEvent.beforeGeneration,
            actions: const [
              RuleAction(type: RuleActionType.addInstruction, instruction: '来个商人'),
            ],
          ),
        ]),
        event: RuleEvent.beforeGeneration,
        turn: 1,
        userInput: '',
      );
      expect(evalBefore.instructions, ['来个商人']);
    });
  });

  group('同回合去重', () {
    test('重试时状态不重复累计，但指令仍然给出', () {
      final r = rule(
        event: RuleEvent.afterTurn,
        actions: const [
          RuleAction(type: RuleActionType.addInstruction, instruction: '提示'),
          RuleAction(type: RuleActionType.incrementState, key: 'n', amount: 1),
        ],
      );
      final first = evaluateRules(
        rules: rulesOf([r]),
        event: RuleEvent.afterTurn,
        turn: 3,
        userInput: '',
      );
      expect(first.stateDelta['n'], 1);

      final second = evaluateRules(
        rules: rulesOf([r]),
        event: RuleEvent.afterTurn,
        turn: 3,
        userInput: '',
        appliedKeys: first.appliedKeys,
      );
      expect(second.stateDelta, isEmpty, reason: '同回合不该再累计');
      expect(second.instructions, ['提示'], reason: '指令仍需注入');
    });

    test('下一回合可以再次累计', () {
      final r = rule();
      final first = evaluateRules(
        rules: rulesOf([r]),
        event: RuleEvent.afterTurn,
        turn: 3,
        userInput: '',
      );
      final next = evaluateRules(
        rules: rulesOf([r]),
        event: RuleEvent.afterTurn,
        turn: 4,
        userInput: '',
        appliedKeys: first.appliedKeys,
      );
      expect(next.stateDelta['refusals'], 1);
    });
  });

  group('描述文案', () {
    test('条件与事件说成人话', () {
      expect(describeRuleMatch(const RuleMatch()), '每轮');
      expect(describeRuleMatch(const RuleMatch(everyTurns: 5)), '每 5 轮');
      expect(describeRuleMatch(const RuleMatch(chancePercent: 30)), '30% 概率');
      expect(
        describeRuleMatch(const RuleMatch(keywords: ['拒绝'])),
        '提到「拒绝」',
      );
      expect(
        describeRuleMatch(const RuleMatch(everyTurns: 2, chancePercent: 50)),
        '每 2 轮 + 50% 概率',
      );
      expect(describeRuleEvent(RuleEvent.beforeGeneration), '生成前');
      expect(describeRuleEvent(RuleEvent.afterTurn), '回合后');
    });
  });

  group('状态持久化', () {
    test('写入后能读回，且键保留', () async {
      await PluginRuleStateStore.save(
        'p.one',
        7,
        state: {'n': 3},
        appliedKeys: {'k1', 'k2'},
      );
      final loaded = await PluginRuleStateStore.load('p.one', 7);
      expect(loaded.state['n'], 3);
      expect(loaded.appliedKeys, containsAll(['k1', 'k2']));
    });

    test('按会话隔离', () async {
      await PluginRuleStateStore.save('p.one', 1, state: {'n': 1}, appliedKeys: {});
      final other = await PluginRuleStateStore.load('p.one', 2);
      expect(other.state, isEmpty);
    });

    test('没有记录时返回空状态（不抛异常）', () async {
      final s = await PluginRuleStateStore.load('p.none', 99);
      expect(s.state, isEmpty);
      expect(s.appliedKeys, isEmpty);
    });
  });
  group('写入插件存储（set_storage）', () {
    test('解析出 key 与 value', () {
      final r = PluginRule.fromJson({
        'id': 'x',
        'event': 'after_turn',
        'actions': [
          {'type': 'set_storage', 'key': 'record', 'value': '第 {{turn}} 轮'},
        ],
      });
      expect(r, isNotNull);
      expect(r!.actions.single.key, 'record');
      expect(r.actions.single.value, '第 {{turn}} 轮');
    });

    test('缺 key 或 value 的动作被丢弃', () {
      expect(
        PluginRule.fromJson({
          'id': 'x',
          'event': 'after_turn',
          'actions': [
            {'type': 'set_storage', 'key': 'k'},
          ],
        }),
        isNull,
      );
      expect(
        PluginRule.fromJson({
          'id': 'x',
          'event': 'after_turn',
          'actions': [
            {'type': 'set_storage', 'value': 'v'},
          ],
        }),
        isNull,
      );
    });

    test('求值产出 storageWrites', () {
      final eval = evaluateRules(
        rules: rulesOf([
          rule(
            actions: const [
              RuleAction(
                type: RuleActionType.setStorage,
                key: 'record',
                value: '第 {{turn}} 轮',
              ),
            ],
          ),
        ]),
        event: RuleEvent.afterTurn,
        turn: 3,
        userInput: '',
      );
      expect(eval.storageWrites['record'], '第 {{turn}} 轮');
    });

    test('同回合重试不会重复写入', () {
      final r = rule(
        actions: const [
          RuleAction(type: RuleActionType.setStorage, key: 'k', value: 'v'),
        ],
      );
      final first = evaluateRules(
        rules: rulesOf([r]),
        event: RuleEvent.afterTurn,
        turn: 2,
        userInput: '',
      );
      final second = evaluateRules(
        rules: rulesOf([r]),
        event: RuleEvent.afterTurn,
        turn: 2,
        userInput: '',
        appliedKeys: first.appliedKeys,
      );
      expect(first.storageWrites, isNotEmpty);
      expect(second.storageWrites, isEmpty);
    });
  });

  group('renderRuleValue', () {
    test('替换 {{turn}}', () {
      expect(renderRuleValue('第 {{turn}} 轮', turn: 5), '第 5 轮');
    });

    test('替换 {{state.key}}', () {
      expect(
        renderRuleValue('拒绝 {{state.refusals}} 次', turn: 1, state: {'refusals': 3}),
        '拒绝 3 次',
      );
    });

    test('未知占位保留原样，不静默变空', () {
      expect(renderRuleValue('{{unknown}}', turn: 1), '{{unknown}}');
      expect(renderRuleValue('{{state.nope}}', turn: 1), '{{state.nope}}');
    });

    test('混合占位', () {
      expect(
        renderRuleValue('t{{turn}}-n{{state.n}}', turn: 2, state: {'n': 9}),
        't2-n9',
      );
    });
  });

}
