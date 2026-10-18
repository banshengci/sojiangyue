import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/character_persona.dart';
import 'package:songjiang_reader/service/character/director_action.dart';

/// 导演动作与锁定事实。
///
/// 两者都是「给模型加约束」的机制，写错的后果一样：约束没生效，
/// 但界面看起来是生效的——所以这里把拼出来的文本逐条钉住。
void main() {
  final t0 = DateTime(2026);

  group('导演指令', () {
    test('五种动作都有展示名、说明与注入指令', () {
      for (final a in DirectorAction.values) {
        expect(a.label.trim(), isNotEmpty);
        expect(a.hint.trim(), isNotEmpty);
        expect(a.instruction.trim().length, greaterThan(10));
      }
      expect(DirectorAction.values.length, 5);
    });

    test('指令以【导演指令 · 名称】开头，模型能认出这是舞台指令', () {
      final d = buildDirectorDirective(DirectorAction.conflict);
      expect(d.startsWith('【导演指令 · 制造冲突】'), isTrue);
      expect(d, contains('分歧'));
    });

    test('推进与放缓是相反的方向（别写成同一句）', () {
      final adv = DirectorAction.advance.instruction;
      final slow = DirectorAction.slowEmotion.instruction;
      expect(adv, isNot(slow));
      expect(adv, contains('推进'));
      expect(slow, contains('不要推进外部事件'));
    });

    test('目标是空 / 纯空白时不出现"目标"段', () {
      for (final goal in [null, '', '   ']) {
        final d = buildDirectorDirective(DirectorAction.advance, goal: goal);
        expect(d.contains('这一次的目标是'), isFalse, reason: 'goal=$goal');
      }
    });

    test('有目标时附在末尾，并要求落成行动而不是念任务说明', () {
      final d = buildDirectorDirective(
        DirectorAction.advance,
        goal: '让宝玉先开口道歉',
      );
      expect(d, contains('这一次的目标是：让宝玉先开口道歉'));
      expect(d, contains('不要把它当成任务说明念出来'));
    });

    test('目标前后的空白被裁掉', () {
      final d = buildDirectorDirective(
        DirectorAction.viewpoint,
        goal: '  换黛玉的视角  ',
      );
      expect(d, contains('这一次的目标是：换黛玉的视角。'));
      expect(d, isNot(contains(' 换黛玉')));
    });
  });

  group('锁定事实注入', () {
    WorldSetting w(String name, {bool pinned = false}) => WorldSetting(
          bookId: 1,
          category: '势力',
          name: name,
          description: '$name 的描述',
          pinned: pinned,
          createdAt: t0,
          updatedAt: t0,
        );

    CharacterCard c() => CharacterCard(
          bookId: 1,
          name: '林黛玉',
          createdAt: t0,
          updatedAt: t0,
        );

    test('单人对话：锁定的进「不可改写」，其余留在「你所处的世界」', () {
      final prompt = buildCharacterSystemPrompt(
        character: c(),
        world: [w('荣国府', pinned: true), w('江南甄家')],
      );
      expect(prompt, contains('不可改写的设定'));
      expect(prompt, contains('荣国府'));
      expect(prompt, contains('你所处的世界'));
      expect(prompt, contains('江南甄家'));

      // 锁定的那条必须出现在「不可改写」段落里，而不是普通段落
      final lockedIdx = prompt.indexOf('不可改写的设定');
      final normalIdx = prompt.indexOf('你所处的世界');
      final rongIdx = prompt.indexOf('- 势力·荣国府');
      expect(rongIdx, greaterThan(lockedIdx));
      expect(rongIdx, lessThan(normalIdx));
    });

    test('没有锁定时不出现「不可改写」段（避免空段干扰）', () {
      final prompt = buildCharacterSystemPrompt(
        character: c(),
        world: [w('荣国府')],
      );
      expect(prompt, isNot(contains('不可改写的设定')));
      expect(prompt, contains('你所处的世界'));
    });

    test('群聊也会注入锁定事实', () {
      final prompt = buildGroupSystemPrompt(
        characters: [c()],
        world: [w('荣国府', pinned: true)],
      );
      expect(prompt, contains('不可改写的设定'));
      expect(prompt, contains('荣国府'));
      expect(prompt, contains('不得否认'));
    });
  });
  group('别写成小说（对话体约束）', () {
    test('单人 prompt 明确禁止「我＋动作」开头的散文腔', () {
      final p = buildCharacterSystemPrompt(
        character: CharacterCard(
          bookId: 1,
          name: '烈焰',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      expect(p, contains('别写成小说'));
      expect(p, contains('我＋动作'));
      expect(p, contains('不要为写景而写景'));
      expect(p, contains('不要加「名字：」前缀'));
    });

    test('群聊 prompt 也有同样的约束', () {
      final p = buildGroupSystemPrompt(
        characters: [
          CharacterCard(
            bookId: 1,
            name: '烈焰',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ],
      );
      expect(p, contains('别写成小说'));
      expect(p, contains('我＋动作'));
    });

    test('旁观指令要求用对白推进，而不是整段散文', () {
      final d = buildParticipationDirective(
        participation: CharacterParticipation.spectator,
      );
      expect(d, contains('对白'));
      expect(d, contains('不要写成整段散文'));
      expect(d, isNot(contains('做动作、说台词')));
    });
  });
}
