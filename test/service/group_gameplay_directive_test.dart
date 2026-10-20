import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/character/character_persona.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_modes.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';

/// 群聊里的玩法设定。
///
/// 回归的是这样一次真实故障：元叙事那局是群聊（姬动 × 烈焰），
/// `reply()` 只在单人口吻分支传 `extraDirective`，群聊分支的
/// `buildGroupSystemPrompt` 压根没有这个入参——于是玩法规则、状态量、
/// 分幕、收局条件一条都没进提示词，整局退化成普通同人续写。
///
/// 玩法在群聊里跑得比单人还多（多人在场才成戏），所以这条必须锁住。
void main() {
  final card = CharacterCard(
    bookId: 1,
    name: '姬动',
    role: '天干圣徒',
    personality: '嘴硬、重情',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  GameplayMode metaFiction() =>
      kBuiltinGameplayModes.firstWhere((m) => m.id == 'meta-fiction');

  String directiveOf(GameplayMode mode) => GameplayRuntime.buildDirective(
        mode: mode,
        session: GameplaySession(
          chatSessionId: 1,
          modeId: mode.id,
          stats: {for (final d in mode.stats) d.key: d.initial},
        ),
      );

  group('buildGroupSystemPrompt 的 extraDirective', () {
    test('传了就会写进群聊 prompt', () {
      final prompt = buildGroupSystemPrompt(
        characters: [card],
        extraDirective: '## 本场玩法：元叙事\n角色察觉到自己在一本书里。',
      );
      expect(prompt, contains('## 本场额外设定'));
      expect(prompt, contains('元叙事'));
    });

    test('不传时不塞空段落（普通群聊保持原样）', () {
      final prompt = buildGroupSystemPrompt(characters: [card]);
      expect(prompt, isNot(contains('## 本场额外设定')));
    });

    test('空白串等同于不传', () {
      final prompt = buildGroupSystemPrompt(
        characters: [card],
        extraDirective: '   \n  ',
      );
      expect(prompt, isNot(contains('## 本场额外设定')));
    });

    test('元叙事的玩法规则能原样落到群聊 prompt 里', () {
      final mode = metaFiction();
      final prompt = buildGroupSystemPrompt(
        characters: [card],
        extraDirective: directiveOf(mode),
      );
      // 玩法名、状态量、分幕、收局条件、状态块格式，一个都不能少
      expect(prompt, contains('本场玩法：${mode.name}'));
      expect(prompt, contains('觉醒度'));
      expect(prompt, contains('第 1 幕'));
      expect(prompt, contains('<sj-state>'));
      // 单人和群聊两版都要有，别只修一边
      final single = buildCharacterSystemPrompt(
        character: card,
        extraDirective: directiveOf(mode),
      );
      expect(single, contains('本场玩法：${mode.name}'));
    });
  });
}
