import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/design/songjiang/sj_tap_target.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/page/home_page/mine_page.dart';

import 'helpers/test_l10n.dart';

/// 「我的」页渲染测试。
///
/// 这页是 v3 新底栏的第四个 tab（「统计」与「设置」被并进来），
/// 依赖三个 prefs 与两个 Riverpod provider。
/// provider 在测试里拿不到数据库，会走 `maybeWhen(orElse:)` 的兜底分支——
/// **这本身就是需要验证的行为**：数据拿不到时页面也必须能渲染。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ReadingStylePrefs.ensureInitialized();
    await SyncPrefs.ensureInitialized();
    await ThemePrefs.ensureInitialized();
  });

  Widget app() => ProviderScope(child: wrapWithL10n(const MinePage()));

  testWidgets('无数据时也能渲染（provider 走兜底）', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    expect(find.text('我的'), findsOneWidget);
    expect(find.text('墨客'), findsOneWidget);

    expect(find.text('本月时长'), findsOneWidget);
    expect(find.text('已读'), findsOneWidget);
    expect(find.text('标注'), findsOneWidget);
    expect(find.text('暂无阅读记录'), findsOneWidget);

    expect(find.text('成就徽章'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    // 「数据面板」已移除：它指向的是设计预览画板 SjGallery，会给用户看到第二套系统
    expect(find.text('数据面板'), findsNothing);
  });

  testWidgets('内容入口行高不低于 52（触控下限）', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    for (final label in ['成就徽章', '我的收藏']) {
      final finder = find.text(label);
      expect(finder, findsOneWidget);
      final box = tester.getSize(
        find
            .ancestor(of: finder, matching: find.byType(ConstrainedBox))
            .first,
      );
      expect(
        box.height,
        greaterThanOrEqualTo(52),
        reason: '$label 行高 ${box.height}，要求 ≥52',
      );
    }
  });

  testWidgets('顶部设置齿轮热区为 44×44', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final targets = find.byType(SjTapTarget);
    expect(targets, findsWidgets);

    final size = tester.getSize(targets.first);
    expect(size.width, greaterThanOrEqualTo(SjSizes.minTouchTarget));
    expect(size.height, greaterThanOrEqualTo(SjSizes.minTouchTarget));
  });

  testWidgets('品牌色只出现在一处统计数字上（强调不通胀）', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final c = SjColors.light;
    final brandNumbers = find
        .byWidgetPredicate((w) =>
            w is Text &&
            w.style?.color == c.pine &&
            w.style?.fontSize == SjType.display)
        .evaluate()
        .length;

    expect(brandNumbers, 1, reason: '品牌色统计数字应恰好 1 个，实得 $brandNumbers');
  });
}
