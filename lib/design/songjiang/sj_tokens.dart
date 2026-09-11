/// 松江阅 · 设计令牌
///
/// 取值严格对应 Ardot 设计文件中的变量集：
///  - 《松江阅 · 色彩》：浅色 / 深色双模式，6 个 COLOR 变量
///    松墨 / 松绿 / 江青 / 砂朱 / 松霜 / 纸白
///  - 《松江阅 · 尺寸》：图标网格 24 / 图标描边 1.75 / 卡片圆角 24 / 导航圆角 36
///
/// 页面视觉对应画板「07 核心页面」（搜索 / 收藏 / 我的）。
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
    required this.pine,
    required this.river,
    required this.clay,
    required this.frost,
    required this.paper,
    required this.card,
    required this.cardBorder,
    required this.divider,
    required this.onPine,
  });

  /// 松墨 —— 主文字 / 主图标。
  final Color ink;

  /// 次文（灰绿）—— 次要文字 / 说明。
  final Color inkSoft;

  /// 松绿 —— 主色（激活态 / 主按钮 / 主强调）。
  final Color pine;

  /// 江青 —— 强调色一。
  final Color river;

  /// 砂朱 —— 强调色二（徽标 / 高亮 / 图标描边）。
  final Color clay;

  /// 松霜 —— 弱化色（次要底 / 描边 / 标签底）。
  final Color frost;

  /// 纸白 —— 页面底色。
  final Color paper;

  /// 卡片底。
  final Color card;

  /// 卡片描边。
  final Color cardBorder;

  /// 分隔线。
  final Color divider;

  /// 主色之上的前景色。
  final Color onPine;

  /// 浅色模式。
  static const SjColors light = SjColors(
    ink: Color(0xFF173B2E),
    inkSoft: Color(0xFF6B7A72),
    pine: Color(0xFF2E6B4F),
    river: Color(0xFF3D8C7D),
    clay: Color(0xFFC4543D),
    frost: Color(0xFFA8C9BD),
    paper: Color(0xFFF7F5ED),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE6E2D6),
    divider: Color(0xFFEFECE1),
    onPine: Color(0xFFF7F5ED),
  );

  /// 深色模式。
  static const SjColors dark = SjColors(
    ink: Color(0xFFE8F0E8),
    inkSoft: Color(0xFF9FB4AB),
    pine: Color(0xFF59A17D),
    river: Color(0xFF6BB8A6),
    clay: Color(0xFFD97357),
    frost: Color(0xFF33544A),
    paper: Color(0xFF12261F),
    card: Color(0xFF1B332A),
    cardBorder: Color(0xFF284A3C),
    divider: Color(0xFF1F3A30),
    onPine: Color(0xFF10211B),
  );

  /// 按当前 Brightness 取色。
  static SjColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
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
}

/// 间距令牌（1 单位 = 1 逻辑像素）。
class SjSpace {
  const SjSpace._();

  /// 页面左右内边距。
  static const double page = 20;
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// 字体与文本样式。
///
/// 标题使用思源宋体（已在 pubspec 注册为 `SourceHanSerif`），
/// 正文沿用系统中文字体，与画板「07 核心页面」一致。
class SjText {
  const SjText._();

  /// 衬线字体族（思源宋体）。
  static const String serif = 'SourceHanSerif';

  /// 页面主标题（如「搜索」「我的收藏」）。
  static TextStyle pageTitle(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: color,
      );

  /// 区块标题（如「最近阅读」「热门标签」）。
  static TextStyle sectionTitle(Color color) => TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// 书封上的书名。
  static TextStyle coverTitle(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// 书封上的作者 / 副题。
  static TextStyle coverSubtitle(Color color) => TextStyle(
        fontSize: 15,
        height: 1.3,
        color: color,
      );

  /// 卡片主文字。
  static TextStyle cardTitle(Color color) => TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// 正文。
  static TextStyle body(Color color) => TextStyle(
        fontSize: 15,
        height: 1.45,
        color: color,
      );

  /// 说明 / 元信息。
  static TextStyle meta(Color color) => TextStyle(
        fontSize: 13,
        height: 1.3,
        color: color,
      );

  /// 数字（统计）。
  static TextStyle statNumber(Color color) => TextStyle(
        fontFamily: serif,
        fontSize: 34,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// 标签 / 筹码。
  static TextStyle chip(Color color, {bool selected = false}) => TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: color,
      );
}
