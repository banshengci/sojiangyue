import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 图表组件：阅读热力图 / 柱状图 / 进度条。
///
/// 颜色沿用品牌绿阶，深浅色模式各自取阶。

/// 阅读热力图（每行一个周次，每行 7 格，等级 0–4）。
class SjHeatmap extends StatelessWidget {
  const SjHeatmap({
    super.key,
    required this.levels,
    this.gap = 6,
    this.radius = 6,
  });

  /// 等级矩阵，取值 0（无）–4（最深）。
  final List<List<int>> levels;
  final double gap;
  final double radius;

  static const List<Color> _light = [
    Color(0xFFE6EDE8),
    Color(0xFFC3DCD0),
    Color(0xFF8FC5B4),
    Color(0xFF59A17D),
    Color(0xFF2E6B4F),
  ];

  static const List<Color> _dark = [
    Color(0xFF1F3A30),
    Color(0xFF2A5342),
    Color(0xFF3A7358),
    Color(0xFF4C8F6C),
    Color(0xFF59A17D),
  ];

  @override
  Widget build(BuildContext context) {
    final scale =
        Theme.of(context).brightness == Brightness.dark ? _dark : _light;
    return Column(
      children: [
        for (var r = 0; r < levels.length; r++)
          Padding(
            padding: EdgeInsets.only(bottom: r == levels.length - 1 ? 0 : gap),
            child: Row(
              children: [
                for (var i = 0; i < levels[r].length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scale[levels[r][i].clamp(0, 4)],
                          borderRadius: BorderRadius.circular(radius),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 柱状图（值域 0–1，可高亮一根）。
class SjBarChart extends StatelessWidget {
  const SjBarChart({
    super.key,
    required this.values,
    this.height = 150,
    this.gap = 14,
    this.highlightIndex,
  });

  final List<double> values;
  final double height;
  final double gap;
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: (height * values[i]).clamp(6.0, height),
                      decoration: BoxDecoration(
                        color: i == highlightIndex ? c.clay : c.pine,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 3, color: c.divider),
      ],
    );
  }
}

/// 进度条（值域 0–1）。
class SjProgressBar extends StatelessWidget {
  const SjProgressBar({super.key, required this.value, this.height = 10});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final radius = BorderRadius.circular(SjSizes.radiusPill);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.frost.withAlpha(90),
                    borderRadius: radius,
                  ),
                ),
              ),
              Container(
                width: constraints.maxWidth * value.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: c.pine,
                  borderRadius: radius,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
