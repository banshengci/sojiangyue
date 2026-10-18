import 'dart:convert';

// lib/service/character/dialogue_review.dart
//
// 一致性审校：生成完之后再"体检"一次，把跑偏的地方点名出来。
//
// 为什么需要：角色一旦 OOC（口吻不像、动机突变、态度不对、用了不该知道的信息），
// 用户只能点「重新生成」再赌一次运气。审校把"一次赌对"变成
// "生成 → 体检 → 按问题重写"。
//
// 四类问题刻意收得很窄：只查语义偏离，不查文笔。
// 情绪波动、讽刺、撒谎、伪装都属于合理范围，不该被当成错误。

/// 审校发现的问题。
class ReviewIssue {
  const ReviewIssue({
    required this.code,
    required this.severity,
    required this.speaker,
    required this.detail,
    required this.evidence,
  });

  /// 四类之一：voice / motivation / relationship / knowledge。
  final String code;

  /// warning 或 error。
  final String severity;

  final String speaker;

  /// 为什么与人物设定冲突。
  final String detail;

  /// 逐字摘录的原文证据（2–40 字）。
  final String evidence;

  bool get isError => severity == 'error';

  String get codeLabel => switch (code) {
        'semantic_voice_drift' => '口吻不像',
        'semantic_motivation_drift' => '动机突变',
        'semantic_relationship_drift' => '态度不符',
        'semantic_knowledge_drift' => '知道得太多',
        _ => '疑似偏离',
      };
}

/// 组装审校提示词。
///
/// [personaSummary] 是这个角色"应该是什么样"的浓缩说明（身份/性格/所求/关系）。
String buildReviewPrompt({
  required String characterName,
  required String replies,
  required String personaSummary,
}) {
  final buf = StringBuffer();
  buf.writeln('你是人物对话的一致性审校器。不要续写，不要润色，只判断这段回复有没有跑偏。');
  buf.writeln();
  buf.writeln('【人物设定】');
  buf.writeln(personaSummary.trim().isEmpty ? '（无）' : personaSummary.trim());
  buf.writeln();
  buf.writeln('【刚刚这一段回复】');
  buf.writeln(replies.trim());
  buf.writeln();
  buf.writeln('只查四类问题：');
  buf.writeln('1. semantic_voice_drift —— 说话口吻明显不像这个人（用词、句式、称呼都不对）');
  buf.writeln('2. semantic_motivation_drift —— 动机或决策逻辑突然变了，没有铺垫');
  buf.writeln('3. semantic_relationship_drift —— 对某人的态度与当前关系明显冲突');
  buf.writeln('4. semantic_knowledge_drift —— 用了这个角色不可能知道的信息');
  buf.writeln();
  buf.writeln('要求：');
  buf.writeln('- **只有证据明确时才报**。合理的情绪波动、讽刺、撒谎、伪装、情境性反常都不算问题；');
  buf.writeln('- evidence 必须是上面回复里**逐字连续摘录**的 2–40 字，不许改写；');
  buf.writeln('- severity 只能是 warning 或 error；');
  buf.writeln('- 没有问题就返回空数组。');
  buf.writeln();
  buf.writeln('只输出 JSON，不要解释、不要代码围栏：');
  buf.writeln(
    '{"issues":[{"code":"semantic_voice_drift","severity":"warning",'
    '"speaker":"$characterName","detail":"为什么与设定冲突","evidence":"原文摘录"}],'
    '"summary":"一句话结论"}',
  );
  return buf.toString();
}

/// 解析审校结果；无法解析时返回空列表（当作"没查出问题"）。
List<ReviewIssue> parseReviewIssues(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return const [];
  text = text
      .replaceAll(RegExp(r'```(?:json)?', multiLine: true), '')
      .replaceAll('```', '')
      .trim();

  Object? decoded;
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded is! Map) return const [];
  final list = decoded['issues'];
  if (list is! List) return const [];

  const allowed = {
    'semantic_voice_drift',
    'semantic_motivation_drift',
    'semantic_relationship_drift',
    'semantic_knowledge_drift',
  };
  final out = <ReviewIssue>[];
  for (final e in list) {
    if (e is! Map) continue;
    final code = (e['code'] ?? '').toString();
    if (!allowed.contains(code)) continue;
    final evidence = (e['evidence'] ?? '').toString().trim();
    // 没有逐字证据的判断不可信——宁可漏报，不要误报
    if (evidence.isEmpty) continue;
    out.add(
      ReviewIssue(
        code: code,
        severity: (e['severity'] ?? 'warning').toString() == 'error'
            ? 'error'
            : 'warning',
        speaker: (e['speaker'] ?? '').toString(),
        detail: (e['detail'] ?? '').toString(),
        evidence: evidence,
      ),
    );
  }
  return out;
}

/// 把问题清单变成"重写指令"。
///
/// 关键约束：只改这些问题，不新增情节，也不解释修改过程——
/// 否则模型会顺手把这一轮重写成一个新故事。
String buildCorrectionInstruction(List<ReviewIssue> issues) {
  if (issues.isEmpty) return '';
  final buf = StringBuffer();
  buf.writeln('【重写这一轮】上一版回复有以下问题，请逐条消除后重写同一轮：');
  for (final i in issues) {
    final why = i.detail.trim().isEmpty ? i.codeLabel : i.detail.trim();
    buf.writeln('- ${i.codeLabel}：$why（原文：「${i.evidence}」）');
  }
  buf.writeln('要求：保留已经成立的场景事实与事件，只调整有问题的地方；'
      '不要新增情节，不要解释你在改什么，也不要提及审校。');
  return buf.toString();
}
