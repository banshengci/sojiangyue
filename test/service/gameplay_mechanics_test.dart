import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_modes.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_setup.dart';

/// 玩法「不只是聊天」的那一半：规则对玩家可见、结局由程序判定、分幕按剧情推进。
///
/// 在这之前，玩法层只是把模型自报的数字显示出来：
///   · 暗牌（规则怪谈的四条规则、海龟汤的汤面）玩家根本看不到，只能听角色讲；
///   · `ended` 由模型在状态块里自己写，玩家永远赢不了也输不了；
///   · 分幕按 `回合数 ~/ 3` 硬推，玩家什么都没干也会自动换幕。
void main() {
  group('开局设定结构化', () {
    const raw = '''
【公开】
凌晨三点的医院旧楼，走廊尽头的灯一直闪。

【规则】
1. 听到有人喊你名字，先看清方向再应。
2. 不要数楼梯的台阶。
3. 电梯里只有你一个人的时候，别回头。

【暗牌】
规则 2 是致命的。数过台阶的人第二天会说不出话。
唯一的安全做法是：一直待在护士站，天亮前不要离开。
''';

    test('三段拆得开，规则一条条出来', () {
      final setup = GameplaySetup.parse(raw);
      expect(setup.publicBrief, contains('凌晨三点'));
      expect(setup.rules, hasLength(3));
      expect(setup.rules.first, '听到有人喊你名字，先看清方向再应。');
      expect(setup.secret, contains('致命'));
      expect(setup.secret, isNot(contains('凌晨三点')),
          reason: '公开信息不能混进暗牌');
      expect(setup.secret, isNot(contains('数楼梯')),
          reason: '规则不能混进暗牌');
    });

    test('「无」不算一条规则', () {
      final setup = GameplaySetup.parse('【公开】\n一个雨夜。\n【规则】\n无\n【暗牌】\n凶手是管家。');
      expect(setup.rules, isEmpty);
      expect(setup.publicBrief, '一个雨夜。');
      expect(setup.secret, '凶手是管家。');
    });

    test('旧格式（只有【汤面】【汤底】）也能读', () {
      final setup = GameplaySetup.parse('【汤面】一个人走进酒吧，要了一杯水。\n【汤底】他打嗝不止。');
      expect(setup.publicBrief, '一个人走进酒吧，要了一杯水。');
      expect(setup.secret, '他打嗝不止。');
    });

    test('认不出标记时整段当暗牌——宁可少显示，也不漏真相', () {
      final setup = GameplaySetup.parse('凶手是二少爷，用冰锥。');
      expect(setup.publicBrief, isEmpty);
      expect(setup.rules, isEmpty);
      expect(setup.hasVisible, isFalse);
      expect(setup.secret, '凶手是二少爷，用冰锥。');
    });
  });

  group('海龟汤只认三个答案', () {
    test('是 / 否 / 与此无关 都认', () {
      expect(parseYesNo('是。'), '是');
      expect(parseYesNo('「否。」'), '否');
      expect(parseYesNo('与此无关。'), '与此无关');
    });

    test('换个说法也算同一个答案', () {
      expect(parseYesNo('不是。'), '否');
      expect(parseYesNo('对，正是。'), '是');
      expect(parseYesNo('无关。'), '与此无关');
    });

    test('解释型回答不给答案（这一句才是关键）', () {
      // 模型只要多解释一句，玩家就不用猜了 —— 返回 null 才谈得上"强制"
      expect(parseYesNo('他其实是因为打嗝才要水的，你问的方向不对。'), isNull);
    });

    test('空串不崩', () {
      expect(parseYesNo('   '), isNull);
      expect(parseYesNo(''), isNull);
    });
  });

  group('结局由程序判定', () {
    final horror =
        kBuiltinGameplayModes.firstWhere((m) => m.id == 'horror-rule');

    GameplaySession fresh() => GameplaySession(
          chatSessionId: 1,
          modeId: horror.id,
          stats: {for (final d in horror.stats) d.key: d.initial},
        );

    test('规则怪谈声明了「神志耗尽」与「违规到顶」两个结局', () {
      expect(horror.endings, hasLength(2));
      expect(horror.endings.map((e) => e.statKey), containsAll(['sanity', 'violations']));
    });

    test('神志归零就收局，不用模型点头', () {
      final result = GameplayRuntime.apply(
        mode: horror,
        session: fresh(),
        turn: const GameplayTurn(displayText: '', deltas: {'神志': -100}),
      );
      expect(result.session.ended, isTrue);
      expect(result.ending, isNotNull);
      expect(result.session.stats['sanity'], 0);
      expect(
        result.session.log.last.text,
        contains('本局结束'),
        reason: '收局要留下一条可回看的记录',
      );
    });

    test('违规到三次也收局', () {
      final result = GameplayRuntime.apply(
        mode: horror,
        session: fresh().copyWith(stats: {'sanity': 80, 'violations': 3}),
        turn: const GameplayTurn(displayText: '', deltas: {}),
      );
      expect(result.session.ended, isTrue);
      expect(result.ending?.statKey, 'violations');
    });

    test('没到阈值就不收局（别把戏提前掐了）', () {
      final result = GameplayRuntime.apply(
        mode: horror,
        session: fresh(),
        turn: const GameplayTurn(displayText: '', deltas: {'神志': -5}),
      );
      expect(result.session.ended, isFalse);
      expect(result.ending, isNull);
    });
  });

  group('分幕按剧情推进', () {
    final horror =
        kBuiltinGameplayModes.firstWhere((m) => m.id == 'horror-rule');

    GameplaySession fresh() => GameplaySession(
          chatSessionId: 1,
          modeId: horror.id,
          stats: {for (final d in horror.stats) d.key: d.initial},
        );

    test('没标记 next 时，聊再多轮也不换幕', () {
      var s = fresh();
      for (var i = 0; i < 9; i++) {
        s = GameplayRuntime.apply(
          mode: horror,
          session: s,
          turn: const GameplayTurn(displayText: '', deltas: {'神志': -1}),
        ).session;
      }
      expect(s.phaseIndex, 0, reason: '原先按 turn ~/ 3 推进，跟剧情无关');
    });

    test('标记 next 才进下一幕，且不会越过最后一幕', () {
      var s = fresh();
      for (var i = 0; i < 10; i++) {
        s = GameplayRuntime.apply(
          mode: horror,
          session: s,
          turn: const GameplayTurn(displayText: '', advancePhase: true),
        ).session;
      }
      expect(s.phaseIndex, horror.phases.length - 1);
    });
  });

  group('状态块解析', () {
    test('next 与 ended 不会被当成状态量', () {
      final turn = GameplayRuntime.parse(
        '灯灭了。<sj-state>{"next": true, "ended": true, "note": "进第二幕"}</sj-state>',
      );
      expect(turn.displayText, '灯灭了。');
      expect(turn.advancePhase, isTrue);
      expect(turn.ended, isTrue);
      expect(turn.deltas, isEmpty);
      expect(turn.note, '进第二幕');
    });
  });

  group('开局提示词要求三段标记', () {
    test('提示词里带着三个标记，模型才知道怎么分段', () {
      final horror =
          kBuiltinGameplayModes.firstWhere((m) => m.id == 'horror-rule');
      final prompt = GameplayRuntime.buildSetupPrompt(
        mode: horror,
        characterName: '姬动',
      );
      expect(prompt, contains(GameplaySetup.publicTag));
      expect(prompt, contains(GameplaySetup.rulesTag));
      expect(prompt, contains(GameplaySetup.secretTag));
    });
  });
}
