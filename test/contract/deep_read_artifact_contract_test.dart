import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/deep_read_artifact.dart';
import 'package:songjiang_reader/models/deep_read_quiz.dart';

/// AI 深读产物 / 自测题 JSON 契约测试（T01）。
///
/// 覆盖：产物往返、未知 `kind` 兜底、题目 JSON 往返。
void main() {
  group('DeepReadArtifact', () {
    test('fromMap → toMap 往返一致', () {
      final now = DateTime(2026, 10, 7, 12, 0, 0);
      final map = {
        'id': 5,
        'book_id': 7,
        'chapter_href': 'chapter-3.xhtml',
        'chapter_title': '第三回',
        'kind': 'quiz',
        'format': 'json',
        'content': '{"questions":[]}',
        'model': 'gpt-x',
        'score': 3,
        'total': 4,
        'answered_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final artifact = DeepReadArtifact.fromMap(map);
      expect(artifact.bookId, 7);
      expect(artifact.chapterHref, 'chapter-3.xhtml');
      expect(artifact.kind, DeepReadKind.quiz);
      expect(artifact.format, 'json');
      expect(artifact.score, 3);
      expect(artifact.total, 4);
      expect(artifact.answeredAt, now);

      final out = artifact.toMap();
      expect(out['book_id'], 7);
      expect(out['chapter_href'], 'chapter-3.xhtml');
      expect(out['chapter_title'], '第三回');
      expect(out['kind'], 'quiz');
      expect(out['format'], 'json');
      expect(out['content'], '{"questions":[]}');
      expect(out['model'], 'gpt-x');
      expect(out['score'], 3);
      expect(out['total'], 4);
      expect(out['answered_at'], now.toIso8601String());
      expect(out['created_at'], now.toIso8601String());
      expect(out['updated_at'], now.toIso8601String());
    });

    test('未知 kind 字符串兜底为 preview，不抛异常', () {
      final artifact = DeepReadArtifact.fromMap({
        'book_id': 1,
        'kind': 'quantum_report', // 未来版本写入的未知类型
        'content': 'x',
        'created_at': '2026-10-07T12:00:00.000',
        'updated_at': '2026-10-07T12:00:00.000',
      });
      expect(artifact.kind, DeepReadKind.preview);
    });

    test('fromName：已知值精确匹配、未知值 / null 兜底', () {
      expect(DeepReadKind.fromName('preview'), DeepReadKind.preview);
      expect(DeepReadKind.fromName('quiz'), DeepReadKind.quiz);
      expect(DeepReadKind.fromName('recap'), DeepReadKind.recap);
      expect(DeepReadKind.fromName('summary'), DeepReadKind.summary);
      expect(DeepReadKind.fromName('nope'), DeepReadKind.preview);
      expect(DeepReadKind.fromName(null), DeepReadKind.preview);
    });

    test('缺失可选字段回退默认值', () {
      final artifact = DeepReadArtifact.fromMap({
        'book_id': 2,
        'kind': 'preview',
        'content': '正文',
        'created_at': '2026-10-07T12:00:00.000',
        'updated_at': '2026-10-07T12:00:00.000',
      });
      expect(artifact.chapterHref, '', reason: '缺省章节归一化为空串');
      expect(artifact.chapterTitle, isNull);
      expect(artifact.format, 'markdown');
      expect(artifact.model, isNull);
      expect(artifact.score, isNull);
      expect(artifact.total, isNull);
      expect(artifact.answeredAt, isNull);
    });
  });

  group('QuizPayload', () {
    test('toJson → fromJson 往返一致', () {
      final payload = QuizPayload.fromJson({
        'questions': [
          {
            'id': 'q1',
            'stem': '宝玉为何在此处沉默？',
            'options': ['未曾听懂', '心有所感却不欲言', '急于离开'],
            'answer_index': 1,
            'explanation': '前文已铺垫他两次欲言又止',
          },
        ],
      });
      expect(payload.questions.length, 1);

      final out = payload.toJson();
      final again = QuizPayload.fromJson(out);
      expect(again.questions.length, 1);
      final q = again.questions.first;
      expect(q.id, 'q1');
      expect(q.stem, '宝玉为何在此处沉默？');
      expect(q.options, ['未曾听懂', '心有所感却不欲言', '急于离开']);
      expect(q.answerIndex, 1);
      expect(q.explanation, '前文已铺垫他两次欲言又止');
    });

    test('isCorrect 以 0 基 answer_index 判定', () {
      const q = QuizQuestion(
        id: 'q1',
        stem: '题干',
        options: ['A', 'B', 'C', 'D'],
        answerIndex: 2,
      );
      expect(q.isCorrect(2), isTrue);
      expect(q.isCorrect(0), isFalse);
      expect(q.isCorrect(3), isFalse);
    });

    test('结构缺失时回退空题列表，不抛异常', () {
      final empty = QuizPayload.fromJson(const {});
      expect(empty.questions, isEmpty);

      final result = const QuizParseResult(fallbackText: '模型原文');
      expect(result.ok, isFalse);
      expect(result.payload, isNull);
      expect(result.fallbackText, '模型原文');
    });
  });
}
