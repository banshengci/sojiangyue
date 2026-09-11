import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 成就徽章卡：单字篆意图形 + 名称。
///
/// 已解锁为松绿实底 + 纸白字；未解锁为松霜浅底 + 弱化字。
class SjAchievementBadge extends StatelessWidget {
  const SjAchievementBadge({
    super.key,
    required this.glyph,
    required this.label,
    this.unlocked = true,
    this.tooltip,
    this.onTap,
  });

  final String glyph;
  final String label;
  final bool unlocked;

  /// 达成条件（悬停 / 长按查看）。
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final Color bg = unlocked ? c.pine : c.frost.withAlpha(90);
    final Color fg = unlocked ? c.onPine : c.frost;

    final Widget badge = Material(
      color: bg,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                glyph,
                style: TextStyle(
                  fontFamily: SjText.serif,
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return tooltip == null ? badge : Tooltip(message: tooltip!, child: badge);
  }
}

/// 主按钮（松绿胶囊 + 纸白文字）。
class SjPrimaryButton extends StatelessWidget {
  const SjPrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Material(
      color: c.pine,
      borderRadius: BorderRadius.circular(SjSizes.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SjSizes.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: c.onPine),
                const SizedBox(width: SjSpace.s),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: c.onPine,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
