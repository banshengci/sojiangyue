import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 书卡右下角的阅读进度环。
///
/// 规格：直径 28（默认）· 线宽 2.5 · 轨道用 `divider` · 进度用 `pine`。
/// 用于书架网格里替代「62%」这类纯文字，让进度可一眼扫读。
class SjProgressRing extends StatelessWidget {
  const SjProgressRing({
    super.key,
    required this.progress,
    this.size = 28,
    this.strokeWidth = 2.5,
    this.showLabel = false,
  });

  /// 0.0 – 1.0。
  final double progress;
  final double size;
  final double strokeWidth;

  /// 是否在环中心显示百分比文字（直径 <32 时建议关掉）。
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final value = progress.clamp(0.0, 1.0);
    return Semantics(
      label: '阅读进度 ${(value * 100).round()}%',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _SjRingPainter(
                value: value,
                track: c.divider,
                color: c.pine,
                strokeWidth: strokeWidth,
              ),
            ),
            if (showLabel)
              Text(
                '${(value * 100).round()}',
                style: SjText.caption(c.inkSoft),
              ),
          ],
        ),
      ),
    );
  }
}

class _SjRingPainter extends CustomPainter {
  const _SjRingPainter({
    required this.value,
    required this.track,
    required this.color,
    required this.strokeWidth,
  });

  final double value;
  final Color track;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    if (value <= 0) return;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_SjRingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
