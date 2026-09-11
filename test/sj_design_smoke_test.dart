import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/data/sj_view_models.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_achievements_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_empty_state_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_favorites_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_mine_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_search_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_statistics_page.dart';
import 'package:songjiang_reader/design/songjiang/sj_gallery.dart';

/// 渲染冒烟测试 + 视图模型单元测试。
///
/// 本文件只依赖设计模块（纯展示层），不引入应用 DAO，因此可独立运行。
void main() {
  Future<void> pumpPage(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  final sample = SjGalleryData.sample;

  // ---------- 视图模型 ----------
  group('视图模型', () {
    test('时长格式化', () {
      expect(sjFormatDuration(67320), '18h 42m');
      expect(sjFormatDuration(2520), '42m');
      expect(sjFormatDuration(0), '0s');
    });

    test('环比与柱值归一化', () {
      expect(sample.statistics.monthDeltaLabel, '较上月 +12%');
      expect(sample.statistics.weeklyPeakIndex, 6);
      expect(sample.statistics.weeklyNormalized.last, 1.0);
      expect(sample.statistics.hasData, isTrue);
    });

    test('无上月数据时不显示环比', () {
      const s = SjStatisticsData(
        monthSeconds: 3600,
        prevMonthSeconds: 0,
        currentStreak: 1,
        finishedBooks: 1,
        dailyAverageMinutes: 10,
        heatLevels: [
          [0, 0, 0, 0, 0, 0, 0],
        ],
        weeklySeconds: [0, 0, 0, 0, 0, 0, 0],
      );
      expect(s.monthDeltaLabel, isNull);
      expect(s.weeklyPeakIndex, isNull);
    });

    test('成就进度与封面种子', () {
      expect(sample.achievements.total, 6);
      expect(sample.achievements.unlockedCount, 3);
      expect(sample.achievements.progress, 0.5);
      for (final b in sample.favorites) {
        expect(b.coverSeed, inInclusiveRange(0, 3));
        expect(b.progressLabel, startsWith('已读 '));
      }
    });
  });

  // ---------- P1 核心页面 ----------
  testWidgets('搜索页可渲染', (tester) async {
    await pumpPage(tester, const SjSearchPage());
    expect(find.text('搜索'), findsWidgets);
    expect(find.text('最近阅读'), findsOneWidget);
  });

  testWidgets('收藏页可渲染', (tester) async {
    await pumpPage(tester, SjFavoritesPage(books: sample.favorites));
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('长恨歌'), findsOneWidget);
    expect(find.text('已读 62%'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('收藏页空态可渲染', (tester) async {
    await pumpPage(tester, const SjFavoritesPage(books: []));
    expect(find.text('还没有收藏'), findsOneWidget);
  });

  testWidgets('我的页可渲染', (tester) async {
    await pumpPage(tester, SjMinePage(profile: sample.profile));
    expect(find.text('墨客'), findsOneWidget);
    expect(find.text('已读 24 本 · 笔记 38 条'), findsOneWidget);
    expect(find.text('阅读统计'), findsOneWidget);
  });

  // ---------- P2 数据与成就 ----------
  testWidgets('数据统计页可渲染', (tester) async {
    // 页面较长（含热力图与柱状图），给足视口以便整页构建。
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester, SjStatisticsPage(data: sample.statistics));
    expect(find.text('数据统计'), findsOneWidget);
    expect(find.text('18h 42m'), findsOneWidget);
    expect(find.text('较上月 +12%'), findsOneWidget);
    expect(find.text('本周阅读'), findsOneWidget);
  });

  testWidgets('成就页可渲染', (tester) async {
    await pumpPage(tester, SjAchievementsPage(data: sample.achievements));
    expect(find.text('成就'), findsOneWidget);
    expect(find.text('3 / 6'), findsOneWidget);
    expect(find.text('初读'), findsOneWidget);
    expect(find.text('书海漫游'), findsOneWidget);
  });

  testWidgets('空状态页（书架为空）可渲染', (tester) async {
    await pumpPage(tester, const SjEmptyStatePage(bookCount: 0));
    expect(find.text('书架还空着'), findsOneWidget);
    expect(find.text('导入图书'), findsOneWidget);
  });

  testWidgets('空状态页（已有藏书）切换文案', (tester) async {
    await pumpPage(tester, const SjEmptyStatePage(bookCount: 7));
    expect(find.text('书架已有 7 本书'), findsOneWidget);
    expect(find.text('导入图书'), findsNothing);
  });

  // ---------- 预览容器 ----------
  testWidgets('预览容器（索引 + 底部导航）可渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SjGallery(data: sample)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('设计页索引'), findsOneWidget);
    expect(find.text('书库'), findsWidgets);
  });
}
