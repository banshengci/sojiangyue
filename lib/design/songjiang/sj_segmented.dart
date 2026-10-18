import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 分段控件（2–4 个互斥选项）。
///
/// 与 `SjChip` 的区别：chip 是「可多选的标签」，segmented 是「单选视图切换」。
/// 每项热区高度固定 [SjSizes.minTouchTarget]，宽度不小于 44。
class SjSegmented extends StatelessWidget {
  const SjSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.semanticLabels,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 每项的读屏标签（可选，默认用 [labels]）。
  final List<String>? semanticLabels;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.divider,
        borderRadius: BorderRadius.circular(SjSizes.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              label: semanticLabels != null ? semanticLabels![i] : labels[i],
              selected: i == selectedIndex,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  constraints: const BoxConstraints(
                    minWidth: SjSizes.minTouchTarget,
                    minHeight: SjSizes.minTouchTarget - 6,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: SjSpace.s),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selectedIndex ? c.pine : Colors.transparent,
                    borderRadius: BorderRadius.circular(SjSizes.radiusPill),
                  ),
                  child: Text(
                    labels[i],
                    style: SjText.chip(
                      i == selectedIndex ? c.onPine : c.inkSoft,
                      selected: i == selectedIndex,
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
