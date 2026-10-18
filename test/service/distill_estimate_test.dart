import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/character_distill_estimate.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart'
    show DistillChunkPlanner;
import 'package:songjiang_reader/service/character/distill_chunking.dart';
import 'package:songjiang_reader/service/character/distill_prompt.dart';

/// 蒸馏前的三项：预估、章节范围、人物名。
///
/// 重点是**对齐**：预估说几次调用，真跑就必须是几次。
/// 这个偏差不会报错，只会悄悄变贵，所以专门写了对照测试。
void main() {
  String text(int n, {String fill = '字'}) => fill * n;

  group('splitChapterRanges', () {
    test('不超过预算：整段一片', () {
      final r = splitChapterRanges(text(1000), budget: 12000);
      expect(r.length, 1);
      expect(r.single.start, 0);
      expect(r.single.end, 1000);
    });

    test('空文本也返回一片（与规划器一致，不会返回 0 片）', () {
      final r = splitChapterRanges('', budget: 12000);
      expect(r.length, 1);
      expect(r.single.end, 0);
    });

    test('超出预算会切成多片', () {
      final r = splitChapterRanges(text(30000), budget: 12000);
      expect(r.length, greaterThan(1));
    });

    test('相邻切片保留重叠', () {
      final r = splitChapterRanges(text(30000), budget: 12000, overlap: 800);
      expect(r[1].start, lessThan(r[0].end));
    });

    test('切到文末就停，不再吐一片纯尾巴（回归）', () {
      final r = splitChapterRanges(text(20000), budget: 12000, overlap: 800);
      // 修复前会多出 [19200, 20000) 这一片，内容与上一片完全重复
      expect(r.last.end, 20000);
      expect(r.length, 2, reason: '20000 字、预算 12000、重叠 800 应为 2 片');
      for (var i = 1; i < r.length; i++) {
        expect(r[i].start, lessThan(r[i - 1].end), reason: '相邻片应有重叠');
        expect(
          r[i].start >= r[i - 1].start && r[i].end <= r[i - 1].end,
          isFalse,
          reason: '不得出现被上一片完全包含的重复切片',
        );
      }
    });

    test('句末优先：切点落在标点之后', () {
      final body = '${text(7000)}。${text(7000)}。${text(7000)}';
      final r = splitChapterRanges(body, budget: 12000);
      final first = body.substring(r[0].start, r[0].end);
      expect(first.endsWith('。'), isTrue, reason: '应尽量在句号后断开');
    });

    test('预算是 0 或负数时整段一片，不死循环', () {
      expect(splitChapterRanges(text(100), budget: 0).length, 1);
      expect(splitChapterRanges(text(100), budget: -5).length, 1);
    });
  });

  group('chunkCountFor 与规划器对齐', () {
    test('各种长度下，预估片数 == 规划器片数', () {
      final planner = DistillChunkPlanner();
      for (final len in [0, 1, 11999, 12000, 12001, 20000, 36001, 50000]) {
        final chapters = [
          BookChapter(title: '第1章', text: text(len)),
        ];
        final actual = planner.plan(chapters).length;
        final estimated = chunkCountFor(text(len), budget: 12000, overlap: 800);
        expect(estimated, actual, reason: '$len 字时预估与实际不一致');
      }
    });

    test('多章时总数也一致', () {
      final planner = DistillChunkPlanner();
      final chapters = [
        BookChapter(title: '第1章', text: text(5000)),
        BookChapter(title: '第2章', text: text(30000)),
        BookChapter(title: '第3章', text: text(12000)),
      ];
      expect(
        estimateDistill(
          chapterTexts: chapters.map((c) => c.text).toList(),
        ).chunks,
        planner.plan(chapters).length,
      );
    });
  });

  group('整体预估', () {
    test('空输入返回全零，不除零', () {
      final e = estimateDistill(chapterTexts: const []);
      expect(e.chunks, 0);
      expect(e.totalTokens, 0);
      expect(e.duration, Duration.zero);
      expect(e.describe(), contains('没有可蒸馏'));
    });

    test('Token 含每次调用的固定开销', () {
      final e = estimateDistill(chapterTexts: [text(12000)]);
      expect(e.inputTokens, greaterThan(12000));
      expect(e.outputTokens, greaterThan(0));
    });

    test('指定人物名时输出 Token 更低（输入不变）', () {
      final auto = estimateDistill(chapterTexts: [text(10000), text(10000)]);
      final focus = estimateDistill(
        chapterTexts: [text(10000), text(10000)],
        focusNameCount: 3,
      );
      expect(focus.outputTokens, lessThan(auto.outputTokens));
      expect(focus.inputTokens, auto.inputTokens);
    });

    test('并发越高耗时越短，但不会为零', () {
      final many = List.filled(4, text(12000));
      final c1 = estimateDistill(chapterTexts: many, concurrency: 1);
      final c4 = estimateDistill(chapterTexts: many, concurrency: 4);
      expect(c4.duration, lessThan(c1.duration));
      expect(c4.duration.inSeconds, greaterThan(0));
    });

    test('描述文案含次数、Token、预计', () {
      final t = estimateDistill(chapterTexts: [text(12000)]).describe();
      expect(t, contains('次调用'));
      expect(t, contains('Token'));
      expect(t, contains('预计'));
    });

    test('耗时超过一分钟用「分」表述', () {
      final e = estimateDistill(
        chapterTexts: List.filled(20, text(12000)),
        concurrency: 1,
      );
      expect(e.describe(), contains('分'));
    });
  });

  group('章节范围（唯一实现 sliceByChapter）', () {
    test('1 基闭区间', () {
      expect(sliceByChapter([1, 2, 3, 4, 5], 2, 4), [2, 3, 4]);
    });

    test('不传范围返回全部', () {
      expect(sliceByChapter([1, 2, 3], null, null), [1, 2, 3]);
    });

    test('越界收敛', () {
      expect(sliceByChapter([1, 2, 3], 1, 99), [1, 2, 3]);
      expect(sliceByChapter([1, 2, 3], -5, 2), [1, 2]);
    });

    test('起点大于终点退化为全部，而不是空', () {
      expect(sliceByChapter([1, 2, 3], 3, 1), [1, 2, 3]);
    });

    test('空列表返回空', () {
      expect(sliceByChapter(<int>[], 1, 2), isEmpty);
    });

    test('泛型对 BookChapter 同样生效', () {
      final chapters = [
        for (var i = 0; i < 3; i++)
          BookChapter(title: '第${i + 1}章', text: 'x'),
      ];
      expect(sliceByChapter(chapters, 2, 3).first.title, '第2章');
    });
  });

  group('规划器的章节标题（回归）', () {
    test('每章第一片用原名，只有续片才加「（续）」', () {
      final planner = DistillChunkPlanner();
      final chunks = planner.plan([
        BookChapter(title: '第一章', text: text(30000)),
        BookChapter(title: '第二章', text: text(30000)),
      ]);
      final firstChapter = chunks.where((c) => c.title.startsWith('第一章'));
      final secondChapter = chunks.where((c) => c.title.startsWith('第二章'));
      expect(
        firstChapter.where((c) => c.title == '第一章').length,
        1,
        reason: '第一章应恰好有一片用原名',
      );
      expect(
        secondChapter.where((c) => c.title == '第二章').length,
        1,
        reason: '修复前第二章的首片会错叫「第二章（续）」',
      );
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

    test('空白名字被过滤', () {
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
