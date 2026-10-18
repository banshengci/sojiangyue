import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/service/character/dialogue_review.dart';

/// 一致性审校：提示词、解析、重写指令。
///
/// 审校最容易出的问题是**误报**——把合理的情绪波动判成"跑偏"，
/// 然后按这个错判去重写，反而把好回复改坏。所以这里重点钉两件事：
/// 没有逐字证据的判断不采纳；重写指令只准改问题、不准新增情节。
void main() {
  group('提示词', () {
    test('列全四类问题码', () {
      final p = buildReviewPrompt(
        characterName: '林黛玉',
        replies: '你懂什么。',
        personaSummary: '姓名：林黛玉\n性格：敏感',
      );
      expect(p, contains('semantic_voice_drift'));
      expect(p, contains('semantic_motivation_drift'));
      expect(p, contains('semantic_relationship_drift'));
      expect(p, contains('semantic_knowledge_drift'));
    });

    test('强调合理反常不算问题（防止误报）', () {
      final p = buildReviewPrompt(
        characterName: '某人',
        replies: '嗯。',
        personaSummary: '',
      );
      expect(p, contains('讽刺'));
      expect(p, contains('撒谎'));
      expect(p, contains('伪装'));
      expect(p, contains('只有证据明确时才报'));
    });

    test('要求证据逐字摘录且有长度范围', () {
      final p = buildReviewPrompt(
        characterName: '某人',
        replies: '嗯。',
        personaSummary: '',
      );
      expect(p, contains('逐字连续摘录'));
      expect(p, contains('2–40'));
    });

    test('把人物设定与回复都放进提示词', () {
      final p = buildReviewPrompt(
        characterName: '林黛玉',
        replies: '你懂什么。',
        personaSummary: '姓名：林黛玉\n性格：敏感',
      );
      expect(p, contains('姓名：林黛玉'));
      expect(p, contains('你懂什么。'));
    });
  });

  group('解析', () {
    test('标准 JSON', () {
      final list = parseReviewIssues(
        '{"issues":[{"code":"semantic_voice_drift","severity":"warning",'
        '"speaker":"林黛玉","detail":"用词太现代","evidence":"你懂什么"}],'
        '"summary":"一处"}',
      );
      expect(list.length, 1);
      expect(list.single.codeLabel, '口吻不像');
      expect(list.single.evidence, '你懂什么');
      expect(list.single.isError, isFalse);
    });

    test('代码围栏与前后缀文字都能解析', () {
      final list = parseReviewIssues(
        '好的，结果如下：\n```json\n{"issues":[{"code":"semantic_knowledge_drift",'
        '"severity":"error","detail":"不该知道","evidence":"我知道密档"}]}\n```',
      );
      expect(list.single.codeLabel, '知道得太多');
      expect(list.single.isError, isTrue);
    });

    test('未知 code 被丢弃（只认四类）', () {
      final list = parseReviewIssues(
        '{"issues":[{"code":"style_poor","severity":"warning","evidence":"x"}]}',
      );
      expect(list, isEmpty);
    });

    test('没有 evidence 的判断不采纳', () {
      final list = parseReviewIssues(
        '{"issues":[{"code":"semantic_voice_drift","severity":"warning",'
        '"detail":"感觉不对"}]}',
      );
      expect(list, isEmpty, reason: '没有逐字证据的误报比漏报更伤人');
    });

    test('空 issues 与无法解析都返回空，不抛异常', () {
      expect(parseReviewIssues('{"issues":[]}'), isEmpty);
      expect(parseReviewIssues('模型不想干活'), isEmpty);
      expect(parseReviewIssues(''), isEmpty);
    });
  });

  group('重写指令', () {
    test('逐条列出问题与原文证据', () {
      final text = buildCorrectionInstruction(const [
        ReviewIssue(
          code: 'semantic_voice_drift',
          severity: 'warning',
          speaker: '林黛玉',
          detail: '用词太现代',
          evidence: '你懂什么',
        ),
      ]);
      expect(text, contains('口吻不像'));
      expect(text, contains('用词太现代'));
      expect(text, contains('你懂什么'));
    });

    test('要求保留既成事实、不新增情节、不解释修改过程', () {
      final text = buildCorrectionInstruction(const [
        ReviewIssue(
          code: 'semantic_knowledge_drift',
          severity: 'error',
          speaker: '某人',
          detail: '',
          evidence: '我知道密档',
        ),
      ]);
      expect(text, contains('保留已经成立的场景事实'));
      expect(text, contains('不要新增情节'));
      expect(text, contains('不要解释你在改什么'));
    });

    test('没有问题时返回空串（不产生空的改写指令）', () {
      expect(buildCorrectionInstruction(const []), isEmpty);
    });
  });
}
