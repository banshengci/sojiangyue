import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 选中文字浮条里的一项。
@immutable
class SjSelectionAction {
  const SjSelectionAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

/// 选中文字浮条（深色胶囊）。
///
/// 设计约束（来自评审）：
///  - **首行最多 4 项**，其余收进「更多」。v2 原型放了 8 项，
///    与底栏功能重复且出现「✎ 同屏既指笔记又指批注」的图标冲突。
///  - 每项热区 ≥44×44。
///  - 图标语义不得与底栏重复：本组件默认不包含「问 AI」（底栏已有「问」）。
///
/// 用法：
/// ```dart
/// SjSelectionBar(
///   actions: [
///     SjSelectionAction(icon: Icons.brush, label: '高亮'),
///     SjSelectionAction(icon: Icons.format_underline, label: '划线'),
///     SjSelectionAction(icon: Icons.edit_note, label: '批注'),
///     SjSelectionAction(icon: Icons.copy, label: '复制'),
///   ],
///   onMore: () {},
/// )
/// ```
class SjSelectionBar extends StatelessWidget {
  const SjSelectionBar({
    super.key,
    required this.actions,
    this.onMore,
    this.moreLabel = '更多',
  }) : assert(actions.length <= 4, '浮条首行最多 4 项，其余请放进 onMore');

  final List<SjSelectionAction> actions;
  final VoidCallback? onMore;
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    // 浮条恒为深底浅字：与页面明暗无关，保证在任意阅读配色上都清晰。
    const fg = Color(0xFFEDEFEA);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SjSpace.xxs,
        vertical: SjSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(SjSizes.radiusCard),
        boxShadow: SjShadow.floating,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in actions)
            _SjSelAction(action: a, color: fg, onTap: a.onTap),
          if (onMore != null)
            _SjSelAction(
              action: SjSelectionAction(
                icon: Icons.more_horiz,
                label: moreLabel,
              ),
              color: fg,
              onTap: onMore,
            ),
        ],
      ),
    );
  }
}

class _SjSelAction extends StatelessWidget {
  const _SjSelAction({
    required this.action,
    required this.color,
    required this.onTap,
  });

  final SjSelectionAction action;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: action.label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SjSpace.s),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: SjSizes.minTouchTarget + 8,
            minHeight: SjSizes.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SjSpace.xs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, size: 18, color: color),
                const SizedBox(height: 2),
                Text(action.label, style: SjText.caption(color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
