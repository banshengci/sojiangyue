import 'package:songjiang_reader/enums/statistics_dashboard_tile_type.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/books_total_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/completion_progress_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/library_totals_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/notes_total_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/period_summary_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/random_highlight_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/reading_days_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/reading_duration_trend_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/reading_streak_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/continue_reading_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/top_book_tile.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/tiles/total_time_tile.dart';

// 兼容：原先从本文件取 `StatisticsDashboardTileType` /
// `defaultStatisticsDashboardTiles` 的使用方（共 17 处）无需改动。
//
// 注意：Dart 要求所有指令（import/export/part）出现在任何声明之前，
// 因此这里必须放在 `dashboardTileRegistry` 之前，不能挪到文件末尾。
export 'package:songjiang_reader/enums/statistics_dashboard_tile_type.dart';

final Map<StatisticsDashboardTileType, StatisticsDashboardTileBase>
    dashboardTileRegistry = {
  StatisticsDashboardTileType.totalTime: const TotalTimeTile(),
  StatisticsDashboardTileType.libraryTotals: const LibraryTotalsTile(),
  StatisticsDashboardTileType.periodSummary: const PeriodSummaryTile(),
  StatisticsDashboardTileType.booksTotal: const BooksTotalTile(),
  StatisticsDashboardTileType.readingDaysTotal: const ReadingDaysTile(),
  StatisticsDashboardTileType.notesTotal: const NotesTotalTile(),
  StatisticsDashboardTileType.readingStreak: const ReadingStreakTile(),
  StatisticsDashboardTileType.randomHighlight: const RandomHighlightTile(),
  StatisticsDashboardTileType.readingDurationLast7: ReadingDurationLast7Tile(),
  StatisticsDashboardTileType.readingDurationLast30:
      ReadingDurationLast30Tile(),
  StatisticsDashboardTileType.completionProgress:
      const CompletionProgressTile(),
  StatisticsDashboardTileType.topBook: const TopBookTile(),
  StatisticsDashboardTileType.continueReading: const ContinueReadingTile(),
};
