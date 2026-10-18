import 'package:flutter/material.dart';

import 'sj_tap_target.dart';
import 'sj_tokens.dart';

/// 区块标题：左侧衬线标题 + 右侧动作（如「查看全部 ›」）。
///
/// 右侧动作的可点区域被撑到 44 高（评审实测 v2 的「查看全部」只有 58.8×19）。
class SjSectionHeader extends StatelessWidget {
  const SjSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final hasAction = actionLabel != null && onAction != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: SjSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: SjText.sectionTitle(c.ink)),
          ),
          if (hasAction)
            SjTapTarget(
              onTap: onAction,
              semanticLabel: actionLabel,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!, style: SjText.meta(c.inkSoft)),
                  Icon(Icons.chevron_right, size: 18, color: c.borderStrong),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
