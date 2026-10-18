// lib/service/character/character_distill_estimate.dart
//
// 蒸馏开跑前的预估：会调用几次、大概烧多少 Token、要等多久。
//
// 为什么需要：长篇小说整本蒸馏是"先付费后看见结果"的操作，
// 只告诉用户"会消耗较多 Token"等于什么都没说。
//
// **切片数不在这里重新算**：直接调用 `distill_chunking.dart` 里规划器
// 用的同一个函数。预估与真跑必须是同一个数字，否则用户会觉得被坑，
// 而这种偏差不会报错——它只会悄悄变贵。

import 'dart:math' as math;

import 'package:songjiang_reader/service/character/distill_chunking.dart';

/// 一次蒸馏的预估结果。
class DistillEstimate {
  const DistillEstimate({
    required this.chunks,
    required this.inputTokens,
    required this.outputTokens,
    required this.duration,
    required this.chapters,
  });

  /// 切片数（= 模型调用次数）。
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
    if (chunks == 0) return '没有可蒸馏的章节';
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

/// 与 `DistillChunkPlanner` 的默认重叠保持一致。
const int kDefaultOverlap = 800;

/// 预估。
///
/// [chapterTexts] 是**已按范围过滤后**的正文——
/// 范围选择的效果因此自动反映到预估里，不需要额外同步。
DistillEstimate estimateDistill({
  required List<String> chapterTexts,
  int chapterCharBudget = 12000,
  int overlap = kDefaultOverlap,
  int concurrency = 4,
  int focusNameCount = 0,
}) {
  if (chapterTexts.isEmpty) {
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
  for (final text in chapterTexts) {
    chunks += chunkCountFor(
      text,
      budget: chapterCharBudget,
      overlap: overlap,
    );
    chars += text.length;
  }

  // 输入：正文 + 每次调用的固定开销
  final input = (chars * kTokensPerChineseChar).round() +
      chunks * kPerCallPromptOverheadTokens;

  // 指定了人物名时：读的上下文一样，但要写的内容变少，
  // 也不会被龙套带偏，输出按八折估。
  final outputFactor = focusNameCount > 0 ? 0.8 : 1.0;
  final output = (chunks * kPerCallOutputTokens * outputFactor).round();

  final safeConcurrency = math.max(1, concurrency);
  final seconds = (chunks / safeConcurrency) * kSecondsPerCall;

  return DistillEstimate(
    chunks: chunks,
    inputTokens: input,
    outputTokens: output,
    duration: Duration(seconds: seconds.round()),
    chapters: chapterTexts.length,
  );
}
