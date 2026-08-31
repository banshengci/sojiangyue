import 'package:songjiang_reader/providers/heatmap_data.dart';
import 'package:songjiang_reader/providers/statistic_data.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HeatmapChart extends ConsumerWidget {
  const HeatmapChart({super.key});

  /// 松绿色阶：由浅到深对应阅读时长递增，做出类似贡献图的层次感。
  ///
  /// 数据集单位是**秒**（`SUM(reading_time)`），因此阈值取 1 / 5 / 15 / 30 / 60 分钟。
  ///
  /// 注意：包内 `DatasetsUtil.getColor` 取的是「key <= 当日数值」中的最大 key，
  /// 所以最小 key 必须是 1 —— 否则当天阅读时长小于最小 key 时返回 null，格子会没颜色。
  static const Map<int, Color> _pineScale = {
    1: Color(0x3C1B6B44), // 松绿 24%
    300: Color(0x6E1B6B44), // 43%，≥ 5 分钟
    900: Color(0xAA1B6B44), // 67%，≥ 15 分钟
    1800: Color(0xFF1B6B44), // 实色，≥ 30 分钟
    3600: SongJiangColors.pineDeep, // ≥ 1 小时
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticData = ref.watch(heatmapDataProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return HeatMap(
      showColorTip: false,
      blockBorder: Border.all(
        // 原为固定的 Colors.black12，深色模式下一圈黑边很脏
        color: isDark
            ? Colors.white.withAlpha(28)
            : SongJiangColors.pine.withAlpha(38),
        style: BorderStyle.solid,
        width: 0.25,
        strokeAlign: BorderSide.strokeAlignOutside,
      ),
      defaultColor: Theme.of(context).colorScheme.surface,
      datasets: statisticData.when(
          data: (data) => data, loading: () => {}, error: (error, stack) => {}),
      // opacity 模式只吃单色（靠透明度表现强弱）；改用 color 模式才能做多级色阶
      colorMode: ColorMode.color,
      showText: false,
      scrollable: true,
      colorsets: _pineScale,
      onClick: (value) {
        ref.read(statisticDataProvider.notifier).setIsSelectingDay(true, value);
      },
    );
  }
}
