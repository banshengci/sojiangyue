// lib/models/deep_read_quiz.dart
//
// 自测题（B-02）的结构化 JSON 契约与解析结果。
//
// 契约（模型须返回，可包在 ```json 围栏里）：
// {
//   "questions": [
//     {
//       "id": "q1",
//       "stem": "宝玉为何在此处沉默？",
//       "options": ["...", "...", "...", "..."],
//       "answer_index": 1,
//       "explanation": "..."
//     }
//   ]
// }
//
// `answer_index` 是 0 基下标；渲染成 A/B/C/D 时用 String.fromCharCode(65 + i)。

/// 一道自测题。
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.stem,
    required this.options,
    required this.answerIndex,
    this.explanation = '',
  });

  final String id;

  /// 题干。
  final String stem;

  /// 选项文本（≥ 2 个）。
  final List<String> options;

  /// 正确选项下标（0 基）。
  final int answerIndex;

  final String explanation;

  /// 选 [picked] 是否正确。
  bool isCorrect(int picked) => picked == answerIndex;

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        id: j['id']?.toString() ?? '',
        stem: j['stem'] as String? ?? '',
        options: (j['options'] as List?)
                ?.map((e) => e?.toString() ?? '')
                .toList(growable: false) ??
            const <String>[],
        answerIndex: (j['answer_index'] as num?)?.toInt() ?? 0,
        explanation: j['explanation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'stem': stem,
        'options': options,
        'answer_index': answerIndex,
        'explanation': explanation,
      };
}

/// 一份自测题载荷。
class QuizPayload {
  const QuizPayload({required this.questions});

  final List<QuizQuestion> questions;

  factory QuizPayload.fromJson(Map<String, dynamic> j) => QuizPayload(
        questions: (j['questions'] as List?)
                ?.whereType<Map>()
                .map((e) => QuizQuestion.fromJson(e.cast<String, dynamic>()))
                .toList(growable: false) ??
            const <QuizQuestion>[],
      );

  Map<String, dynamic> toJson() => {
        'questions': questions.map((q) => q.toJson()).toList(),
      };
}

/// 解析结果：成功时带 [payload]，降级时带 [fallbackText]（原文，走纯文本渲染）。
///
/// 解析三段式（`DeepReadQuizParser`）任一失败即降级，**绝不抛异常**：
/// 结构不满足时返回 [fallbackText]，UI 走现有纯文本渲染（不空白、不崩溃）。
class QuizParseResult {
  const QuizParseResult({this.payload, this.fallbackText});

  final QuizPayload? payload;
  final String? fallbackText;

  bool get ok => payload != null;
}
