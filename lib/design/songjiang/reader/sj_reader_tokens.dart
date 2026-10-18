/// 松江阅 · 小说阅读页（微信读书风格）设计令牌
///
/// 结构对齐微信读书阅读页：纸张底色 + 极简工具栏 + 底部五个工具位
/// + 右下「A↑ / 听」浮动按钮 + 上滑面板。
///
/// 与 `sj_tokens.dart` 的区别：
///  - [SjColors] 是 App 全局品牌色（松绿 / 纸白 / 松墨），用于书架、我的等页面；
///  - [SjReaderPalette] 是**阅读纸张**色，由当前阅读主题的底色/字色派生，
///    因此任意自定义主题都能得到协调的面板、分隔线、胶囊底色。
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// 纸张色（对应底部「亮度」面板里的「颜色」一行）
// ---------------------------------------------------------------------------

/// 一种阅读纸张配色。
@immutable
class SjReaderPaper {
  const SjReaderPaper({
    required this.id,
    required this.label,
    required this.background,
    required this.foreground,
  });

  /// 稳定标识，用于持久化选中态。
  final String id;

  /// 无障碍 / 提示用名称。
  final String label;

  /// 页面底色。
  final Color background;

  /// 正文颜色。
  final Color foreground;

  /// 是否深色纸张。
  bool get isDark => background.computeLuminance() < 0.4;

  /// 白 —— 冷白纸张。
  static const SjReaderPaper white = SjReaderPaper(
    id: 'white',
    label: '白',
    background: Color(0xFFFCFAF3),
    foreground: Color(0xFF2C2B27),
  );

  /// 纸 —— 米黄纸张（微信读书默认）。
  static const SjReaderPaper cream = SjReaderPaper(
    id: 'cream',
    label: '纸',
    background: Color(0xFFF7F2E3),
    foreground: Color(0xFF2C2B27),
  );

  /// 绿 —— 豆绿护眼纸张。
  static const SjReaderPaper mint = SjReaderPaper(
    id: 'mint',
    label: '绿',
    background: Color(0xFFE4EFE2),
    foreground: Color(0xFF242E26),
  );

  /// 夜 —— 夜间纸张（底色取品牌松墨）。
  static const SjReaderPaper night = SjReaderPaper(
    id: 'night',
    label: '夜',
    background: Color(0xFF141A17),
    foreground: Color(0xFFC7CEC5),
  );

  /// 「颜色」一行展示的四张纸。
  static const List<SjReaderPaper> presets = <SjReaderPaper>[
    white,
    cream,
    mint,
    night,
  ];

  /// 按底色匹配预置纸张，匹配不到时返回 [fallback]。
  static SjReaderPaper match(Color background, {SjReaderPaper? fallback}) {
    for (final paper in presets) {
      if (paper.background.toARGB32() == background.toARGB32()) {
        return paper;
      }
    }
    return fallback ?? (background.computeLuminance() < 0.4 ? night : cream);
  }
}

// ---------------------------------------------------------------------------
// 派生调色板
// ---------------------------------------------------------------------------

/// 阅读页调色板：由纸张底色 + 正文字色派生。
///
/// 页面、底部面板、工具栏同源同调，避免出现「米黄纸张 + 白底面板」的割裂。
@immutable
class SjReaderPalette {
  const SjReaderPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.foreground,
    required this.subForeground,
    required this.faint,
    required this.accent,
    required this.accentSoft,
    required this.divider,
    required this.chip,
    required this.knob,
    required this.onAccent,
    required this.isDark,
  });

  /// 页面底色（正文区）。
  final Color background;

  /// 面板 / 工具栏底色（比页面略深一点）。
  final Color surface;

  /// 面板内卡片底色。
  final Color surfaceRaised;

  /// 正文 / 主图标。
  final Color foreground;

  /// 次要文字 / 未激活图标。
  final Color subForeground;

  /// 更弱的说明文字 / 页码。
  final Color faint;

  /// 激活色（当前工具位、当前章节）。
  final Color accent;

  /// 激活态淡底。
  final Color accentSoft;

  /// 分隔线。
  final Color divider;

  /// 胶囊 / 滑块轨道 / 搜索框底。
  final Color chip;

  /// 滑块圆点。
  final Color knob;

  /// 激活色之上的前景色。
  final Color onAccent;

  /// 是否深色纸张。
  final bool isDark;

  /// 由纸张与强调色派生整套颜色。
  ///
  /// [accent] 默认取品牌松绿；夜间纸张上自动提亮，保证对比度。
  factory SjReaderPalette.from({
    required Color background,
    required Color foreground,
    Color accent = const Color(0xFF2E6B4F),
  }) {
    final dark = background.computeLuminance() < 0.4;

    // 面板底色：暗色纸张向白微提，浅色纸张向字色微压，形成一层薄薄的层次。
    final surface = dark
        ? Color.lerp(background, Colors.white, 0.075)!
        : Color.lerp(background, foreground, 0.035)!;
    final surfaceRaised = dark
        ? Color.lerp(background, Colors.white, 0.09)!
        : Color.lerp(background, Colors.white, 0.6)!;

    return SjReaderPalette(
      background: background,
      surface: surface,
      surfaceRaised: surfaceRaised,
      foreground: foreground,
      subForeground: Color.lerp(foreground, background, 0.38)!,
      faint: Color.lerp(foreground, background, 0.58)!,
      accent: dark ? Color.lerp(accent, Colors.white, 0.34)! : accent,
      accentSoft: (dark ? Color.lerp(accent, Colors.white, 0.34)! : accent)
          .withValues(alpha: 0.12),
      divider: Color.lerp(foreground, background, 0.86)!,
      chip: Color.lerp(foreground, background, 0.93)!,
      knob: dark ? Color.lerp(background, Colors.white, 0.32)! : Colors.white,
      onAccent: background,
      isDark: dark,
    );
  }

  /// 由主题（底色 + 字色）派生。
  factory SjReaderPalette.fromTheme(
    Color background,
    Color foreground, {
    Color accent = const Color(0xFF2E6B4F),
  }) =>
      SjReaderPalette.from(
        background: background,
        foreground: foreground,
        accent: accent,
      );

  /// 浅色纸张 + 松绿强调（预览默认值）。
  static const SjReaderPalette paper = SjReaderPalette(
    background: Color(0xFFF7F2E3),
    surface: Color(0xFFF4EEDD),
    surfaceRaised: Color(0xFFFCF8EC),
    foreground: Color(0xFF2C2B27),
    subForeground: Color(0xFF7A7566),
    faint: Color(0xFF9E9A8A),
    accent: Color(0xFF2E6B4F),
    accentSoft: Color(0x1F2E6B4F),
    divider: Color(0xFFE7E0CC),
    chip: Color(0xFFEFE9D8),
    knob: Color(0xFFFFFFFF),
    onAccent: Color(0xFFF7F2E3),
    isDark: false,
  );
}

// ---------------------------------------------------------------------------
// 尺寸
// ---------------------------------------------------------------------------

/// 阅读页尺寸令牌。
class SjReaderSize {
  const SjReaderSize._();

  /// 正文左右留白。
  static const double textPadding = 26;

  /// 顶栏高度（不含状态栏）。
  static const double topBar = 52;

  /// 底部工具栏高度（不含安全区）。
  static const double bottomBar = 58;

  /// 工具栏图标位宽度。
  static const double toolSlot = 56;

  /// 工具栏图标尺寸。
  static const double toolIcon = 23;

  /// 右下浮动按钮直径。
  static const double floatButton = 48;

  /// 面板顶部圆角。
  static const double sheetRadius = 20;

  /// 面板拖拽条。
  static const Size handleSize = Size(38, 4);

  /// 卡片圆角。
  static const double cardRadius = 14;

  /// 胶囊圆角。
  static const double pillRadius = 999;

  /// 滑块高度。
  static const double sliderHeight = 34;

  /// 滑块圆点直径。
  static const double sliderKnob = 28;

  /// 分段控件高度。
  static const double segmentHeight = 42;

  /// 色板直径。
  static const double swatch = 52;
}

// ---------------------------------------------------------------------------
// 排版
// ---------------------------------------------------------------------------

/// 阅读页排版令牌。
///
/// 正文与章节标题走思源宋体（与品牌一致），UI 文字走系统字体。
class SjReaderText {
  const SjReaderText._();

  /// 衬线字体族。
  static const String serif = 'SourceHanSerif';

  /// 章节序号「第 1 章」。
  static TextStyle chapterNumber(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: 15,
        height: 1.5,
        letterSpacing: 1.0,
        color: color,
      );

  /// 章节名。
  static TextStyle chapterTitle(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: 23,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
      );

  /// 正文段落。
  static TextStyle body(Color color, {double fontSize = 19}) => TextStyle(
        fontFamily: serif,
        fontSize: fontSize,
        height: 1.95,
        letterSpacing: 0.3,
        color: color,
      );

  /// 页面底部提示 / 页码。
  static TextStyle footer(Color color) => TextStyle(
        fontSize: 12,
        height: 1.2,
        letterSpacing: 0.2,
        color: color,
      );

  /// 面板标题（如「颜色」「背景」）。
  static TextStyle sheetLabel(Color color) => TextStyle(
        fontSize: 12,
        height: 1.2,
        letterSpacing: 0.3,
        color: color,
      );

  /// 面板主按钮文字。
  static TextStyle pill(Color color, {bool selected = false}) => TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: color,
      );

  /// 统计数字。
  static TextStyle statValue(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: 23,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// 统计说明。
  static TextStyle statLabel(Color color) => TextStyle(
        fontSize: 11,
        height: 1.4,
        color: color,
      );

  /// 面板底部小动作（图标 + 文字）。
  static TextStyle actionLabel(Color color) => TextStyle(
        fontSize: 11,
        height: 1.3,
        color: color,
      );
}
