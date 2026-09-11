/// 松江阅页面 · 数据接入层
///
/// 把应用真实数据（tb_reading_time / tb_books / tb_notes）映射为页面视图模型。
/// 页面只依赖 [SjStatisticsData] 等模型，不直接触碰 DAO。
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/reading_time.dart';

import 'sj_view_models.dart';

/// 「读完」的判定阈值（与书架筛选保持一致）。
const double _finishedThreshold = 0.98;

/// 热力等级阈值（秒）：<10 分 / <30 分 / <60 分 / ≥60 分。
const List<int> _heatThresholds = [600, 1800, 3600];

// ==================== 数据统计 ====================

/// 数据统计（真实数据）。
final sjStatisticsProvider = FutureProvider<SjStatisticsData>((ref) async {
  final now = DateTime.now();

  final monthSeconds = _sum(
    await readingTimeDao.selectReadingTimeOfMonth(now),
  );
  final prevMonthSeconds = _sum(
    await readingTimeDao.selectReadingTimeOfMonth(
      DateTime(now.year, now.month - 1, 1),
    ),
  );

  final perDay = await _readingSecondsByDay();
  final activeDays = _activeDays(perDay);
  final streak = _streak(activeDays, now);

  final daysWithReading = activeDays.length;
  final totalSeconds = await readingTimeDao.selectTotalReadingTime();

  final books = await bookDao.selectNotDeleteBooks();
  final finishedBooks =
      books.where((b) => b.readingPercentage >= _finishedThreshold).length;

  final weekly = await readingTimeDao.selectReadingTimeOfWeek(now);

  return SjStatisticsData(
    monthSeconds: monthSeconds,
    prevMonthSeconds: prevMonthSeconds,
    currentStreak: streak.current,
    finishedBooks: finishedBooks,
    dailyAverageMinutes: daysWithReading == 0
        ? 0
        : (totalSeconds / daysWithReading / 60).round(),
    heatLevels: _buildHeatmap(perDay, now),
    weeklySeconds: weekly,
  );
});

// ==================== 成就 ====================

/// 成就（由真实阅读数据判定解锁）。
final sjAchievementsProvider =
    FutureProvider<SjAchievementsData>((ref) async {
  final perDay = await _readingSecondsByDay();
  final activeDays = _activeDays(perDay);
  final streak = _streak(activeDays, DateTime.now());

  final daysWithReading = activeDays.length;
  final maxDailySeconds =
      perDay.isEmpty ? 0 : perDay.values.reduce(math.max);
  final totalSeconds = await readingTimeDao.selectTotalReadingTime();
  final notes = await readingTimeDao.selectTotalNumberOfNotes();

  final books = await bookDao.selectNotDeleteBooks();
  final finishedBooks =
      books.where((b) => b.readingPercentage >= _finishedThreshold).length;
  final ratedBooks = books.where((b) => b.rating > 0).length;

  final items = <SjAchievementItem>[
    SjAchievementItem(
      glyph: '读',
      label: '初读',
      requirement: '读完第一本',
      unlocked: finishedBooks >= 1,
    ),
    SjAchievementItem(
      glyph: '晓',
      label: '破晓',
      requirement: '连续阅读 7 天',
      unlocked: streak.longest >= 7,
    ),
    SjAchievementItem(
      glyph: '半',
      label: '半月',
      requirement: '连续阅读 15 天',
      unlocked: streak.longest >= 15,
    ),
    SjAchievementItem(
      glyph: '百',
      label: '百日',
      requirement: '累计 100 天有阅读',
      unlocked: daysWithReading >= 100,
    ),
    SjAchievementItem(
      glyph: '卷',
      label: '十卷',
      requirement: '读完 10 本',
      unlocked: finishedBooks >= 10,
    ),
    SjAchievementItem(
      glyph: '藏',
      label: '藏书',
      requirement: '书架 20 本',
      unlocked: books.length >= 20,
    ),
    SjAchievementItem(
      glyph: '记',
      label: '笔记',
      requirement: '写满 50 条笔记',
      unlocked: notes >= 50,
    ),
    SjAchievementItem(
      glyph: '评',
      label: '评赏',
      requirement: '收藏 20 本',
      unlocked: ratedBooks >= 20,
    ),
    SjAchievementItem(
      glyph: '时',
      label: '万时',
      requirement: '累计阅读 10 小时',
      unlocked: totalSeconds >= 36000,
    ),
    SjAchievementItem(
      glyph: '长',
      label: '长读',
      requirement: '单日阅读 3 小时',
      unlocked: maxDailySeconds >= 10800,
    ),
  ];

  return SjAchievementsData(items: items);
});

// ==================== 收藏 ====================

/// 收藏（来源：书架中用户评分 > 0 的书）。
final sjFavoritesProvider = FutureProvider<List<SjFavoriteBook>>((ref) async {
  final books = await bookDao.selectNotDeleteBooks();
  final favorites = books.where((b) => b.rating > 0).toList()
    ..sort((a, b) => b.updateTime.compareTo(a.updateTime));
  return favorites
      .map(
        (b) => SjFavoriteBook(
          id: b.id,
          title: b.title,
          author: b.author.isEmpty ? '佚名' : b.author,
          progress: b.readingPercentage,
        ),
      )
      .toList();
});

// ==================== 我的 ====================

/// 「我的」页统计（真实数据）。
final sjProfileProvider = FutureProvider<SjProfileData>((ref) async {
  final books = await bookDao.selectNotDeleteBooks();
  return SjProfileData(
    booksRead: await readingTimeDao.selectTotalNumberOfBook(),
    favorites: books.where((b) => b.rating > 0).length,
    notes: await readingTimeDao.selectTotalNumberOfNotes(),
  );
});

/// 书架藏书数（用于空状态判定）。
final sjBookCountProvider = FutureProvider<int>((ref) async {
  final books = await bookDao.selectNotDeleteBooks();
  return books.length;
});

// ==================== 内部工具 ====================

int _sum(List<int> values) => values.fold<int>(0, (a, b) => a + b);

/// 逐日阅读秒数（键已归一到当天零点）。
Future<Map<DateTime, int>> _readingSecondsByDay() async {
  final raw = await readingTimeDao.selectAllReadingTimeGroupByDay();
  final perDay = <DateTime, int>{};
  raw.forEach((key, value) {
    final day = DateTime(key.year, key.month, key.day);
    perDay[day] = (perDay[day] ?? 0) + value;
  });
  return perDay;
}

/// 有阅读记录的日期（升序）。
List<DateTime> _activeDays(Map<DateTime, int> perDay) =>
    perDay.entries.where((e) => e.value > 0).map((e) => e.key).toList()..sort();

/// 当前 / 最长连续阅读天数。
({int current, int longest}) _streak(List<DateTime> days, DateTime now) {
  if (days.isEmpty) return (current: 0, longest: 0);

  var longest = 1;
  var run = 1;
  for (var i = 1; i < days.length; i++) {
    run = days[i].difference(days[i - 1]).inDays == 1 ? run + 1 : 1;
    longest = math.max(longest, run);
  }

  final today = DateTime(now.year, now.month, now.day);
  final last = days.last;
  if (today.difference(last).inDays > 1) {
    return (current: 0, longest: longest);
  }

  var current = 1;
  var expected = last.subtract(const Duration(days: 1));
  for (var i = days.length - 2; i >= 0; i--) {
    if (days[i].isAtSameMomentAs(expected)) {
      current++;
      expected = expected.subtract(const Duration(days: 1));
    } else if (days[i].isBefore(expected)) {
      break;
    }
  }
  return (current: current, longest: longest);
}

int _heatLevel(int seconds) {
  if (seconds <= 0) return 0;
  for (var i = 0; i < _heatThresholds.length; i++) {
    if (seconds < _heatThresholds[i]) return i + 1;
  }
  return 4;
}

/// 最近 4 周（周一 → 周日）的阅读热力等级。
List<List<int>> _buildHeatmap(Map<DateTime, int> perDay, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final start = thisMonday.subtract(const Duration(days: 21));
  return List<List<int>>.generate(4, (w) {
    return List<int>.generate(7, (d) {
      final day = start.add(Duration(days: w * 7 + d));
      return _heatLevel(perDay[day] ?? 0);
    });
  });
}
