import 'package:flutter/material.dart';

import 'sj_icon.dart';
import 'sj_tokens.dart';

/// 区块标题（如「最近阅读」「热门标签」）。
class SjSectionHeader extends StatelessWidget {
  const SjSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: SjText.sectionTitle(c.inkSoft))),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 统计项（数字 + 标签），用于「我的」页的已读 / 收藏 / 笔记。
class SjStatTile extends StatelessWidget {
  const SjStatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: SjText.statNumber(c.ink)),
        const SizedBox(height: 6),
        Text(label, style: SjText.meta(c.inkSoft)),
      ],
    );
  }
}

/// 菜单行（品牌图标 + 文字 + 箭头）。
///
/// [icon] 为品牌图标集（icons-24）中的一枚；图标默认以砂朱着色。
class SjMenuRow extends StatelessWidget {
  const SjMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
    this.iconColor,
  });

  final SjIconName icon;
  final String label;
  final VoidCallback? onTap;

  /// 覆盖右侧默认箭头（例如换成开关）。
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        child: Row(
          children: [
            SjIcon(icon, size: 22, color: iconColor ?? c.clay),
            const SizedBox(width: SjSpace.l),
            Expanded(
              child: Text(
                label,
                style: SjText.cardTitle(c.ink).copyWith(fontSize: 16),
              ),
            ),
            trailing ??
                Icon(Icons.chevron_right, size: 22, color: c.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// 圆角卡片容器，用于承载菜单列表等。
class SjCard extends StatelessWidget {
  const SjCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(SjSizes.radiusCard),
        border: Border.all(color: c.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 卡片内的细分隔线。
class SjCardDivider extends StatelessWidget {
  const SjCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 18,
      endIndent: 18,
      color: SjColors.of(context).divider,
    );
  }
}
