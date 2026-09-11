import 'package:flutter/material.dart';

import '../data/sj_view_models.dart';
import '../sj_charts.dart';
import '../sj_list_items.dart';
import '../sj_tokens.dart';

/// 「数据统计」页视觉（对应画板 08 · 页面一）。
///
/// 纯展示：数据由 [SjStatisticsData] 传入（真实阅读记录）。
class SjStatisticsPage extends StatelessWidget {
  const SjStatisticsPage({super.key, required this.data});

  final SjStatisticsData data;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final delta = data.monthDeltaLabel;

    return ListView(
      padding: const EdgeInsets.fromLTRB(SjSpace.page, 12, SjSpace.page, 120),
      children: [
        Text('数据统计', style: SjText.pageTitle(c.ink)),

        const SizedBox(height: SjSpace.l),
        SjCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本月阅读时长', style: SjText.meta(c.inkSoft)),
              const SizedBox(height: 6),
              Text(data.monthDurationLabel, style: SjText.statNumber(c.ink)),
              if (delta != null) ...[
                const SizedBox(height: 6),
                Text(delta, style: SjText.meta(c.pine)),
              ],
            ],
          ),
        ),

        const SizedBox(height: SjSpace.xl),
        Row(
          children: [
            Expanded(
              child: SjStatTile(
                value: '${data.currentStreak}',
                label: '连续阅读 · 天',
              ),
            ),
            Expanded(
              child: SjStatTile(
                value: '${data.finishedBooks}',
                label: '累计读完 · 本',
              ),
            ),
            Expanded(
              child: SjStatTile(
                value: '${data.dailyAverageMinutes}',
                label: '日均 · 分钟',
              ),
            ),
          ],
        ),

        const SizedBox(height: SjSpace.xl),
        const SjSectionHeader(title: '阅读热力　最近 4 周'),
        const SizedBox(height: SjSpace.m),
        SjCard(
          padding: const EdgeInsets.all(20),
          child: SjHeatmap(levels: data.heatLevels),
        ),

        const SizedBox(height: SjSpace.xl),
        const SjSectionHeader(title: '本周阅读'),
        const SizedBox(height: SjSpace.m),
        SjCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              SjBarChart(
                values: data.weeklyNormalized,
                highlightIndex: data.weeklyPeakIndex,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final d in SjStatisticsData.weekdays)
                    Expanded(
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: SjText.meta(c.inkSoft),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
