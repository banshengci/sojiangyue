import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:songjiang_reader/dao/reading_time.dart';

part 'daily_reading_goal.g.dart';

/// 今日阅读目标进度：已读秒数 / 目标是否开启。
@riverpod
class DailyReadingGoal extends _$DailyReadingGoal {
  @override
  Future<DailyReadingGoalState> build() async {
    return _load();
  }

  Future<DailyReadingGoalState> _load() async {
    final seconds = await readingTimeDao.selectTodayReadingSeconds();
    return DailyReadingGoalState(secondsToday: seconds);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncData(await _load());
  }
}

class DailyReadingGoalState {
  const DailyReadingGoalState({required this.secondsToday});

  final int secondsToday;
}
