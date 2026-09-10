import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/providers/daily_reading_goal.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';

/// 书架顶部「今日阅读目标」进度条；目标为 0 时不显示。
class DailyGoalBanner extends ConsumerWidget {
  const DailyGoalBanner({super.key});

  String _formatMinutes(BuildContext context, int seconds) {
    final minutes = (seconds / 60).ceil();
    return L10n.of(context).commonMinutes(minutes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ReadingUiPrefs.dailyGoalMinutes;
    if (goal <= 0) return const SizedBox.shrink();

    final async = ref.watch(dailyReadingGoalProvider);
    final seconds = async.valueOrNull?.secondsToday ?? 0;
    final progress = (seconds / (goal * 60)).clamp(0.0, 1.0);
    final done = progress >= 1.0;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: scheme.primaryContainer.withAlpha(70),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => ref.read(dailyReadingGoalProvider.notifier).refresh(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  done ? Icons.emoji_events_outlined : Icons.flag_outlined,
                  size: 20,
                  color: done
                      ? SongJiangColors.pine
                      : scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        done
                            ? L10n.of(context).readingGoalDone
                            : L10n.of(context).readingGoalProgress(
                                _formatMinutes(context, seconds),
                                L10n.of(context).commonMinutes(goal),
                              ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: scheme.primary.withAlpha(40),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
