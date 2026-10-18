// lib/service/character/distill_estimate.dart
//
// 蒸馏开跑前的预估：会调用几次、大概烧多少 Token、要等多久。
//
// 为什么需要：长篇小说整本蒸馏是"先付费后看见结果"的操作，
// 只告诉用户"会消耗较多 Token"等于什么都没说。
// 预估本身是纯计算，不花任何模型调用——所以可以随范围拖动实时刷新。

import 'dart:math' as math;

/// 一次蒸馏的预估结果。
class DistillEstimate {
  const DistillEstimate({
    required this.chunks,
    required this.inputTokens,
    required this.outputTokens,
    required this.duration,
    required this.chapters,
  });

  /// 切片数（也就是模型调用次数）。
  final int chunks;

  /// 送进去的 Token 估算。
  final int inputTokens;

  /// 取回来的 Token 估算。
  final int outputTokens;

  final Duration duration;

  /// 参与蒸馏的章节数。
  final int chapters;

  int get totalTokens => inputTokens + outputTokens;

  /// 例如「约 12 次调用 · 约 4.8 万 Token · 预计 1 分 30 秒」。
  String describe() {
    final t = totalTokens >= 10000
        ? '${(totalTokens / 10000).toStringAsFixed(1)} 万'
        : '$totalTokens';
    return '约 $chunks 次调用 · 约 $t Token · 预计 ${_durationText()}';
  }

  String _durationText() {
    final s = duration.inSeconds;
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    final rest = s % 60;
    return rest == 0 ? '$m 分钟' : '$m 分 $rest 秒';
  }
}

/// 每 1 个中文字符大致对应 1 个 Token（中文模型的经验值）。
const double kTokensPerChineseChar = 1.0;

/// 单次调用的固定开销（系统提示词 + 输出契约说明）。
const int kPerCallPromptOverheadTokens = 1200;

/// 单次调用平均返回的 Token（一段章节抽出的人物/关系 JSON）。
const int kPerCallOutputTokens = 700;

/// 每次调用平均耗时（秒）——刻意取保守值，估短了用户会觉得卡住。
const double kSecondsPerCall = 12;

/// 计算一个章节在给定预算下会被切成几片。
int chunksForChapter(int chapterChars, int budget) {
  if (budget <= 0) return 1;
  if (chapterChars <= 0) return 1;
  return math.max(1, (chapterChars / budget).ceil());
}

/// 预估。
///
/// [chapterLengths] 是**已按范围过滤后**的章节字数列表——
/// 范围选择的效果因此会自动反映到预估里，不需要额外同步。
DistillEstimate estimateDistill({
  required List<int> chapterLengths,
  int chapterCharBudget = 12000,
  int concurrency = 4,
  int focusNameCount = 0,
}) {
  final chapters = chapterLengths.length;
  if (chapters == 0) {
    return const DistillEstimate(
      chunks: 0,
      inputTokens: 0,
      outputTokens: 0,
      duration: Duration.zero,
      chapters: 0,
    );
  }

  var chunks = 0;
  var chars = 0;
  for (final len in chapterLengths) {
    chunks += chunksForChapter(len, chapterCharBudget);
    chars += len;
  }

  // 输入：正文 + 每次调用的固定开销
  var input = (chars * kTokensPerChineseChar).round() +
      chunks * kPerCallPromptOverheadTokens;

  // 指定了人物名时，模型要读的上下文没变，但要写的内容变少，
  // 反过来也会因为「只看这几个人」而少扫一遍——预估上按输出打八折。
  final outputFactor = focusNameCount > 0 ? 0.8 : 1.0;
  final output = (chunks * kPerCallOutputTokens * outputFactor).round();

  final safeConcurrency = math.max(1, concurrency);
  final seconds = (chunks / safeConcurrency) * kSecondsPerCall;

  return DistillEstimate(
    chunks: chunks,
    inputTokens: input,
    outputTokens: output,
    duration: Duration(seconds: seconds.round()),
    chapters: chapters,
  );
}

/// 从「1 基的章节区间」截取字数列表；越界自动收敛。
///
/// [from] / [to] 都按用户看到的 1 基章节号传入；返回的列表供
/// [estimateDistill] 使用。范围非法时退化为全部章节，而不是返回空。
List<int> sliceChapterLengths(
  List<int> all,
  int? from,
  int? to,
) {
  if (all.isEmpty) return const [];
  var start = (from ?? 1) - 1;
  var end = (to ?? all.length) - 1;
  if (start < 0) start = 0;
  if (end >= all.length) end = all.length - 1;
  if (start > end) {
    return all;
  }
  return all.sublist(start, end + 1);
}
