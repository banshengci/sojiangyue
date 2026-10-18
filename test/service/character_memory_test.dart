import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/service/character/character_persona.dart';

/// 记忆（把超出窗口的旧对话折叠成一段备忘）。
///
/// 起因：历史窗口只有 `maxHistoryMessages = 24` 条，超出部分**被静默丢弃**，
/// 于是长对话里角色会忘记刚发生过的约定与秘密。这里锁住三件事：
/// 记忆段落的形状、压缩提示词的要求、以及记忆字段的持久化。
void main() {
  group('buildMemorySection', () {
    test('没有记忆时不产出任何段落（不污染 system prompt）', () {
      expect(buildMemorySection(null), '');
      expect(buildMemorySection(''), '');
      expect(buildMemorySection('   '), '');
    });

    test('有记忆时带上小标题与正文', () {
      final s = buildMemorySection('我在雨夜见过她，她没说实话。');
      expect(s, contains('你还记得'));
      expect(s, contains('我在雨夜见过她，她没说实话。'));
    });
  });

  group('buildMemorySummaryPrompt', () {
    const dialogue = '林黛玉：你又来做什么。\n贾宝玉：来看看你。';

    test('要求第一人称、有字数上限', () {
      final p = buildMemorySummaryPrompt(
        characterName: '林黛玉',
        previousSummary: '',
        dialogue: dialogue,
      );
      expect(p, contains('林黛玉'));
      expect(p, contains('第一人称'));
      expect(p, contains('200 字'));
    });

    test('已有记忆时会要求"接得上、别重复"', () {
      final p = buildMemorySummaryPrompt(
        characterName: '林黛玉',
        previousSummary: '先前我病了一场。',
        dialogue: dialogue,
      );
      expect(p, contains('已有的记忆'));
      expect(p, contains('先前我病了一场。'));
      expect(p, contains('不要重复'));
    });

    test('没有旧记忆时不出现空的"已有记忆"区块', () {
      final p = buildMemorySummaryPrompt(
        characterName: '林黛玉',
        previousSummary: '   ',
        dialogue: dialogue,
      );
      expect(p, isNot(contains('已有的记忆')));
    });

    test('把新对话原文带进去', () {
      final p = buildMemorySummaryPrompt(
        characterName: '林黛玉',
        previousSummary: '',
        dialogue: dialogue,
      );
      expect(p, contains('来看看你'));
    });
  });

  group('buildMemoryDialogue', () {
    test('拼成「说话人：内容」，并跳过空内容', () {
      final text = buildMemoryDialogue([
        (speaker: '林黛玉', content: '你又来做什么。'),
        (speaker: '旁白', content: '   '),
        (speaker: '', content: '窗外下雨。'),
      ]);
      expect(text, contains('林黛玉：你又来做什么。'));
      expect(text, contains('旁白：窗外下雨。'));
      expect(text.split('\n').where((l) => l.trim().isNotEmpty).length, 2);
    });
  });

  group('会话记忆字段', () {
    test('默认没有记忆', () {
      final s = CharacterChatSession(
        bookId: 1,
        characterName: '林黛玉',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(s.memorySummary, isNull);
      expect(s.memoryUptoMessageId, isNull);
    });

    test('toMap / fromMap 往返不丢', () {
      final s = CharacterChatSession(
        bookId: 1,
        characterName: '林黛玉',
        memorySummary: '我记得那个雨夜。',
        memoryUptoMessageId: 42,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );
      final back = CharacterChatSession.fromMap({'id': 9, ...s.toMap()});
      expect(back.memorySummary, '我记得那个雨夜。');
      expect(back.memoryUptoMessageId, 42);
    });

    test('copyWith 能单独更新记忆进度', () {
      final s = CharacterChatSession(
        bookId: 1,
        characterName: '林黛玉',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final updated = s.copyWith(
        memorySummary: '新备忘',
        memoryUptoMessageId: 7,
      );
      expect(updated.memorySummary, '新备忘');
      expect(updated.memoryUptoMessageId, 7);
      // 其他字段不受影响
      expect(updated.characterName, '林黛玉');
    });
  });

  group('memoryForFork（分支时能否沿用记忆）', () {
    test('没有记忆 → 不带', () {
      expect(
        memoryForFork(summary: null, upto: 10, atMessageId: 20),
        isNull,
      );
      expect(
        memoryForFork(summary: '   ', upto: 10, atMessageId: 20),
        isNull,
      );
    });

    test('整段复制（不指定分叉点）→ 沿用', () {
      expect(
        memoryForFork(summary: '旧事', upto: 99, atMessageId: null),
        '旧事',
      );
    });

    test('分叉点晚于已压范围 → 沿用', () {
      expect(
        memoryForFork(summary: '旧事', upto: 10, atMessageId: 20),
        '旧事',
      );
    });

    test('分叉点早于已压范围 → 丢弃（否则新分支会记得没经历的事）', () {
      expect(
        memoryForFork(summary: '旧事', upto: 30, atMessageId: 20),
        isNull,
      );
    });

    test('不知道压到哪 → 保守丢弃', () {
      expect(
        memoryForFork(summary: '旧事', upto: null, atMessageId: 20),
        isNull,
      );
    });
  });}
