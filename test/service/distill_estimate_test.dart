import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/character_distill_estimate.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart'
    show scopeChapters;
import 'package:songjiang_reader/service/character/distill_prompt.dart';

/// 蒸馏前的三项：预估、章节范围、人物名。
///
/// 这三项都直接影响花多少钱，所以都是纯计算、都可测：
/// 预估错了用户会以为被坑，范围少了会白跑一遍，人物名没生效会抽出一堆龙套。
void main() {
  group('切片数估算', () {
    test('不超过预算的章节算 1 片', () {
      expect(chunksForChapter(1000, 12000), 1);
      expect(chunksForChapter(12000, 12000), 1);
    });

    test('超过预算按向上取整', () {
      expect(chunksForChapter(12001, 12000), 2);
      expect(chunksForChapter(36000, 12000), 3);
      expect(chunksForChapter(36001, 12000), 4);
    });

    test('空/负数章节也至少算 1 片（不返回 0）', () {
      expect(chunksForChapter(0, 12000), 1);
      expect(chunksForChapter(-5, 12000), 1);
    });
  });

  group('整体预估', () {
    test('空输入返回全零，不除零', () {
      final e = estimateDistill(chapterLengths: const []);
      expect(e.chunks, 0);
      expect(e.totalTokens, 0);
      expect(e.duration, Duration.zero);
    });

    test('调用次数与章节切片一致', () {
      final e = estimateDistill(
        chapterLengths: [10000, 10000, 20000],
      );
      expect(e.chunks, 1 + 1 + 2);
      expect(e.chapters, 3);
    });

    test('Token 含每次调用的固定开销', () {
      final e = estimateDistill(chapterLengths: [12000]);
      expect(e.inputTokens, greaterThan(12000));
      expect(e.outputTokens, greaterThan(0));
    });

    test('指定人物名时输出 Token 更低（少于自动全找）', () {
      final auto = estimateDistill(chapterLengths: [10000, 10000]);
      final focus =
          estimateDistill(chapterLengths: [10000, 10000], focusNameCount: 3);
      expect(focus.outputTokens, lessThan(auto.outputTokens));
      // 输入不变：读的正文一样多
      expect(focus.inputTokens, auto.inputTokens);
    });

    test('并发越高耗时越短，但不会为零', () {
      final c1 = estimateDistill(chapterLengths: [12000, 12000, 12000, 12000], concurrency: 1);
      final c4 = estimateDistill(chapterLengths: [12000, 12000, 12000, 12000], concurrency: 4);
      expect(c4.duration, lessThan(c1.duration));
      expect(c4.duration.inSeconds, greaterThan(0));
    });

    test('描述文案带调用次数、Token 与耗时', () {
      final text = estimateDistill(chapterLengths: [12000]).describe();
      expect(text, contains('次调用'));
      expect(text, contains('Token'));
      expect(text, contains('预计'));
    });

    test('耗时超过一分钟时用「分」表述', () {
      final e = estimateDistill(
        chapterLengths: List.filled(20, 12000),
        concurrency: 1,
      );
      expect(e.describe(), contains('分'));
    });
  });

  group('章节范围截取', () {
    test('1 基闭区间', () {
      expect(sliceChapterLengths([1, 2, 3, 4, 5], 2, 4), [2, 3, 4]);
    });

    test('不传范围时返回全部', () {
      expect(sliceChapterLengths([1, 2, 3], null, null), [1, 2, 3]);
    });

    test('越界自动收敛', () {
      expect(sliceChapterLengths([1, 2, 3], 1, 99), [1, 2, 3]);
      expect(sliceChapterLengths([1, 2, 3], -5, 2), [1, 2]);
    });

    test('起点大于终点时退化为全部（而不是返回空）', () {
      expect(sliceChapterLengths([1, 2, 3], 3, 1), [1, 2, 3]);
    });

    test('空列表返回空', () {
      expect(sliceChapterLengths([], 1, 2), isEmpty);
    });
  });

  group('scopeChapters（服务端同一套语义）', () {
    List<BookChapter> chapters(int n) => [
          for (var i = 0; i < n; i++)
            BookChapter(title: '第${i + 1}章', text: 'x' * 10),
        ];

    test('按 1 基闭区间截取', () {
      final scoped = scopeChapters(chapters(5), 2, 3);
      expect(scoped.length, 2);
      expect(scoped.first.title, '第2章');
      expect(scoped.last.title, '第3章');
    });

    test('不传范围返回全部', () {
      expect(scopeChapters(chapters(4), null, null).length, 4);
    });

    test('越界收敛与非法范围退化', () {
      expect(scopeChapters(chapters(3), 1, 99).length, 3);
      expect(scopeChapters(chapters(3), 3, 1).length, 3);
      expect(scopeChapters(const [], 1, 2), isEmpty);
    });
  });

  group('人物名注入提示词', () {
    test('不传人物名时不出现「只抽这些人物」', () {
      final p = buildDistillUserPrompt('第一章', '正文');
      expect(p, isNot(contains('只抽这些人物')));
    });

    test('传了人物名会列出，并要求忽略其他人', () {
      final p = buildDistillUserPrompt(
        '第一章',
        '正文',
        focusNames: const ['林黛玉', '贾宝玉'],
      );
      expect(p, contains('只抽这些人物'));
      expect(p, contains('林黛玉、贾宝玉'));
      expect(p, contains('其他人即使出现也忽略'));
    });

    test('空白名字被过滤，不会产生空列表', () {
      final p = buildDistillUserPrompt(
        '第一章',
        '正文',
        focusNames: const ['  ', '林黛玉', ''],
      );
      expect(p, contains('林黛玉'));
      expect(p, isNot(contains('、\n')));
    });
  });
}
