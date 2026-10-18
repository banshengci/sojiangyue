import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/data/sj_view_models.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_achievements_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_empty_state_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_favorites_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_mine_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_statistics_page.dart';
import 'package:songjiang_reader/design/songjiang/sj_progress_ring.dart';
import 'package:songjiang_reader/design/songjiang/sj_reader_toolbar.dart';
import 'package:songjiang_reader/design/songjiang/sj_section_header.dart';
import 'package:songjiang_reader/design/songjiang/sj_segmented.dart';
import 'package:songjiang_reader/design/songjiang/sj_selection_bar.dart';
import 'package:songjiang_reader/design/songjiang/sj_tap_target.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';

/// 深色模式渲染验证 + 组件状态矩阵。
///
/// 令牌层的深色对比度已由 `sj_tokens_contrast_test.dart` 逐对断言；
/// 这个文件验证的是**另一件事**：切到深色后，组件能不能正常渲染、
/// 状态（默认/禁用）是否符合规范。
void main() {
  Widget host(Widget child, {required Brightness brightness}) {
    return MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('深色模式渲染', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final label = brightness == Brightness.dark ? '深色' : '浅色';

      testWidgets('$label · 5 个新组件全部可渲染', (tester) async {
        await tester.pumpWidget(host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SjTapTarget(
                semanticLabel: '返回',
                onTap: () {},
                child: const Icon(Icons.chevron_left),
              ),
              SjSegmented(
                labels: const ['全部', '在读'],
                selectedIndex: 0,
                onChanged: (_) {},
              ),
              const SjSectionHeader(title: '最近阅读', actionLabel: '查看全部'),
              const SjProgressRing(progress: 0.6),
              SjSelectionBar(
                actions: const [
                  SjSelectionAction(icon: Icons.brush, label: '高亮'),
                  SjSelectionAction(icon: Icons.copy, label: '复制'),
                ],
                onMore: () {},
              ),
              SjReaderToolbar(
                items: const [
                  SjReaderToolItem(icon: Icons.toc, label: '目录'),
                  SjReaderToolItem(icon: Icons.headphones, label: '听'),
                ],
                selectedIndex: 0,
                onTap: (_) {},
                showSafeArea: false,
              ),
            ],
          ),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('$label · 设计模块页面全部可渲染', (tester) async {
        final sample = SjGalleryData.sample;
        final pages = <String, Widget>{
          '我的': SjMinePage(profile: sample.profile),
          '收藏': SjFavoritesPage(books: sample.favorites),
          '成就': SjAchievementsPage(data: sample.achievements),
          '统计': SjStatisticsPage(data: sample.statistics),
          '空状态': const SjEmptyStatePage(bookCount: 0),
        };

        for (final entry in pages.entries) {
          await tester.pumpWidget(
            host(entry.value, brightness: brightness),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$label 模式下「${entry.key}」页渲染失败',
          );
        }
      });
    }
  });

  group('组件状态矩阵', () {
    testWidgets('默认态：可点', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(
        SjTapTarget(
          onTap: () => tapped++,
          child: const Icon(Icons.add),
        ),
        brightness: Brightness.light,
      ));
      await tester.tap(find.byType(SjTapTarget));
      expect(tapped, 1);
    });

    testWidgets('禁用态：不响应点击，且不透明度降为 0.4', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(
        SjTapTarget(
          enabled: false,
          onTap: () => tapped++,
          child: const Icon(Icons.add),
        ),
        brightness: Brightness.light,
      ));

      await tester.tap(find.byType(SjTapTarget), warnIfMissed: false);
      expect(tapped, 0, reason: '禁用态不应触发回调');

      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(SjTapTarget),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.4);
    });

    testWidgets('禁用态仍保留 44×44 占位（布局不跳动）', (tester) async {
      await tester.pumpWidget(host(
        SjTapTarget(
          enabled: false,
          onTap: () {},
          child: const Icon(Icons.add),
        ),
        brightness: Brightness.light,
      ));
      final size = tester.getSize(find.byType(SjTapTarget));
      expect(size.width, greaterThanOrEqualTo(SjSizes.minTouchTarget));
      expect(size.height, greaterThanOrEqualTo(SjSizes.minTouchTarget));
    });

    testWidgets('未提供 onTap 时不可点，但仍占位', (tester) async {
      await tester.pumpWidget(host(
        const SjTapTarget(child: Icon(Icons.add)),
        brightness: Brightness.light,
      ));
      final size = tester.getSize(find.byType(SjTapTarget));
      expect(size.width, greaterThanOrEqualTo(SjSizes.minTouchTarget));
      // 没有 GestureDetector 即不可点
      expect(
        find.descendant(
          of: find.byType(SjTapTarget),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });
}
