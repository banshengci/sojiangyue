import 'package:flutter/material.dart';

import '../data/sj_view_models.dart';
import '../sj_badge.dart';
import '../sj_charts.dart';
import '../sj_tokens.dart';

/// 「成就」页视觉（对应画板 08 · 页面二）。
///
/// 纯展示：数据由 [SjAchievementsData] 传入（解锁状态来自真实阅读数据）。
class SjAchievementsPage extends StatelessWidget {
  const SjAchievementsPage({super.key, required this.data});

  final SjAchievementsData data;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final items = data.items;

    return ListView(
      padding: const EdgeInsets.fromLTRB(SjSpace.page, 12, SjSpace.page, 120),
      children: [
        Row(
          children: [
            Expanded(child: Text('成就', style: SjText.pageTitle(c.ink))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: c.pine,
                borderRadius: BorderRadius.circular(SjSizes.radiusPill),
              ),
              child: Text(
                '${data.unlockedCount} / ${data.total}',
                style: TextStyle(
                  fontFamily: SjText.serif,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: c.onPine,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: SjSpace.l),
        Text(
          '已完成 ${data.unlockedCount} / ${data.total} 个成就',
          style: SjText.meta(c.inkSoft),
        ),
        const SizedBox(height: SjSpace.s),
        SjProgressBar(value: data.progress),

        const SizedBox(height: SjSpace.xl),
        for (var r = 0; r < items.length; r += 3)
          Padding(
            padding: const EdgeInsets.only(bottom: SjSpace.l),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var k = 0; k < 3; k++) ...[
                  if (k > 0) const SizedBox(width: SjSpace.m),
                  Expanded(
                    child: r + k < items.length
                        ? SjAchievementBadge(
                            glyph: items[r + k].glyph,
                            label: items[r + k].label,
                            unlocked: items[r + k].unlocked,
                            tooltip: items[r + k].requirement,
                            onTap: () {},
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
