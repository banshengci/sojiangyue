/// 松江阅 · 设计令牌
///
/// **本文件是全项目唯一的取色 / 取字号 / 取间距来源。**
/// 任何页面、组件都不得再出现硬编码的颜色与字号。
///
/// 取值与对比度经 WCAG 2.2 复算（脚本：`tool/check_tokens.mjs`）：
///  - 所有正文色对底色 ≥ 4.5:1
///  - 所有交互边界 ≥ 3:1
///  - 装饰色单独标注，不得承载文字
///
/// 变更记录（v3）：
///  - `inkSoft` 由 `#6B7A72`（4.14:1，不达 AA）修正为 `#5F6E66`（4.92:1）
///  - 新增 `inkFaint`（4.14:1）承接「仅大字 / 装饰」的旧语义
///  - `cardBorder` 由 `#E6E2D6`（1.19:1）加深至 `#D8D2C0`（1.38:1），并配 `SjShadow.card`
///  - 新增 `borderStrong`（3.66:1）专用于可交互边界
///  - 新增 `SjStatus`（success / warning / error / info 各 bg/fg/border 三件套）
///  - 字号收敛为严格 1.25 模块化 6 档（`SjType`）
///  - 间距收敛为 4pt 栅格 8 档（`SjSpace`）
library;

import 'package:flutter/material.dart';

/// 双模式色彩令牌（松江阅 · 色彩）。
///
/// 用法：`final c = SjColors.of(context);`
@immutable
class SjColors {
  const SjColors({
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.pine,
    required this.river,
    required this.clay,
    required this.frost,
    required this.paper,
    required this.card,
    required this.cardBorder,
    required this.borderStrong,
    required this.divider,
    required this.onPine,
    required this.riverText,
    required this.clayText,
  });

  /// 松墨 —— 主文字 / 主图标（14.28:1 on paper）。
  final Color ink;

  /// 次文 —— 次要文字 / 说明（**4.92:1**，满足 AA 正文）。
  final Color inkSoft;

  /// 弱文 —— 仅用于 ≥18.66px 加粗或纯装饰（4.14:1，**不要承载小字号正文**）。
  final Color inkFaint;

  /// 松绿 —— 品牌主色（5.77:1 on paper，6.30:1 on card）。
  final Color pine;

  /// 江青 —— 强调色一。作**非文字**使用（3.67:1）；文字场景请用 [riverText]。
  final Color river;

  /// 江青 · 文字安全版（7.22:1）。**文字必须用这个，不要用 [river]。**
  final Color riverText;

  /// 砂朱 —— 强调色二。作**非文字**使用（4.11:1）；文字场景请用 [clayText]。
  final Color clay;

  /// 砂朱 · 文字安全版（7.47:1）。**文字必须用这个，不要用 [clay]。**
  final Color clayText;

  /// 松霜 —— 装饰色（1.64:1，**不得承载文字**）。
  final Color frost;

  /// 纸白 —— 页面底色。
  final Color paper;

  /// 卡片底。
  final Color card;

  /// 装饰描边（1.38:1，需与 [SjShadow.card] 配合使用）。
  final Color cardBorder;

  /// 可交互边界（3.66:1）—— 按钮、输入框、chip 的边界必须用它。
  final Color borderStrong;

  /// 分隔线。
  final Color divider;

  /// 主色之上的前景色（5.77:1 on pine）。
  final Color onPine;


  /// 浅色模式。
  static const SjColors light = SjColors(
    ink: Color(0xFF173B2E),
    inkSoft: Color(0xFF5F6E66),
    inkFaint: Color(0xFF6B7A72),
    pine: Color(0xFF2E6B4F),
    river: Color(0xFF3D8C7D),
    clay: Color(0xFFC4543D),
    frost: Color(0xFFA8C9BD),
    paper: Color(0xFFF7F5ED),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFD8D2C0),
    borderStrong: Color(0xFF8C8578),
    divider: Color(0xFFEFECE1),
    onPine: Color(0xFFF7F5ED),
    riverText: Color(0xFF275A50),
    clayText: Color(0xFF853728),
  );

  /// 深色模式。
  static const SjColors dark = SjColors(
    ink: Color(0xFFE8F0E8),
    inkSoft: Color(0xFFA8BCB3),
    inkFaint: Color(0xFF8FA69C),
    pine: Color(0xFF86AD9B),
    river: Color(0xFF76AEA3),
    clay: Color(0xFFD68777),
    frost: Color(0xFF33544A),
    paper: Color(0xFF12261F),
    card: Color(0xFF1B332A),
    cardBorder: Color(0xFF3A4A43),
    borderStrong: Color(0xFF7A8A81),
    divider: Color(0xFF1F3A30),
    onPine: Color(0xFF10211B),
    riverText: Color(0xFF8FC7BB),
    clayText: Color(0xFFE5A395),
  );

  /// 按当前 Brightness 取色。
  static SjColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 状态色（每组 bg / fg / border 三件套）。
///
/// fg 对 bg 的对比度：success 5.57 · warning 4.92 · error 5.75 · info 6.11。
@immutable
class SjStatusColors {
  const SjStatusColors({
    required this.fg,
    required this.bg,
    required this.border,
  });

  final Color fg;
  final Color bg;
  final Color border;
}

/// 状态色集合。
class SjStatus {
  const SjStatus._();

  static const SjStatusColors success = SjStatusColors(
    fg: Color(0xFF2F6B3D),
    bg: Color(0xFFE8F2EA),
    border: Color(0xFFA8CDB2),
  );

  static const SjStatusColors warning = SjStatusColors(
    fg: Color(0xFF8A5E1F),
    bg: Color(0xFFF7EEDC),
    border: Color(0xFFE0C089),
  );

  static const SjStatusColors error = SjStatusColors(
    fg: Color(0xFF9E3B27),
    bg: Color(0xFFFAE9E6),
    border: Color(0xFFE3B0A5),
  );

  static const SjStatusColors info = SjStatusColors(
    fg: Color(0xFF25606B),
    bg: Color(0xFFE6F0F2),
    border: Color(0xFFA2C6CC),
  );

  /// 深色模式。
  static const SjStatusColors successDark = SjStatusColors(
    fg: Color(0xFF8FD3A3),
    bg: Color(0xFF1C3A28),
    border: Color(0xFF2F5C40),
  );

  static const SjStatusColors warningDark = SjStatusColors(
    fg: Color(0xFFE0B26A),
    bg: Color(0xFF3A2E18),
    border: Color(0xFF5C4823),
  );

  static const SjStatusColors errorDark = SjStatusColors(
    fg: Color(0xFFEFA192),
    bg: Color(0xFF3A211C),
    border: Color(0xFF5C352C),
  );

  static const SjStatusColors infoDark = SjStatusColors(
    fg: Color(0xFF8FC7D2),
    bg: Color(0xFF17343A),
    border: Color(0xFF2A5560),
  );
}

/// 尺寸令牌（松江阅 · 尺寸）。
class SjSizes {
  const SjSizes._();

  /// 图标网格。
  static const double iconGrid = 24;

  /// 图标描边（品牌线性图标统一描边）。
  static const double iconStroke = 1.75;

  /// 卡片圆角。
  static const double radiusCard = 24;

  /// 导航圆角（底部悬浮导航）。
  static const double radiusNav = 36;

  /// 书封圆角。
  static const double radiusCover = 10;

  /// 胶囊圆角。
  static const double radiusPill = 999;

  /// 最小可点尺寸（WCAG / Material 下限）。
  ///
  /// **所有可点元素的实际热区不得小于这个值**；视觉尺寸可以更小，
  /// 但必须用 [SjTapTarget] 或 `padding` 把热区撑到 44。
  static const double minTouchTarget = 44;

  /// 书封宽高比（3:4）。按此比例由宽度反算高度。
  static const double coverAspectRatio = 3 / 4;
}

/// 间距令牌（4pt 栅格，8 档，1 单位 = 1 逻辑像素）。
///
/// 只允许使用这 8 个值。v2 曾出现 `14px` 作为事实基础间距（42 次），已废弃。
class SjSpace {
  const SjSpace._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double s = 12;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// 页面左右内边距（落在栅格上，由 v2 的 20 改为 16）。
  static const double page = 16;
}

/// 字号令牌（严格 1.25 模块化，只有 6 档）。
///
/// 相邻比：10.5→13 = 1.238 · 13→16 = 1.231 · 16→20 = 1.250
/// · 20→25 = 1.250 · 25→31 = 1.240。
class SjType {
  const SjType._();

  /// 元信息、标签、时间戳。
  static const double caption = 10.5;

  /// 说明文字、列表副标题、导航标签。
  static const double label = 13;

  /// 正文。
  static const double body = 16;

  /// 卡片标题、区块标题。
  static const double title = 20;

  /// 大标题、书名。
  static const double headline = 25;

  /// 页面标题、统计主数字。
  static const double display = 31;
}

/// 阴影令牌。
///
/// 全项目只允许三种阴影；卡片必须同时用 [card] 阴影 + `cardBorder` 描边，
/// 因为单靠 1.38:1 的描边不足以让卡片从纸白底上分离出来。
class SjShadow {
  const SjShadow._();

  /// 卡片：极轻，只负责「浮起 1px」。
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D1B2622),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// 底部导航。
  static const List<BoxShadow> nav = <BoxShadow>[
    BoxShadow(
      color: Color(0x121B2622),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// 浮动层（选中浮条、FAB）。
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A1B2622),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];
}

/// 字体与文本样式。
///
/// 标题使用思源宋体（已在 pubspec 注册为 `SourceHanSerif`），
/// 正文沿用系统中文字体。**所有字号取自 [SjType]，不得硬编码。**
class SjText {
  const SjText._();

  /// 衬线字体族（思源宋体）。
  static const String serif = 'SourceHanSerif';

  /// 页面主标题（如「搜索」「我的收藏」）。
  static TextStyle pageTitle(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: SjType.display,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: color,
      );

  /// 区块标题（如「最近阅读」「热门标签」）。
  static TextStyle sectionTitle(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: SjType.title,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// 书封上的书名。
  static TextStyle coverTitle(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: SjType.headline,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// 书封上的作者 / 副题。
  static TextStyle coverSubtitle(Color color) => TextStyle(
        fontSize: SjType.label,
        height: 1.3,
        color: color,
      );

  /// 卡片主文字。
  static TextStyle cardTitle(Color color) => TextStyle(
        fontSize: SjType.title,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// 正文。
  static TextStyle body(Color color) => TextStyle(
        fontSize: SjType.body,
        height: 1.55,
        color: color,
      );

  /// 说明 / 元信息。
  static TextStyle meta(Color color) => TextStyle(
        fontSize: SjType.label,
        height: 1.4,
        color: color,
      );

  /// 最小号元信息。
  static TextStyle caption(Color color) => TextStyle(
        fontSize: SjType.caption,
        height: 1.4,
        color: color,
      );

  /// 数字（统计）。
  static TextStyle statNumber(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: SjType.display,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// 标签 / 筹码。
  static TextStyle chip(Color color, {bool selected = false}) => TextStyle(
        fontSize: SjType.label,
        height: 1.2,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: color,
      );

  /// 阅读正文（中文行长约束：手机 20–22 字/行，行高 1.8）。
  static TextStyle reading(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: SjType.body,
        height: 1.8,
        color: color,
      );
}
