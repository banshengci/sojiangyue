import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 分类筹码（如「全部 / 文学 / 历史 / 诗词」）。
///
/// 选中态使用松绿实底 + 纸白文字；未选中态为白底 + 描边。
class SjChip extends StatelessWidget {
  const SjChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SjSizes.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.pine : c.card,
          borderRadius: BorderRadius.circular(SjSizes.radiusPill),
          border: Border.all(
            color: selected ? Colors.transparent : c.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: SjText.chip(selected ? c.onPine : c.ink, selected: selected),
        ),
      ),
    );
  }
}

/// 热门标签（弱化底色的轻量筹码）。
class SjTagChip extends StatelessWidget {
  const SjTagChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SjSizes.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: c.frost.withAlpha(64),
          borderRadius: BorderRadius.circular(SjSizes.radiusPill),
        ),
        child: Text(label, style: SjText.chip(c.ink)),
      ),
    );
  }
}
