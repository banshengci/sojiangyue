// lib/models/reading_insight.dart
//
// 阅读洞察的产出模型（C-02 速度 / C-03 节律 / C-05 卡住的书）。
//
// 空数据约定（§7.7）：一律走「数据不足 / 继续阅读以生成洞察」态，
// 禁止渲染 0 页/小时、NaN、Infinity——除法前必须判分母 + 样本数。

import 'package:songjiang_reader/models/book.dart';

/// 某本书的阅读速度估算。
class ReadingSpeed {
  const ReadingSpeed({
    this.pagesPerHour,
    this.remainingHours,
    this.sampleCount = 0,
  });

  /// 每小时页数（约值）；数据不足时为 null。
  final double? pagesPerHour;

  /// 按当前速度读完剩余内容还需几小时；数据不足时为 null。
  final double? remainingHours;

  /// 参与估算的会话样本数。
  final int sampleCount;

  /// 样本不足 3 次 → 不展示数值，走「数据不足」态。
  bool get insufficient => sampleCount < 3;
}

/// 空的小时直方图（24 格全 0），供 [ReadingRhythm] 默认值使用。
const List<int> kEmptyHourHistogram = <int>[
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];

/// 空的星期直方图（7 格全 0），供 [ReadingRhythm] 默认值使用。
const List<int> kEmptyWeekdayHistogram = <int>[0, 0, 0, 0, 0, 0, 0];

/// 阅读节律（时段 / 星期 / 单次时长 / 连续天数）。
class ReadingRhythm {
  const ReadingRhythm({
    this.hourHistogram = kEmptyHourHistogram,
    this.weekdayHistogram = kEmptyWeekdayHistogram,
    this.averageSessionSeconds = 0,
    this.longestSessionSeconds = 0,
    this.longestStreakDays = 0,
  });

  /// 按开始小时聚合的会话数，长度 24（下标 = `startedAt.hour`）。
  ///
  /// 「整段归入开始小时」是刻意的简化（§9 #5）：保证各小时之和 == 总时长零误差。
  final List<int> hourHistogram;

  /// 按星期聚合的会话数，长度 7（下标 = `startedAt.weekday - 1`）。
  final List<int> weekdayHistogram;

  /// 平均单次会话时长（秒）。
  final int averageSessionSeconds;

  /// 最长单次会话时长（秒）。
  final int longestSessionSeconds;

  /// 最长连续阅读天数。
  final int longestStreakDays;

  /// 会话样本数（各小时之和，等价于总会话数）。
  int get sampleCount => hourHistogram.fold<int>(0, (sum, v) => sum + v);

  /// 样本不足 3 次 → 走「数据不足」态（与 [ReadingSpeed] 同口径）。
  bool get insufficient => sampleCount < 3;
}

/// 「卡住的书」：进度已过半但很久没动。
class StuckBook {
  const StuckBook({
    required this.book,
    required this.progress,
    required this.idleDays,
  });

  final Book book;

  /// 阅读进度（0.0 ~ 1.0，与 `Book.readingPercentage` 同口径）。
  final double progress;

  /// 距最后一次阅读的天数。
  final int idleDays;
}
