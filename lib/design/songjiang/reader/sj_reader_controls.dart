/// 松江阅 · 阅读页面板通用控件
///
/// 微信读书的面板语言很简单：胶囊、白色圆点滑块、分段选择器、图标+小字。
/// 这里把这四类控件收在一处，五个面板共用，改一处全局生效。
library;

import 'package:flutter/material.dart';

import 'sj_reader_tokens.dart';

// ---------------------------------------------------------------------------
// 面板容器
// ---------------------------------------------------------------------------

/// 面板容器：顶部圆角 + 可选拖拽条。
///
/// 微信读书只有「目录 / 笔记」这类高面板带拖拽条，亮度与字体面板没有。
///
/// [expand] 用于外层已经给定高度的场景（目录、笔记、二级设置页）：
/// 此时内容按剩余空间撑满，内部可以安全使用 [Expanded] / 列表。
class SjReaderSheet extends StatelessWidget {
  const SjReaderSheet({
    super.key,
    required this.palette,
    required this.child,
    this.showHandle = false,
    this.expand = false,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 面板内容。
  final Widget child;

  /// 是否显示顶部拖拽条。
  final bool showHandle;

  /// 内容是否撑满外部给定高度。
  final bool expand;

  /// 内容内边距。
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SjReaderSize.sheetRadius),
        ),
      ),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          if (showHandle)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: SjReaderSize.handleSize.width,
                height: SjReaderSize.handleSize.height,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius:
                      BorderRadius.circular(SjReaderSize.handleSize.height),
                ),
              ),
            ),
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 胶囊按钮
// ---------------------------------------------------------------------------

/// 胶囊按钮。
///
/// 用于「去当前」「阅读明细」「字体样式 ›」这类次级动作。
class SjPillButton extends StatelessWidget {
  const SjPillButton({
    super.key,
    required this.palette,
    required this.label,
    this.onTap,
    this.leading,
    this.trailing,
    this.height = 36,
    this.selected = false,
    this.expand = false,
    this.outlined = false,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 文案。
  final String label;

  /// 点击。
  final VoidCallback? onTap;

  /// 前置图标。
  final Widget? leading;

  /// 后置图标（一般是 `chevron_right`）。
  final Widget? trailing;

  /// 高度。
  final double height;

  /// 选中态（描边 + 强调文字）。
  final bool selected;

  /// 是否占满可用宽度。
  final bool expand;

  /// 是否用描边代替底色。
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? palette.accent : palette.foreground;
    final bg = outlined ? Colors.transparent : palette.chip;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          IconTheme.merge(
            data: IconThemeData(color: fg, size: 15),
            child: leading!,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SjReaderText.pill(fg, selected: selected),
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 3),
          IconTheme.merge(
            data: IconThemeData(color: fg.withValues(alpha: 0.6), size: 14),
            child: trailing!,
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
          onTap: onTap,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: expand ? 10 : 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
              border: Border.all(
                color: outlined || selected
                    ? palette.divider
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分段选择器
// ---------------------------------------------------------------------------

/// 分段选择器（小 / 边距 / 大）。
///
/// 视觉是「胶囊轨道 + 白色圆点」：选中项套一个白色圆形滑块，与微信读书一致。
class SjSegmented extends StatelessWidget {
  const SjSegmented({
    super.key,
    required this.palette,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 选项文案。
  final List<String> labels;

  /// 选中下标。
  final int index;

  /// 选中变化。
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: SjReaderSize.segmentHeight,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    width: i == index ? SjReaderSize.segmentHeight : null,
                    height: i == index ? SjReaderSize.segmentHeight : null,
                    decoration: i == index
                        ? BoxDecoration(
                            color: palette.knob,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          )
                        : null,
                    child: Center(
                      child: Text(
                        labels[i],
                        style: SjReaderText.pill(
                          i == index
                              ? palette.foreground
                              : palette.subForeground,
                          selected: i == index,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 圆点滑块
// ---------------------------------------------------------------------------

/// 胶囊轨道 + 白色圆点的滑块。
///
/// [value] 取值 0–1；[leading] / [trailing] 放在轨道两端（例如小 A / 大 A），
/// [knobLabel] 显示在圆点里（例如字号数字）。
class SjKnobSlider extends StatelessWidget {
  const SjKnobSlider({
    super.key,
    required this.palette,
    required this.value,
    required this.onChanged,
    this.leading,
    this.trailing,
    this.knobLabel,
    this.onChangeEnd,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 归一化取值 0–1。
  final double value;

  /// 拖动中回调。
  final ValueChanged<double>? onChanged;

  /// 结束拖动回调（用于落库）。
  final VoidCallback? onChangeEnd;

  /// 轨道左端装饰。
  final Widget? leading;

  /// 轨道右端装饰。
  final Widget? trailing;

  /// 圆点内文案。
  final String? knobLabel;

  static const double _knob = SjReaderSize.sliderKnob;
  static const double _inset = 3;

  void _emit(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width - _knob - _inset * 2;
    if (width <= 0) return;
    final v = ((dx - _inset - _knob / 2) / width).clamp(0.0, 1.0);
    onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth - _knob - _inset * 2;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _emit(context, d.localPosition.dx),
          onHorizontalDragUpdate: (d) => _emit(context, d.localPosition.dx),
          onHorizontalDragEnd: (_) => onChangeEnd?.call(),
          onTapUp: (_) => onChangeEnd?.call(),
          child: Container(
            height: SjReaderSize.sliderHeight,
            decoration: BoxDecoration(
              color: palette.chip,
              borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                if (leading != null)
                  Positioned(left: 12, child: leading!),
                if (trailing != null)
                  Positioned(right: 12, child: trailing!),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  left: _inset + width * value.clamp(0.0, 1.0),
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      color: palette.knob,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: knobLabel == null
                        ? null
                        : Center(
                            child: Text(
                              knobLabel!,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                color: palette.foreground,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 其他小组件
// ---------------------------------------------------------------------------

/// 图标 + 小字的面板动作（笔记面板的四个入口）。
class SjSheetAction extends StatelessWidget {
  const SjSheetAction({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
    this.onTap,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 图标。
  final IconData icon;

  /// 文案。
  final String label;

  /// 点击。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 24, color: palette.subForeground),
            const SizedBox(height: 7),
            Text(label, style: SjReaderText.actionLabel(palette.faint)),
          ],
        ),
      ),
    );
  }
}

/// 统计块（进度面板：1% 阅读进度）。
class SjStatBlock extends StatelessWidget {
  const SjStatBlock({
    super.key,
    required this.palette,
    required this.value,
    required this.label,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 主数字。
  final String value;

  /// 说明。
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(value, style: SjReaderText.statValue(palette.foreground)),
        const SizedBox(height: 6),
        Text(label, style: SjReaderText.statLabel(palette.faint)),
      ],
    );
  }
}

/// 色板（颜色 / 背景一行里的小方块）。
class SjSwatch extends StatelessWidget {
  const SjSwatch({
    super.key,
    required this.palette,
    required this.color,
    this.selected = false,
    this.onTap,
    this.child,
    this.size = const Size(48, 38),
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 色块底色。
  final Color color;

  /// 是否选中。
  final bool selected;

  /// 点击。
  final VoidCallback? onTap;

  /// 色块内的装饰（夜间色块里的月亮）。
  final Widget? child;

  /// 尺寸。
  final Size size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? palette.accent : palette.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}
