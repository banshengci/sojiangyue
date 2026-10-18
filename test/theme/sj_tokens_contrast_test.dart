import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';

/// 设计令牌护栏。
///
/// 这个测试的存在理由：v1/v2 两轮设计里，「对比度」和「字号阶梯」都是靠人工检查的，
/// 结果分别漏掉了 5 处对比度不达标、52 处字号落在阶梯外。
/// 把规则写成断言后，任何一次改色/改字号都会在这里立刻失败。
///
/// 阈值依据 WCAG 2.2：
///  - 正文文字 4.5:1（AA）
///  - 大字（≥18.66px 加粗 / ≥24px）3:1
///  - 交互组件边界 3:1（1.4.11）
void main() {
  // ---------- WCAG 计算 ----------
  double _lin(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  double _lum(Color c) =>
      0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

  double contrast(Color fg, Color bg) {
    final a = _lum(fg), b = _lum(bg);
    final hi = math.max(a, b), lo = math.min(a, b);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// 断言某一对前景/背景达到阈值，失败时打印实测值。
  void expectContrast(
    String label,
    Color fg,
    Color bg,
    double min, {
    double tolerance = 0.0,
  }) {
    final r = contrast(fg, bg);
    expect(
      r,
      greaterThanOrEqualTo(min - tolerance),
      reason: '$label 实测 ${r.toStringAsFixed(2)}:1，要求 ≥$min:1',
    );
  }

  group('浅色模式对比度', () {
    const c = SjColors.light;

    test('正文与次要文字 ≥ 4.5', () {
      expectContrast('ink/paper', c.ink, c.paper, 4.5);
      expectContrast('ink/card', c.ink, c.card, 4.5);
      expectContrast('inkSoft/paper', c.inkSoft, c.paper, 4.5);
      expectContrast('inkSoft/card', c.inkSoft, c.card, 4.5);
    });

    test('弱文字仅需 ≥3（限大字/装饰）', () {
      expectContrast('inkFaint/paper', c.inkFaint, c.paper, 3.0);
    });

    test('品牌色与前景 ≥ 4.5', () {
      expectContrast('pine/paper', c.pine, c.paper, 4.5);
      expectContrast('pine/card', c.pine, c.card, 4.5);
      expectContrast('onPine/pine', c.onPine, c.pine, 4.5);
    });

    test('强调色的文字安全版 ≥ 4.5', () {
      expectContrast('riverText/paper', c.riverText, c.paper, 4.5);
      expectContrast('clayText/paper', c.clayText, c.paper, 4.5);
    });

    test('强调色的非文字版 ≥ 3（只可用于图形/底纹）', () {
      expectContrast('river/paper', c.river, c.paper, 3.0);
      expectContrast('clay/paper', c.clay, c.paper, 3.0);
    });

    test('交互边界 ≥ 3', () {
      expectContrast('borderStrong/card', c.borderStrong, c.card, 3.0);
      expectContrast('borderStrong/paper', c.borderStrong, c.paper, 3.0);
    });

    test('状态色 fg/bg ≥ 4.5', () {
      expectContrast('success', SjStatus.success.fg, SjStatus.success.bg, 4.5);
      expectContrast('warning', SjStatus.warning.fg, SjStatus.warning.bg, 4.5);
      expectContrast('error', SjStatus.error.fg, SjStatus.error.bg, 4.5);
      expectContrast('info', SjStatus.info.fg, SjStatus.info.bg, 4.5);
    });

    test('状态色在纸白底上也可读', () {
      expectContrast('success/paper', SjStatus.success.fg, c.paper, 4.5);
      expectContrast('warning/paper', SjStatus.warning.fg, c.paper, 4.5);
      expectContrast('error/paper', SjStatus.error.fg, c.paper, 4.5);
      expectContrast('info/paper', SjStatus.info.fg, c.paper, 4.5);
    });
  });

  group('深色模式对比度', () {
    const c = SjColors.dark;

    test('正文与次要文字 ≥ 4.5', () {
      expectContrast('ink/paper', c.ink, c.paper, 4.5);
      expectContrast('ink/card', c.ink, c.card, 4.5);
      expectContrast('inkSoft/paper', c.inkSoft, c.paper, 4.5);
      expectContrast('inkSoft/card', c.inkSoft, c.card, 4.5);
    });

    test('弱文字 ≥ 3', () {
      expectContrast('inkFaint/paper', c.inkFaint, c.paper, 3.0);
    });

    test('品牌色在纸底与卡底都 ≥ 4.5', () {
      expectContrast('pine/paper', c.pine, c.paper, 4.5);
      // 这条曾实测 4.17 失败（pine #6D9884），已改为 #86AD9B
      expectContrast('pine/card', c.pine, c.card, 4.5);
      expectContrast('onPine/pine', c.onPine, c.pine, 4.5);
    });

    test('强调色文字版 ≥ 4.5', () {
      expectContrast('riverText/paper', c.riverText, c.paper, 4.5);
      expectContrast('clayText/paper', c.clayText, c.paper, 4.5);
    });

    test('交互边界 ≥ 3', () {
      // 这条曾实测 2.99 失败（borderStrong #6B7A72），已改为 #7A8A81
      expectContrast('borderStrong/card', c.borderStrong, c.card, 3.0);
    });

    test('状态色 fg/bg ≥ 4.5', () {
      expectContrast(
          'successDark', SjStatus.successDark.fg, SjStatus.successDark.bg, 4.5);
      expectContrast(
          'warningDark', SjStatus.warningDark.fg, SjStatus.warningDark.bg, 4.5);
      expectContrast(
          'errorDark', SjStatus.errorDark.fg, SjStatus.errorDark.bg, 4.5);
      expectContrast(
          'infoDark', SjStatus.infoDark.fg, SjStatus.infoDark.bg, 4.5);
    });
  });

  group('字号阶梯', () {
    test('严格 1.25 模块化：相邻比 ≥ 1.23', () {
      const steps = <double>[
        SjType.caption,
        SjType.label,
        SjType.body,
        SjType.title,
        SjType.headline,
        SjType.display,
      ];
      for (var i = 1; i < steps.length; i++) {
        final ratio = steps[i] / steps[i - 1];
        expect(
          ratio,
          greaterThanOrEqualTo(1.23),
          reason:
              '${steps[i - 1]} → ${steps[i]} 比值 ${ratio.toStringAsFixed(3)}，要求 ≥1.23',
        );
      }
    });

    test('正文不小于 16（可读性下限）', () {
      expect(SjType.body, greaterThanOrEqualTo(16));
    });

    test('只有 6 档，且都为正数', () {
      const steps = <double>[
        SjType.caption,
        SjType.label,
        SjType.body,
        SjType.title,
        SjType.headline,
        SjType.display,
      ];
      expect(steps.length, 6);
      for (final s in steps) {
        expect(s, greaterThan(0));
      }
    });
  });

  group('间距栅格', () {
    test('全部落在 4pt 栅格上', () {
      const values = <double>[
        SjSpace.xxs,
        SjSpace.xs,
        SjSpace.s,
        SjSpace.m,
        SjSpace.l,
        SjSpace.xl,
        SjSpace.xxl,
        SjSpace.xxxl,
        SjSpace.page,
      ];
      for (final v in values) {
        expect(v % 4, 0, reason: '间距 $v 不在 4pt 栅格上');
      }
    });

    test('严格递增', () {
      const values = <double>[
        SjSpace.xxs,
        SjSpace.xs,
        SjSpace.s,
        SjSpace.m,
        SjSpace.l,
        SjSpace.xl,
        SjSpace.xxl,
        SjSpace.xxxl,
      ];
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]));
      }
    });
  });

  group('尺寸约束', () {
    test('最小可点尺寸为 44（WCAG / Material 下限）', () {
      expect(SjSizes.minTouchTarget, 44);
    });

    test('书封宽高比为 3:4', () {
      expect(SjSizes.coverAspectRatio, closeTo(0.75, 0.0001));
    });
  });
}
