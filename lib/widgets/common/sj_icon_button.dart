import 'package:flutter/material.dart';
import 'package:songjiang_reader/design/songjiang/sj_icon.dart';

/// 品牌图标按钮：外观与 Material [IconButton] 一致，但渲染品牌 SVG 图标。
///
/// 用于 AppBar / ListTile 等场景，替代只能接受 [IconData] 的 [IconButton]。
class SjIconButton extends StatelessWidget {
  const SjIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 24,
    this.color,
    this.padding = const EdgeInsets.all(8),
  });

  final SjIconName icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final btn = IconButton(
      onPressed: onPressed,
      padding: padding,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: SjIcon(icon, size: size, color: color),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}
