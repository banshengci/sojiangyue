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

    group('违规扣什么（按玩法自己的状态量）', () {
      GameplayMode modeOf(String id) =>
          kBuiltinGameplayModes.firstWhere((m) => m.id == id);

      test('规则怪谈：扣神志、记违规次数', () {
        final d = GameplayJudge.penaltyFor(modeOf('horror-rule'), fatal: false);
        expect(d['sanity'], -8);
        expect(d['violations'], 1);
        expect(
          GameplayJudge.penaltyFor(modeOf('horror-rule'), fatal: true)['sanity'],
          -25,
        );
      });

      test('剧本杀没有 sanity/violations，扣的是它自己的主计分量', () {
        // 以前这里写死 violations +1 / sanity -25，剧本杀压根没这两个键，
        // 结算落进看不见的地方——判官判了，玩家没感觉，结局也不动。
        final d = GameplayJudge.penaltyFor(
          modeOf('murder-mystery'),
          fatal: false,
        );
        expect(d.containsKey('sanity'), isFalse);
        expect(d.containsKey('violations'), isFalse);
        expect(d.keys.single, 'clue'); // isScore 的那一项
        expect(d['clue'], -5);
      });

      test('海龟汤扣「接近真相」', () {
        final d = GameplayJudge.penaltyFor(
          modeOf('haigui-soup'),
          fatal: true,
        );
        expect(d.keys.single, 'closeness');
        expect(d['closeness'], -15);
      });

      test('扣的都是玩法里真有的状态量', () {
        final all = <GameplayMode>[
          ...kBuiltinGameplayModes,
          for (final pack in kOfficialGameplayPacks)
            ...pack.gameplayModesJson.map(GameplayMode.fromJson),
        ];
        for (final mode in all) {
          final d = GameplayJudge.penaltyFor(mode, fatal: true);
          final keys = mode.stats.map((s) => s.key).toSet();
          expect(d, isNotEmpty, reason: '「${mode.name}」违规后什么都没扣');
          for (final k in d.keys) {
            expect(keys, contains(k), reason: '「${mode.name}」扣了不存在的状态 $k');
          }
        }
      });
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

  group('玩法自带的技能', () {
    /// 一个带「每回合技能」的元叙事变体。
    Map<String, dynamic> metaWithSkill() => {
          'id': 'meta-fiction-skill',
          'name': '元叙事（带技能）',
          'directive': '本场采用元叙事。',
          'summary': '角色察觉自己在书里',
          'stats': [
            {'key': 'awareness', 'name': '觉醒度', 'max': 100, 'isScore': true},
          ],
          'scriptTools': [
            {
              'id': 'scan',
              'displayName': '觉醒度扫描',
              'description': '判断这一回合角色有没有意识到叙事装置',
              'behavior': 'aiPrompt',
              'prompt': '读这段对话，判断角色有没有意识到自己在书里：{{text}}',
            },
          ],
          'enhancers': [
            {
              'id': 'wall',
              'title': '第四面墙',
              'rule': '可以让角色察觉到读者与翻页。',
            },
          ],
          'rules': [
            {
              'id': 'echo',
              'title': '提到作者',
              'event': 'after_turn',
              'actions': [
                {
                  'type': 'add_instruction',
                  'instruction': '角色开始怀疑自己的处境。',
                },
              ],
            },
          ],
          'turnTool': 'scan',
        };

    test('JSON 往返不丢技能声明', () {
      final mode = GameplayMode.fromJson(metaWithSkill());
      expect(mode.scriptTools, hasLength(1));
      expect(mode.enhancers, hasLength(1));
      expect(mode.rules, hasLength(1));
      expect(mode.turnTool, 'scan');
      expect(mode.hasSkills, isTrue);

      final back = GameplayMode.fromJson(mode.toJson());
      expect(back.scriptTools, hasLength(1));
      expect(back.enhancers, hasLength(1));
      expect(back.rules, hasLength(1));
      expect(back.turnTool, 'scan');
    });

    test('没声明技能时 hasSkills 为假，且不生成插件清单', () {
      // 手搭一个最小玩法：没有 stats、没有 scriptTools、没开 statJudge
      final plain = GameplayMode(
        id: 'bare',
        name: '素玩法',
        icon: gameplayIconByName(null),
        summary: '',
        directive: '就是聊天。',
      );
      expect(plain.hasSkills, isFalse);
      expect(GameplayRuntime.turnToolIdFor(plain), isNull);
      expect(GameplayRuntime.buildPluginManifest(plain), isNull);
    });

    test('声明了就编译成插件清单：id 带前缀，工具/增强/规则都带过来', () {
      final mode = GameplayMode.fromJson(metaWithSkill());
      final manifest = GameplayRuntime.buildPluginManifest(mode);
      expect(manifest, isNotNull);
      expect(manifest!.id, 'gameplay.${mode.id}');
      expect(manifest.tools, hasLength(1));
      expect(manifest.enhancers, hasLength(1));
      expect(manifest.rules, hasLength(1));
      // 声明式工具要调 AI，权限必须自己带上
      expect(
        manifest.permissions.map((p) => p.value),
        contains('ai.query'),
      );
    });

    test('技能返回的 JSON 能变成状态变化量', () {
      final t = GameplayRuntime.parseSkillOutput(
        '好的，判定如下：{"awareness": 15, "note": "他提到了作者"}',
      );
      expect(t.deltas['awareness'], 15);
      expect(t.note, '他提到了作者');
    });

    test('技能返回不是 JSON 时安静返回空结果，不炸这一回合', () {
      expect(GameplayRuntime.parseSkillOutput('我觉得挺好的').hasChanges, isFalse);
      expect(GameplayRuntime.parseSkillOutput('{}').hasChanges, isFalse);
    });

    test('技能报 0 也能压掉模型自报的数值（否决）', () {
      final base = const GameplayTurn(displayText: 'x', deltas: {'awareness': 15});
      final skill = GameplayRuntime.parseSkillOutput('{"awareness": 0}');
      expect(skill.deltas['awareness'], 0, reason: '0 不能被丢掉，否则否决无效');
      final out = GameplayRuntime.overrideWith(base, skill);
      expect(out.deltas['awareness'], 0);
    });

    test('名字与 key 混写时也能对上（模型写 sanity、技能写「神志」）', () {
      final mode =
          kBuiltinGameplayModes.firstWhere((m) => m.id == 'horror-rule');
      final base = const GameplayTurn(displayText: 'x', deltas: {'sanity': -8});
      final skill = GameplayRuntime.parseSkillOutput('{"神志": -10}');
      final out = GameplayRuntime.overrideWith(base, skill, mode: mode);
      expect(out.deltas.length, 1, reason: '不能变成两项各算一遍');
      expect(out.deltas['sanity'], -10);
    });

    test('按人记的键也能归一化', () {
      final mode =
          kBuiltinGameplayModes.firstWhere((m) => m.id == 'dating-sim');
      final base = const GameplayTurn(
        displayText: 'x',
        deltas: {'affection|姬动': 5},
      );
      final skill = GameplayRuntime.parseSkillOutput('{"好感|姬动": 8}');
      final out = GameplayRuntime.overrideWith(base, skill, mode: mode);
      expect(out.deltas['affection|姬动'], 8);
      expect(out.deltas.length, 1);
    });

    test('规则里有 set_storage 才申请写权限', () {
      final withStorage = GameplayMode.fromJson({
        ...metaWithSkill(),
        'id': 'storage-mode',
        'rules': [
          {
            'id': 'save',
            'title': '记一笔',
            'event': 'after_turn',
            'actions': [
              {'type': 'set_storage', 'key': 'last', 'value': '第{{turn}}轮'},
            ],
          },
        ],
      });
      final manifest = GameplayRuntime.buildPluginManifest(withStorage)!;
      expect(
        manifest.permissions.map((p) => p.value),
        contains('storage.write'),
      );

      // 没有 set_storage 的玩法不该白拿写权限
      final plain = GameplayRuntime.buildPluginManifest(
        GameplayMode.fromJson(metaWithSkill()),
      )!;
      expect(
        plain.permissions.map((p) => p.value),
        isNot(contains('storage.write')),
      );
    });

    test('技能的结论覆盖模型自报的同名项，不翻倍', () {
      final base = const GameplayTurn(
        displayText: '……',
        deltas: {'awareness': 15, 'clue': 1},
        note: '模型自报',
      );
      final skill = GameplayRuntime.parseSkillOutput('{"awareness": 20}');
      final out = GameplayRuntime.overrideWith(base, skill);
      expect(out.deltas['awareness'], 20, reason: '技能说了算');
      expect(out.deltas['clue'], 1, reason: '技能没提的项保留');
      expect(out.displayText, '……');
    });

    test('技能没有结论时保持原样', () {
      final base = const GameplayTurn(displayText: 'x', deltas: {'clue': 1});
      final out =
          GameplayRuntime.overrideWith(base, GameplayRuntime.parseSkillOutput(''));
      expect(out.deltas['clue'], 1);
    });

    test('内置玩法全部用手写技能，不再走通用判定', () {
      for (final m in kBuiltinGameplayModes) {
        expect(m.turnTool, isNotNull, reason: '「${m.name}」没有手写技能');
        expect(m.statJudge, isFalse, reason: '「${m.name}」有手写技能就不该再开通用判定');
        expect(
          m.scriptTools.map((t) => t['id']),
          contains(m.turnTool),
          reason: '「${m.name}」的 turnTool 没有对应工具',
        );
        expect(
          GameplayRuntime.turnToolIdFor(m),
          m.turnTool,
          reason: '「${m.name}」跑的不是自己的技能',
        );
      }
    });

    test('官方包玩法也各有手写技能', () {
      final packs = <GameplayMode>[
        for (final pack in kOfficialGameplayPacks)
          ...pack.gameplayModesJson.map(GameplayMode.fromJson),
      ];
      expect(packs, isNotEmpty);
      for (final m in packs) {
        expect(m.turnTool, isNotNull, reason: '「${m.name}」没有手写技能');
        expect(
          m.scriptTools.map((t) => t['id']),
          contains(m.turnTool),
          reason: '「${m.name}」的 turnTool 没有对应工具',
        );
      }
    });

    test('每个玩法用的技能 id 都不重复（各判各的）', () {
      final all = <GameplayMode>[
        ...kBuiltinGameplayModes,
        for (final pack in kOfficialGameplayPacks)
          ...pack.gameplayModesJson.map(GameplayMode.fromJson),
      ];
      final ids = all.map((m) => m.turnTool).whereType<String>().toList();
      expect(ids.toSet().length, ids.length, reason: '有玩法共用了同一个技能 id');
    });

    test('手写技能能看到玩家发言与暗牌', () {
      // 海龟汤只回「是/否」，剧本杀要对照真相，规则怪谈要对照规则真相
      for (final id in ['murder-mystery', 'haigui-soup', 'horror-rule']) {
        final m = kBuiltinGameplayModes.firstWhere((x) => x.id == id);
        final prompt = m.scriptTools.single['prompt'] as String;
        expect(prompt, contains('{{playerInput}}'), reason: '「${m.name}」看不到玩家发言');
        expect(prompt, contains('{{secret}}'), reason: '「${m.name}」看不到暗牌');
      }
    });

    test('规则怪谈的技能不碰违规次数（那是判官的事）', () {
      final m = kBuiltinGameplayModes.firstWhere((x) => x.id == 'horror-rule');
      final prompt = m.scriptTools.single['prompt'] as String;
      expect(prompt, contains('不要输出 violations'));
      expect(prompt, contains('神志'));
      // 判官结算的 violations 不能被技能覆盖掉
      final base = const GameplayTurn(
        displayText: 'x',
        deltas: {'violations': 1, 'sanity': -8},
      );
      final skill = GameplayRuntime.parseSkillOutput('{"神志": -10}');
      final out = GameplayRuntime.overrideWith(base, skill, mode: m);
      expect(out.deltas['violations'], 1, reason: '违规次数必须保留');
      expect(out.deltas['sanity'], -10, reason: '神志以技能为准');
    });

    test('通用判定仍然是后备：新玩法不写技能也能跑', () {
      // 手写技能是给已有玩法打磨的；将来新增的玩法只要打开 statJudge
      // 就能拿到一个按自己 stats 生成的判定，不必先写提示词。
      final mode = GameplayMode.fromJson({
        'id': 'future-mode',
        'name': '将来的玩法',
        'directive': '先跑起来。',
        'statJudge': true,
        'stats': [
          {'key': 'mood', 'name': '心情', 'max': 100, 'isScore': true},
        ],
      });
      expect(mode.turnTool, isNull);
      expect(
        GameplayRuntime.turnToolIdFor(mode),
        GameplayRuntime.statJudgeToolId,
      );
      final manifest = GameplayRuntime.buildPluginManifest(mode)!;
      expect(
        manifest.tools.map((t) => t.id),
        contains(GameplayRuntime.statJudgeToolId),
      );
    });

    test('通用判定技能按玩法自己的状态量生成，按人记的会要求带人名', () {
      final dating =
          kBuiltinGameplayModes.firstWhere((m) => m.id == 'dating-sim');
      final spec = GameplayRuntime.buildStatJudgeSpec(dating);
      final prompt = spec['prompt'] as String;
      expect(prompt, contains('好感'));
      expect(prompt, contains('信任'));
      expect(prompt, contains('好感|姓名'), reason: '按人记的状态要带人名');
      expect(prompt, contains('{{text}}'));
      expect(prompt, contains('{{members}}'));
    });
  });
}
