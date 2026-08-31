import 'package:songjiang_reader/providers/statistic_data.dart';
import 'package:songjiang_reader/utils/date/convert_seconds.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticChart extends ConsumerStatefulWidget {
  final List<int> readingTime;
  final List<String> xLabels;

  const StatisticChart(
      {super.key, required this.readingTime, required this.xLabels});

  @override
  ConsumerState<StatisticChart> createState() => _StatisticChartState();
}

class _StatisticChartState extends ConsumerState<StatisticChart> {
  int? touchedIndex;
  // 通过 context 取色（跟随用户在外观里选的主题色），
  // 不再依赖 navigatorKey —— 后者在页面未挂载时取色会抛异常。
  Color get bottomColor => Theme.of(context).colorScheme.primary;

  Color get topColor => Theme.of(context).colorScheme.primary.withAlpha(120);

  /// 纵轴上限。原实现直接对列表 reduce，**空列表会抛 Bad state: No element**，
  /// 无阅读记录时统计页会崩，这里补上空判断。
  double get maxY {
    if (widget.readingTime.isEmpty) return 1;
    final peak =
        widget.readingTime.reduce((value, element) => value > element ? value : element);
    // 全 0 时给个最小刻度，避免柱子高度全部塌成 0
    return peak <= 0 ? 1 : peak * 1.2;
  }

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        barTouchData: barTouchData,
        titlesData: titlesData,
        borderData: borderData,
        barGroups: barGroups,
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
      ),
    );
  }

  BarTouchData get barTouchData {
    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (BarChartGroupData group) {
          return Colors.white.withAlpha(0);
        },
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          if (touchedIndex != null && group.x.toInt() == touchedIndex) {
            return BarTooltipItem(
              convertSeconds(widget.readingTime[group.x.toInt()]),
              TextStyle(
                color: topColor,
                fontWeight: FontWeight.bold,
              ),
            );
          }
          return null;
        },
      ),
      touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
        if (response?.spot != null) {
          setState(() {
            touchedIndex = response!.spot!.touchedBarGroupIndex;
            if (event is FlTapUpEvent) {
              if (widget.readingTime.length == 12) {
                ref
                    .read(statisticDataProvider.notifier)
                    .touchMonth(touchedIndex!);
              } else {
                ref
                    .read(statisticDataProvider.notifier)
                    .touchDay(widget.xLabels.length, touchedIndex!);
              }
            }
          });
        }
      },
    );
  }

  FlTitlesData get titlesData => FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: getTitles,
          ),
        ),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      );

  FlBorderData get borderData => FlBorderData(
        show: false,
      );

  LinearGradient get _barsGradient => LinearGradient(
        colors: [
          bottomColor,
          topColor,
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      );

  List<BarChartGroupData> get barGroups {
    List<BarChartGroupData> barGroups = [];
    final trackColor = bottomColor.withAlpha(30);
    for (int i = 0; i < widget.readingTime.length; i++) {
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: widget.readingTime[i].toDouble(),
              gradient: _barsGradient,
              width: 16,
              borderRadius: BorderRadius.circular(5),
              // 背景轨道：让"读了多少"有参照，空档期也有存在感
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY,
                color: trackColor,
              ),
            ),
          ],
          showingTooltipIndicators: [0],
        ),
      );
    }
    return barGroups;
  }

  SideTitleWidget getTitles(double value, TitleMeta meta) {
    var style = TextStyle(
      color: bottomColor,
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    return SideTitleWidget(
        meta: meta,
        child: Text(
          widget.xLabels[value.toInt()],
          style: style,
        ));
  }
}
