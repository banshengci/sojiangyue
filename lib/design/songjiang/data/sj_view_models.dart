/// 松江阅页面 · 视图模型
///
/// 把应用真实数据（阅读记录 / 书架 / 评分 / 笔记）映射为页面可直接渲染的模型，
/// 页面本身保持「纯展示」，只依赖这些模型。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 秒 → 紧凑时长文本（如 `18h 42m`、`42m`）。
String sjFormatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '${seconds}s';
}

/// 「数据统计」页数据。
@immutable
class SjStatisticsData {
  const SjStatisticsData({
    required this.monthSeconds,
    required this.prevMonthSeconds,
    required this.currentStreak,
    required this.finishedBooks,
    required this.dailyAverageMinutes,
    required this.heatLevels,
    required this.weeklySeconds,
  });

  /// 本月阅读秒数（区间 = 当前自然月，逐日求和）。
  final int monthSeconds;

  /// 上月阅读秒数（用于环比）。
  final int prevMonthSeconds;

  /// 当前连续阅读天数。
  final int currentStreak;

  /// 累计读完的书数（readingPercentage ≥ 0.98）。
  final int finishedBooks;

  /// 日均阅读分钟（总时长 ÷ 有阅读记录的天数）。
  final int dailyAverageMinutes;

  /// 阅读热力：4 行（周）× 7 列（周一 → 周日），等级 0–4。
  final List<List<int>> heatLevels;

  /// 本周 7 天阅读秒数（周一 → 周日）。
  final List<int> weeklySeconds;

  /// 本周星期标签。
  static const List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 是否有任何阅读记录。
  bool get hasData =>
      monthSeconds > 0 || weeklySeconds.any((s) => s > 0);

  /// 本月时长文本。
  String get monthDurationLabel => sjFormatDuration(monthSeconds);

  /// 环比文本；上月无数据时返回 null。
  String? get monthDeltaLabel {
    if (prevMonthSeconds <= 0) return null;
    final pct = ((monthSeconds - prevMonthSeconds) / prevMonthSeconds * 100)
        .round();
    final sign = pct >= 0 ? '+' : '';
    return '较上月 $sign$pct%';
  }

  /// 归一化柱值（0–1）。
  List<double> get weeklyNormalized {
    if (weeklySeconds.isEmpty) return const [];
    final peak = weeklySeconds.reduce(math.max);
    if (peak <= 0) return List<double>.filled(weeklySeconds.length, 0);
    return weeklySeconds.map((s) => s / peak).toList();
  }

  /// 本周峰值所在索引；全为 0 时返回 null。
  int? get weeklyPeakIndex {
    if (weeklySeconds.isEmpty) return null;
    var index = 0;
    for (var i = 1; i < weeklySeconds.length; i++) {
      if (weeklySeconds[i] > weeklySeconds[index]) index = i;
    }
    return weeklySeconds[index] > 0 ? index : null;
  }

  static const SjStatisticsData empty = SjStatisticsData(
    monthSeconds: 0,
    prevMonthSeconds: 0,
    currentStreak: 0,
    finishedBooks: 0,
    dailyAverageMinutes: 0,
    heatLevels: [
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
    ],
    weeklySeconds: [0, 0, 0, 0, 0, 0, 0],
  );
}

/// 单个成就。
@immutable
class SjAchievementItem {
  const SjAchievementItem({
    required this.glyph,
    required this.label,
    required this.requirement,
    required this.unlocked,
  });

  /// 单字篆意图形。
  final String glyph;

  /// 成就名。
  final String label;

  /// 达成条件（真实阈值）。
  final String requirement;

  /// 是否已解锁（由真实数据判定）。
  final bool unlocked;
}

/// 「成就」页数据。
@immutable
class SjAchievementsData {
  const SjAchievementsData({required this.items});

  final List<SjAchievementItem> items;

  int get total => items.length;

  int get unlockedCount => items.where((i) => i.unlocked).length;

  /// 解锁进度（0–1）。
  double get progress => total == 0 ? 0 : unlockedCount / total;

  static const SjAchievementsData empty = SjAchievementsData(items: []);
}

/// 收藏卡数据（来源：书架中用户评分 > 0 的书）。
@immutable
class SjFavoriteBook {
  const SjFavoriteBook({
    required this.id,
    required this.title,
    required this.author,
    required this.progress,
  });

  final int id;
  final String title;
  final String author;

  /// 阅读进度（0–1）。
  final double progress;

  String get progressLabel => '已读 ${(progress * 100).round()}%';

  /// 由书名稳定推导的封面配色种子（0–3）。
  int get coverSeed => title.codeUnits.fold<int>(0, (a, b) => a + b) % 4;
}

/// 「我的」页数据。
@immutable
class SjProfileData {
  const SjProfileData({
    required this.booksRead,
    required this.favorites,
    required this.notes,
  });

  /// 已读（有过阅读记录的书数）。
  final int booksRead;

  /// 收藏（评分 > 0 的书数）。
  final int favorites;

  /// 笔记总数。
  final int notes;

  String get subtitle => '已读 $booksRead 本 · 笔记 $notes 条';

  static const SjProfileData empty =
      SjProfileData(booksRead: 0, favorites: 0, notes: 0);
}

/// 预览容器所需的一整组数据。
///
/// 由「数据接入层」（真实数据）或预览夹具（`SjGalleryData.sample`）提供，
/// 使 [SjGallery] 保持纯展示、不依赖任何数据源。
@immutable
class SjGalleryData {
  const SjGalleryData({
    required this.statistics,
    required this.achievements,
    required this.favorites,
    required this.profile,
    required this.bookCount,
  });

  final SjStatisticsData statistics;
  final SjAchievementsData achievements;
  final List<SjFavoriteBook> favorites;
  final SjProfileData profile;
  final int bookCount;

  /// 预览夹具（设计稿示例值，用于独立预览 / 测试）。
  static const SjGalleryData sample = SjGalleryData(
    statistics: SjStatisticsData(
      monthSeconds: 67320, // 18h 42m
      prevMonthSeconds: 60000, // → 较上月 +12%
      currentStreak: 12,
      finishedBooks: 24,
      dailyAverageMinutes: 52,
      heatLevels: [
        [3, 4, 2, 3, 0, 1, 2],
        [4, 4, 3, 4, 2, 2, 3],
        [2, 3, 4, 4, 3, 0, 1],
        [1, 2, 3, 2, 1, 0, 0],
      ],
      weeklySeconds: [1200, 1800, 900, 2000, 1500, 600, 2100],
    ),
    achievements: SjAchievementsData(
      items: [
        SjAchievementItem(
          glyph: '读',
          label: '初读',
          requirement: '读完第一本',
          unlocked: true,
        ),
        SjAchievementItem(
          glyph: '晓',
          label: '破晓',
          requirement: '连续阅读 7 天',
          unlocked: true,
        ),
        SjAchievementItem(
          glyph: '夜',
          label: '夜读者',
          requirement: '夜间阅读 20 次',
          unlocked: true,
        ),
        SjAchievementItem(
          glyph: '游',
          label: '书海漫游',
          requirement: '读完 10 本',
          unlocked: false,
        ),
        SjAchievementItem(
          glyph: '记',
          label: '笔记达人',
          requirement: '写满 50 条笔记',
          unlocked: false,
        ),
        SjAchievementItem(
          glyph: '长',
          label: '长读者',
          requirement: '单日阅读 3 小时',
          unlocked: false,
        ),
      ],
    ),
    favorites: [
      SjFavoriteBook(id: 1, title: '长恨歌', author: '白居易', progress: 0.62),
      SjFavoriteBook(id: 2, title: '红楼梦', author: '曹雪芹', progress: 0.88),
      SjFavoriteBook(id: 3, title: '三体', author: '刘慈欣', progress: 0.41),
      SjFavoriteBook(id: 4, title: '诗经', author: '佚名', progress: 1.0),
    ],
    profile: SjProfileData(booksRead: 24, favorites: 12, notes: 38),
    bookCount: 0,
  );
}
