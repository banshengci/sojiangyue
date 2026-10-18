import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 最小可点尺寸包装。
///
/// 把任意视觉尺寸的控件（图标、色点、chip）的可点区域撑到
/// [SjSizes.minTouchTarget]（44×44），**不改变视觉大小**。
///
/// 为什么需要它：评审实测 v2 原型里返回键只有 5.1×25、主题色点 18×18、
/// 顶栏图标 17×17，全部低于 44×44 下限，而它们恰恰是最高频的动作。
///
/// 用法：
/// ```dart
/// SjTapTarget(
///   semanticLabel: '返回',
///   onTap: () => Navigator.pop(context),
///   child: const Icon(Icons.chevron_left),
/// )
/// ```
class SjTapTarget extends StatelessWidget {
  const SjTapTarget({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.size = SjSizes.minTouchTarget,
    this.behavior = HitTestBehavior.opaque,
  });

  /// 视觉内容（可以比 [size] 小，会被居中）。
  final Widget child;

  /// 点击回调。为 null 时不可点，但仍占位。
  final VoidCallback? onTap;

  /// 读屏标签。**纯图标按钮必须提供**。
  final String? semanticLabel;

  /// 热区边长，默认 44。
  final double size;

  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    Widget body = SizedBox(
      width: size,
      height: size,
      child: Center(child: child),
    );

    if (onTap != null) {
      body = GestureDetector(
        behavior: behavior,
        onTap: onTap,
        child: body,
      );
    }

    if (semanticLabel != null) {
      body = Semantics(
        label: semanticLabel,
        button: onTap != null,
        child: body,
      );
    }

    return body;
  }
}
