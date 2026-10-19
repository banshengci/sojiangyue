import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_judge.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_modes.dart';
import 'package:songjiang_reader/service/gameplay/official_gameplay_packs.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_setup.dart';

/// 一份典型的三段开局（规则怪谈）。
const String rawSetup = '''
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

/// 玩法「不只是聊天」的那一半：规则对玩家可见、结局由程序判定、分幕按剧情推进。
///
/// 在这之前，玩法层只是把模型自报的数字显示出来：
///   · 暗牌（规则怪谈的四条规则、海龟汤的汤面）玩家根本看不到，只能听角色讲；
///   · `ended` 由模型在状态块里自己写，玩家永远赢不了也输不了；
///   · 分幕按 `回合数 ~/ 3` 硬推，玩家什么都没干也会自动换幕。
void main() {
  group('开局设定结构化', () {
    const raw = rawSetup;

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

  group('判官', () {
    test('提示词把规则逐条列出，并要求只输出 JSON', () {
      final prompt = GameplayJudge.buildViolationPrompt(
        setup: GameplaySetup.parse(rawSetup),
        playerAction: '我数了一下楼梯，一共十三级。',
      );
      expect(prompt, contains('1. 听到有人喊你名字'));
      expect(prompt, contains('不要数楼梯的台阶'));
      expect(prompt, contains('{"violated": 0}'));
      expect(prompt, contains('我数了一下楼梯'));
    });

    test('没规则时不调用判官（直接放行）', () async {
      final verdict = await GameplayJudge.checkViolation(
        mode: kBuiltinGameplayModes.firstWhere((m) => m.id == 'horror-rule'),
        setup: const GameplaySetup(),
        playerAction: '随便说点什么',
      );
      expect(verdict.violated, isFalse);
    });

    test('指认提示词带上真相与玩家提交的内容', () {
      final prompt = GameplayJudge.buildAccusationPrompt(
        setup: GameplaySetup.parse(rawSetup),
        suspect: '姬动',
        method: '用冰锥',
      );
      expect(prompt, contains('规则 2 是致命的'));
      expect(prompt, contains('凶手：姬动'));
      expect(prompt, contains('手法：用冰锥'));
      expect(prompt, contains('{"correct": true'));
    });
  });

  group('门槛事件', () {
    final horror =
        kBuiltinGameplayModes.firstWhere((m) => m.id == 'horror-rule');

    GameplaySession fresh() => GameplaySession(
          chatSessionId: 1,
          modeId: horror.id,
          stats: {for (final d in horror.stats) d.key: d.initial},
        );

    test('跨线时产生旁白，并且只触发一次', () {
      final first = GameplayRuntime.apply(
        mode: horror,
        session: fresh(),
        turn: const GameplayTurn(displayText: '', deltas: {'violations': 1}),
      );
      expect(first.events, contains('已经破过一次规矩了，那些东西开始注意到你。'));

      final second = GameplayRuntime.apply(
        mode: horror,
        session: first.session,
        turn: const GameplayTurn(displayText: '', deltas: {'violations': 1}),
      );
      expect(second.events, isNot(contains('已经破过一次规矩了，那些东西开始注意到你。')),
          reason: '同一道门槛不该每轮重复播');
    });

    test('跨过之后写进设定，模型才知道局势变了', () {
      final s = GameplayRuntime.apply(
        mode: horror,
        session: fresh(),
        turn: const GameplayTurn(displayText: '', deltas: {'violations': 1}),
      ).session;
      final directive = GameplayRuntime.buildDirective(mode: horror, session: s);
      expect(directive, contains('已经发生的转折'));
      expect(directive, contains('已经破过一次规矩'));
    });

    test('按成员记的状态（好感）也能跨线', () {
      final dating =
          kBuiltinGameplayModes.firstWhere((m) => m.id == 'dating-sim');
      final s = GameplaySession(
        chatSessionId: 1,
        modeId: dating.id,
        stats: {for (final d in dating.stats) d.key: d.initial},
      );
      final result = GameplayRuntime.apply(
        mode: dating,
        session: s,
        turn: const GameplayTurn(displayText: '', deltas: {'好感|林黛玉': 50}),
      );
      expect(result.events, contains('对方开始主动了，愿意多留一会儿。'));
    });
  });

  group('玩法声明了哪些机制', () {
    test('规则怪谈交给判官判违规', () {
      final m = kBuiltinGameplayModes.firstWhere((x) => x.id == 'horror-rule');
      expect(m.judged, isTrue);
    });

    test('指认：剧本杀与海龟汤（后者叫「说出真相」）', () {
      final accusing =
          kBuiltinGameplayModes.where((m) => m.accusation).toList();
      expect(accusing.map((m) => m.id), containsAll(['murder-mystery', 'haigui-soup']));

      final mm = kBuiltinGameplayModes.firstWhere((m) => m.id == 'murder-mystery');
      final win = mm.endings.firstWhere((e) => e.win);
      expect(win.statKey, 'suspicion');
      expect(win.atLeast, 100);

      final soup = kBuiltinGameplayModes.firstWhere((m) => m.id == 'haigui-soup');
      expect(soup.accusationLabel, '说出真相');
    });

    test('辩论的收局条件在两端', () {
      final debate = kBuiltinGameplayModes.firstWhere((m) => m.id == 'debate');
      expect(debate.endings.any((e) => e.atLeast == 100), isTrue);
      expect(debate.endings.any((e) => e.atMost == 0), isTrue);
    });

    test('机制字段能进玩法包 JSON（装机/导出不丢）', () {
      final horror =
          kBuiltinGameplayModes.firstWhere((m) => m.id == 'horror-rule');
      final back = GameplayMode.fromJson(horror.toJson());
      expect(back.judged, horror.judged);
      expect(back.endings.length, horror.endings.length);
      expect(back.thresholds.length, horror.thresholds.length);

      final mm = kBuiltinGameplayModes.firstWhere((m) => m.id == 'murder-mystery');
      final mmBack = GameplayMode.fromJson(mm.toJson());
      expect(mmBack.accusation, isTrue);
      expect(mmBack.accusationLabel, '指认');
      expect(mmBack.endings.first.atLeast, 100);
    });
  });

  // 这条是给「玩法只是聊天」这个反馈兜底的：
  // 以后新增玩法如果只写 directive，没有收局也没有门槛，这里会红。
  group('每个玩法都不是纯提示词', () {
    final modes = <GameplayMode>[
      ...kBuiltinGameplayModes,
      for (final pack in kOfficialGameplayPacks)
        ...pack.gameplayModesJson.map(GameplayMode.fromJson),
    ];

    test('内置 + 官方包，每个都有收局或门槛', () {
      expect(modes, isNotEmpty);
      for (final m in modes) {
        expect(
          m.endings.isNotEmpty || m.thresholds.isNotEmpty,
          isTrue,
          reason: '「${m.name}」既没有收局条件也没有门槛事件',
        );
      }
    });

    test('有状态量的玩法，状态必须能影响点什么', () {
      for (final m in modes.where((m) => m.stats.isNotEmpty)) {
        final touched = <String>{
          ...m.endings.map((e) => e.statKey),
          ...m.thresholds.map((e) => e.statKey),
        };
        expect(
          m.stats.any((s) => touched.contains(s.key)),
          isTrue,
          reason: '「${m.name}」的状态量涨跌不产生任何后果',
        );
      }
    });

    test('每个官方包至少有一个能赢的结局', () {
      for (final pack in kOfficialGameplayPacks) {
        final m = GameplayMode.fromJson(pack.gameplayModesJson.first);
        expect(
          m.endings.any((e) => e.win) || m.thresholds.any((e) => e.atLeast != null),
          isTrue,
          reason: '「${m.name}」没有可追求的目标',
        );
      }
    });
  });

  group('按人记的状态也能触发结局', () {
    test('某一个人的好感到 90 就收局（恋爱模拟）', () {
      final dating =
          kBuiltinGameplayModes.firstWhere((m) => m.id == 'dating-sim');
      final s = GameplaySession(
        chatSessionId: 1,
        modeId: dating.id,
        stats: {for (final d in dating.stats) d.key: d.initial},
      );
      final result = GameplayRuntime.apply(
        mode: dating,
        session: s,
        turn: const GameplayTurn(displayText: '', deltas: {'好感|林黛玉': 80}),
      );
      // 初始 10 + 80 = 90 → 命中「这段关系走成了」
      expect(result.session.ended, isTrue);
      expect(result.ending?.win, isTrue);
    });
  });

  group('判官结算与模型一轮合并', () {
    test('合并后回合只加一次，两边的数值相加', () {
      final base = const GameplayTurn(
        displayText: '灯灭了。',
        deltas: {'sanity': -5},
        note: '异象',
      );
      final merged = GameplayRuntime.merge(
        base,
        deltas: {'violations': 1, 'sanity': -8},
        note: '违反规则 2',
      );
      expect(merged.deltas['sanity'], -13);
      expect(merged.deltas['violations'], 1);
      expect(merged.note, '违反规则 2');
      expect(merged.displayText, '灯灭了。');
      expect(base.deltas['sanity'], -5, reason: '不能改到原对象');
    });
  });
}
