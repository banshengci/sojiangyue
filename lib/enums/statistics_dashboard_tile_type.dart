/// 统计看板磁贴类型与默认顺序。
///
/// 从 `lib/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart`
/// 下沉到 `lib/enums/`。
/// 动机：`lib/config/shared_preference_provider.dart` 需要读写该类型与默认顺序，
/// 而 config 反向依赖 widgets 会形成 config <-> widgets 环。
/// 下沉后 config 只依赖 enums；registry 原样 re-export，其余使用方无需改动。
/// 行为无变化：枚举值、顺序与默认列表内容逐字保持。
enum StatisticsDashboardTileType {
  totalTime,
  libraryTotals,
  periodSummary,
  booksTotal,
  readingDaysTotal,
  notesTotal,
  readingStreak,
  randomHighlight,
  readingDurationLast7,
  readingDurationLast30,
  completionProgress,
  topBook,
  continueReading,
}

/// Default order for dashboard tiles when the user has not customized the layout.
const List<StatisticsDashboardTileType> defaultStatisticsDashboardTiles = [
  StatisticsDashboardTileType.readingDaysTotal,
  StatisticsDashboardTileType.booksTotal,
  StatisticsDashboardTileType.periodSummary,
  StatisticsDashboardTileType.topBook,
  StatisticsDashboardTileType.readingStreak,
  StatisticsDashboardTileType.randomHighlight,
  StatisticsDashboardTileType.completionProgress,
  StatisticsDashboardTileType.readingDurationLast7,
  StatisticsDashboardTileType.readingDurationLast30,
];
