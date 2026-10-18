import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/data/sj_view_models.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_achievements_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_empty_state_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_favorites_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_mine_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_search_page.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_statistics_page.dart';

/// 渲染后的真实对比度审计。
///
/// 与 `sj_tokens_contrast_test.dart` 的分工：
///  - 那边测的是**令牌两两配对**（ink/paper = 14.28:1），属静态规则
///  - 这边测的是**页面上每一个文字节点实际渲染出来的前景/背景**，
///    能抓到「令牌本身没问题、但某个组件用错了组合」这类错误
///
/// 这相当于手工做了一遍「截图取色 + 对比度计算」，
/// 是在无法目视核对时的替代手段。
///
/// 跳过的情况：
///  - 前景或背景带渐变/图片（无法取单一样本色）
///  - 找不到任何不透明背景祖先
void main() {
  double lin(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  double lum(Color c) =>
      0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);

  double ratio(Color fg, Color bg) {
    final a = lum(fg), b = lum(bg);
    final hi = math.max(a, b), lo = math.min(a, b);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 从某元素的祖先里找第一个不透明背景色。
  Color? backgroundOf(Element element) {
    Color? found;
    element.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      Color? candidate;

      if (w is Container) {
        final d = w.decoration;
        if (d is BoxDecoration) {
          if (d.gradient != null || d.image != null) return false; // 跳过
          candidate = d.color;
        } else if (d == null) {
          candidate = w.color;
        }
      } else if (w is ColoredBox) {
        candidate = w.color;
      } else if (w is Material) {
        candidate = w.color;
      } else if (w is Scaffold) {
        candidate = w.backgroundColor ??
            Theme.of(ancestor).scaffoldBackgroundColor;
      }

      if (candidate != null && candidate.a > 0.99) {
        found = candidate;
        return false;
      }
      return true;
    });
    return found;
  }

  void audit(WidgetTester tester, String pageName) {
    final failures = <String>[];

    for (final element in find.byType(RichText).evaluate()) {
      final render = element.renderObject;
      if (render is! RenderBox || !render.hasSize) continue;

      final rich = element.widget as RichText;
      final style = rich.text.style;
      final fg = style?.color;
      final fontSize = style?.fontSize;
      if (fg == null || fontSize == null) continue;
      if (fg.a < 0.99) continue; // 半透明前景不判

      final bg = backgroundOf(element);
      if (bg == null) continue;

      final bold = (style?.fontWeight?.value ?? 400) >= 700;
      final isLarge = fontSize >= 24 || (bold && fontSize >= 18.66);
      final need = isLarge ? 3.0 : 4.5;

      final r = ratio(fg, bg);
      if (r < need - 0.01) {
        final text = rich.text.toPlainText();
        final preview = text.length > 16 ? '${text.substring(0, 16)}…' : text;
        failures.add('「$preview」 ${fontSize.toStringAsFixed(1)}px  '
            '${r.toStringAsFixed(2)}:1  需 $need:1');
      }
    }

    expect(
      failures,
      isEmpty,
      reason: '$pageName 有 ${failures.length} 处对比度不达标：\n'
          '${failures.join('\n')}',
    );
  }

  final sample = SjGalleryData.sample;
  final pages = <String, Widget>{
    '我的': SjMinePage(profile: sample.profile),
    '统计': SjStatisticsPage(data: sample.statistics),
    '收藏': SjFavoritesPage(books: sample.favorites),
    '成就': SjAchievementsPage(data: sample.achievements),
    '空状态': const SjEmptyStatePage(bookCount: 0),
    '搜索': const SjSearchPage(),
  };

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final tag = brightness == Brightness.dark ? '深色' : '浅色';
    for (final entry in pages.entries) {
      testWidgets('$tag · ${entry.key}页对比度', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(body: entry.value),
        ));
        await tester.pumpAndSettle();
        audit(tester, '$tag「${entry.key}」');
      });
    }
  }
}
