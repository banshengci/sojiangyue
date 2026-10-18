// lib/service/character/distill_chunking.dart
//
// 章节切片规则的**唯一实现**。
//
// 为什么单独抽出来：规划器（真跑）和预估（开跑前给用户看的数字）
// 必须用同一套切法。两边各写一份的后果是——预估说 23 次调用，
// 真跑变成 40 次，用户会认为被坑了。而这类偏差不会报错，只会悄悄变贵。
//
// 切法要点：
// * 单章不超过预算 → 整章一片
// * 超过预算 → 按预算切，但尽量切在句末（。！？\n），
//   且只有断开点越过半章时才采用，否则宁可硬切（避免碎成一堆短句）
// * 相邻切片保留 overlap 字重叠，避免把人物台词拦腰截断
// * **切到文末就停**：早期实现在最后一片之后还会因 overlap 再吐一片
//   纯尾巴（内容与前一片完全重复），等于每章多花一次调用

import 'dart:math' as math;

/// 一个切片在原文里的区间（`[start, end)`）。
typedef ChunkRange = ({int start, int end});

final RegExp _sentenceEnd = RegExp(r'[。！？\n]');

/// 把一段正文切成若干区间。
///
/// [budget] ≤ 0 时整段作为一片（避免除零 / 死循环）。
List<ChunkRange> splitChapterRanges(
  String text, {
  required int budget,
  int overlap = 0,
}) {
  if (budget <= 0) return [(start: 0, end: text.length)];
  if (text.length <= budget) return [(start: 0, end: text.length)];

  final ranges = <ChunkRange>[];
  var start = 0;
  while (start < text.length) {
    var end = math.min(start + budget, text.length);
    if (end < text.length) {
      // 从 end 往前找最后一个句末标点；只有越过半章才采用
      final cut = text.lastIndexOf(_sentenceEnd, end);
      if (cut > start + budget * 0.5) end = cut + 1;
    }
    if (end <= start) end = math.min(start + 1, text.length);
    ranges.add((start: start, end: end));
    if (end >= text.length) break; // 收尾，不再因 overlap 回头

    final back = end - overlap;
    start = back > start ? back : end;
  }
  return ranges;
}

/// 一段正文会被切成几片（预估用；与 [splitChapterRanges] 同源）。
int chunkCountFor(
  String text, {
  required int budget,
  int overlap = 0,
}) =>
    splitChapterRanges(text, budget: budget, overlap: overlap).length;
/// 按 1 基章节区间截取（含两端）。范围非法时退化为全部，而不是返回空。
///
/// 范围语义也只留这一份实现：服务端切片、预估、界面都调它。
List<T> sliceByChapter<T>(List<T> all, int? from, int? to) {
  if (all.isEmpty) return const [];
  var start = (from ?? 1) - 1;
  var end = (to ?? all.length) - 1;
  if (start < 0) start = 0;
  if (end >= all.length) end = all.length - 1;
  if (start > end) return all;
  return all.sublist(start, end + 1);
}