import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/service/character/character_persona.dart';

/// 造梦的三种开局姿态（旁观 / 扮演 / 入场）。
///
/// 这三者是「同一人物、同一场景下体验差别最大」的一层：
/// 旁观时读者不该被搭话，扮演时人物要把读者当书中人，入场时人物要把读者当外来者。
/// 这里用纯函数断言，锁住"模型真的被告知了读者的位置"。
void main() {
  group('buildParticipationDirective', () {
    test('旁观：要求主动推进，不等读者回答', () {
      final s = buildParticipationDirective(
        participation: CharacterParticipation.spectator,
      );
      expect(s, contains('旁观'));
      expect(s, contains('不会发言'));
      expect(s, contains('主动推进'));
    });

    test('扮演：代入指定人物，且不许代写读者台词', () {
      final s = buildParticipationDirective(
        participation: CharacterParticipation.roleplay,
        userPersona: '林黛玉',
      );
      expect(s, contains('扮演'));
      expect(s, contains('林黛玉'));
      expect(s, contains('不要替他说话'));
    });

    test('扮演：没给身份时有兜底文案，不出现空引号', () {
      final s = buildParticipationDirective(
        participation: CharacterParticipation.roleplay,
      );
      expect(s, contains('书中的某个人物'));
      expect(s, isNot(contains('「」')));
    });

    test('入场：读者是外来者，人物可以试探', () {
      final s = buildParticipationDirective(
        participation: CharacterParticipation.join,
        userPersona: '阿舟',
      );
      expect(s, contains('入场'));
      expect(s, contains('阿舟'));
      expect(s, contains('不属于这本书的世界'));
    });

    test('三种姿态产出的文本互不相同（别退化成同一段）', () {
      final texts = CharacterParticipation.values
          .map((p) => buildParticipationDirective(participation: p))
          .toSet();
      expect(texts.length, 3);
    });
  });

  group('接入 system prompt', () {
    final card = CharacterCard(
      bookId: 1,
      name: '林黛玉',
      role: '贾府表小姐',
      personality: '敏感、机敏',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('传了 participation 就会写进单人 prompt', () {
      final prompt = buildCharacterSystemPrompt(
        character: card,
        participation: CharacterParticipation.spectator,
      );
      expect(prompt, contains('## 读者的位置'));
      expect(prompt, contains('旁观'));
    });

    test('不传 participation 时保持原样（不塞无关段落）', () {
      final prompt = buildCharacterSystemPrompt(character: card);
      expect(prompt, isNot(contains('## 读者的位置')));
    });

    test('群聊 prompt 同样支持', () {
      final prompt = buildGroupSystemPrompt(
        characters: [card],
        participation: CharacterParticipation.join,
        userPersona: '阿舟',
      );
      expect(prompt, contains('## 读者的位置'));
      expect(prompt, contains('阿舟'));
    });
  });

  group('会话模型', () {
    test('默认姿态是旁观（老数据无该列时的回退）', () {
      final s = CharacterChatSession(
        bookId: 1,
        characterName: '林黛玉',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(s.participation, CharacterParticipation.spectator);
      expect(s.userPersona, isNull);
    });

    test('toMap / fromMap 往返不丢姿态与身份', () {
      final s = CharacterChatSession(
        bookId: 7,
        characterName: '2:林黛玉,2:贾宝玉',
        mode: CharacterChatMode.group,
        participation: CharacterParticipation.roleplay,
        userPersona: '贾宝玉',
        createdAt: DateTime(2026, 2, 2),
        updatedAt: DateTime(2026, 2, 3),
      );
      final back = CharacterChatSession.fromMap({'id': 3, ...s.toMap()});
      expect(back.participation, CharacterParticipation.roleplay);
      expect(back.userPersona, '贾宝玉');
      expect(back.mode, CharacterChatMode.group);
      expect(back.bookId, 7);
    });

    test('未知/缺失的 participation 回退为旁观，不抛异常', () {
      expect(CharacterParticipation.fromCode(null),
          CharacterParticipation.spectator);
      expect(CharacterParticipation.fromCode('???'),
          CharacterParticipation.spectator);
    });
  });
}
