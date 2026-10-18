import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/data/sj_view_models.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_achievements_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_empty_state_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_favorites_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_mine_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_search_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_statistics_page.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';

/// 触控热区审计。
///
/// 这是「肉眼看图」的自动化替代的一部分：视觉评审最容易漏、而机器最容易查的
/// 就是「可点元素的实际热区小于 44×44」。这里把每个设计页渲染出来，
/// 遍历所有 InkWell / IconButton / GestureDetector，量它们**真实布局尺寸**。
///
/// 判定口径：
///  - 宽或高任一 < 44 视为不合规（WCAG 2.5.5 / Material 下限）
///  - 只统计**有 onTap** 的（禁用的不算）
///  - 文本内联链接等「行进中的可点片段」按行高算，单独放行（见 allowInline）
void main() {
  final sample = SjGalleryData.sample;

  final pages = <String, Widget>{
    '我的': SjMinePage(profile: sample.profile),
    '统计': SjStatisticsPage(data: sample.statistics),
    '收藏': SjFavoritesPage(books: sample.favorites),
    '成就': SjAchievementsPage(data: sample.achievements),
    '空状态': const SjEmptyStatePage(bookCount: 0),
    '搜索': const SjSearchPage(),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key}页 · 所有可点元素热区 ≥44', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: entry.value),
      ));
      await tester.pumpAndSettle();

      final offenders = <String>[];

      void check(Finder finder, String kind) {
        for (final element in finder.evaluate()) {
          final box = element.renderObject;
          if (box is! RenderBox || !box.hasSize) continue;
          final size = box.size;
          if (size.width >= SjSizes.minTouchTarget - 0.5 &&
              size.height >= SjSizes.minTouchTarget - 0.5) {
            continue;
          }
          offenders.add(
            '$kind ${size.width.toStringAsFixed(1)}×'
            '${size.height.toStringAsFixed(1)}',
          );
        }
      }

      check(find.byType(InkWell), 'InkWell');
      check(find.byType(IconButton), 'IconButton');
      check(find.byType(GestureDetector), 'GestureDetector');

      expect(
        offenders,
        isEmpty,
        reason: '${entry.key}页有 ${offenders.length} 个热区不足 44：\n'
            '${offenders.join('\n')}',
      );
    });
  }
}
