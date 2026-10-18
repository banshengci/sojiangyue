/// 松江阅 · 小说阅读页工具栏（微信读书风格）
///
/// 三个部件：
///  - [SjReaderTopBar]：顶栏，仅「返回 + 目录 / 分享 / 更多」四个图标，不显示书名；
///  - [SjReaderBottomBar]：底栏，目录 / 笔记 / 进度 / 亮度 / 字体 五个工具位；
///  - [SjReaderFloatActions]：右下「A↑ / 听」两个深色浮动按钮。
///
/// 全部为纯展示组件，状态与行为由外部注入，便于单独预览与复用。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sj_reader_tokens.dart';

/// 底部工具栏的五个工具位。
enum SjReaderTool {
  /// 目录
  toc('目录'),

  /// 笔记 / 划线
  notes('笔记'),

  /// 阅读进度
  progress('进度'),

  /// 亮度与颜色
  appearance('亮度'),

  /// 字号与排版
  typography('字体');

  const SjReaderTool(this.label);

  /// 无障碍与提示文案。
  final String label;
}

// ---------------------------------------------------------------------------
// 顶栏
// ---------------------------------------------------------------------------

/// 阅读页顶栏。
///
/// 微信读书不显示书名，工具栏浮在正文之上，因此这里用透明底 + 细线图标。
class SjReaderTopBar extends StatelessWidget {
  const SjReaderTopBar({
    super.key,
    required this.palette,
    this.onBack,
    this.onToc,
    this.onShare,
    this.onMore,
    this.background,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 返回。
  final VoidCallback? onBack;

  /// 目录。
  final VoidCallback? onToc;

  /// 分享 / 导出。
  final VoidCallback? onShare;

  /// 更多。
  final VoidCallback? onMore;

  /// 顶栏底色，默认与纸张同色（微信读书的顶栏就是纸色，没有分割线）。
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final iconColor = palette.foreground.withValues(alpha: 0.82);
    return ColoredBox(
      color: background ?? palette.background,
      child: SizedBox(
        height: SjReaderSize.topBar,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 4),
            _TopIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: iconColor,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onTap: onBack,
            ),
            const Spacer(),
            _TopIcon(
              icon: Icons.toc_rounded,
              color: iconColor,
              tooltip: '目录',
              onTap: onToc,
            ),
            _TopIcon(
              icon: Icons.ios_share_rounded,
              color: iconColor,
              tooltip: '分享',
              onTap: onShare,
            ),
            _TopIcon(
              icon: Icons.more_vert_rounded,
              color: iconColor,
              tooltip: '更多',
              onTap: onMore,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.size = 21,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        containedInkWell: true,
        highlightShape: BoxShape.circle,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 底栏
// ---------------------------------------------------------------------------

/// 阅读页底部工具栏：五个图标位，无文字标签。
class SjReaderBottomBar extends StatelessWidget {
  const SjReaderBottomBar({
    super.key,
    required this.palette,
    required this.onSelected,
    this.active,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 点击某个工具位。
  final ValueChanged<SjReaderTool> onSelected;

  /// 当前展开的面板（对应工具位高亮）。
  final SjReaderTool? active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: SjReaderSize.bottomBar,
      child: Row(
        children: <Widget>[
          for (final tool in SjReaderTool.values)
            Expanded(
              child: _ToolSlot(
                tool: tool,
                selected: tool == active,
                palette: palette,
                onTap: () => onSelected(tool),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolSlot extends StatelessWidget {
  const _ToolSlot({
    required this.tool,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final SjReaderTool tool;
  final bool selected;
  final SjReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.accent : palette.subForeground;
    return Semantics(
      button: true,
      selected: selected,
      label: tool.label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: SizedBox.expand(
          child: Center(
            child: SjReaderToolIcon(
              tool: tool,
              color: color,
              size: SjReaderSize.toolIcon,
            ),
          ),
        ),
      ),
    );
  }
}

/// 工具位图标。
///
/// 目录 / 笔记 / 进度三个图形微信读书是自绘的，这里用 [CustomPaint] 还原，
/// 亮度用 Material 内置太阳，字体直接用「A」字。
class SjReaderToolIcon extends StatelessWidget {
  const SjReaderToolIcon({
    super.key,
    required this.tool,
    required this.color,
    this.size = SjReaderSize.toolIcon,
  });

  /// 工具位。
  final SjReaderTool tool;

  /// 图标颜色。
  final Color color;

  /// 图标边长。
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (tool) {
      case SjReaderTool.toc:
        return Icon(Icons.menu_rounded, size: size + 1, color: color);
      case SjReaderTool.notes:
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _NoteIconPainter(color)),
        );
      case SjReaderTool.progress:
        return SizedBox(
          width: size + 2,
          height: size,
          child: CustomPaint(painter: _ProgressIconPainter(color)),
        );
      case SjReaderTool.appearance:
        return Icon(Icons.wb_sunny_outlined, size: size + 1, color: color);
      case SjReaderTool.typography:
        return Text(
          'A',
          style: TextStyle(
            fontSize: size - 2,
            height: 1,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        );
    }
  }
}

/// 笔记：圆圈 + 一支斜笔（缺口的圆）。
class _NoteIconPainter extends CustomPainter {
  const _NoteIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2;

    final circle = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // 从 60° 画到 20°（顺时针预留右上角给笔尖）
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 3,
      math.pi * 2 - math.pi / 5,
      false,
      circle,
    );

    // 斜笔：从左下到右上
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final start = center + Offset(-radius * 0.46, radius * 0.46);
    final end = center + Offset(radius * 0.5, -radius * 0.5);
    canvas.drawLine(start, end, pen);
  }

  @override
  bool shouldRepaint(_NoteIconPainter oldDelegate) => oldDelegate.color != color;
}

/// 进度：两侧短横 + 中间圆点。
class _ProgressIconPainter extends CustomPainter {
  const _ProgressIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final dash = size.width * 0.17;
    canvas.drawLine(Offset(0, cy), Offset(dash, cy), paint);
    canvas.drawLine(
        Offset(size.width - dash, cy), Offset(size.width, cy), paint);
    canvas.drawCircle(
      Offset(size.width / 2, cy),
      size.width * 0.115,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ProgressIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// 浮动动作
// ---------------------------------------------------------------------------

/// 右下角「A↑ / 听」两个深色圆形按钮。
///
/// 微信读书在工具栏展开时把它们浮在底栏上方；关闭工具栏时一同隐藏。
class SjReaderFloatActions extends StatelessWidget {
  const SjReaderFloatActions({
    super.key,
    required this.palette,
    this.onTypography,
    this.onListen,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// A↑：调字号。
  final VoidCallback? onTypography;

  /// 听：听书。
  final VoidCallback? onListen;

  @override
  Widget build(BuildContext context) {
    final bg = palette.isDark
        ? const Color(0xFF2E2E2B).withValues(alpha: 0.92)
        : const Color(0xFF3E3B35).withValues(alpha: 0.86);
    final fg = Colors.white.withValues(alpha: 0.94);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _FloatButton(
          background: bg,
          onTap: onTypography,
          semanticLabel: '字体大小',
          child: _FontSizeGlyph(color: fg),
        ),
        const SizedBox(width: 12),
        _FloatButton(
          background: bg,
          onTap: onListen,
          semanticLabel: '听书',
          child: Text(
            '听',
            style: TextStyle(
              fontSize: 17,
              height: 1,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ],
    );
  }
}

class _FloatButton extends StatelessWidget {
  const _FloatButton({
    required this.background,
    required this.child,
    required this.semanticLabel,
    this.onTap,
  });

  final Color background;
  final Widget child;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: SjReaderSize.floatButton,
          height: SjReaderSize.floatButton,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// 「A」右上角带一个小上箭头的字形。
class _FontSizeGlyph extends StatelessWidget {
  const _FontSizeGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            left: 0,
            bottom: 1,
            child: Text(
              'A',
              style: TextStyle(
                fontSize: 17,
                height: 1,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          Positioned(
            right: -1,
            top: -2,
            child: Icon(Icons.arrow_upward_rounded, size: 10, color: color),
          ),
        ],
      ),
    );
  }
}
