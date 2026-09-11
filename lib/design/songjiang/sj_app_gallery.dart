import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/sj_data_providers.dart';
import 'data/sj_view_models.dart';
import 'sj_gallery.dart';
import 'sj_tokens.dart';

/// 真实数据版页面容器。
///
/// 把应用真实阅读记录（tb_reading_time / tb_books / tb_notes）接入 [SjGallery]。
/// 这是「接真实数据」的接线点；[SjGallery] 本身保持纯展示。
///
/// 应用内用法：
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute(builder: (_) => const SjAppGallery()),
/// );
/// ```
class SjAppGallery extends ConsumerWidget {
  const SjAppGallery({super.key, this.onImport});

  /// 导入入口（书架为空时展示）。
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SjColors.of(context);

    final statistics = ref.watch(sjStatisticsProvider);
    final achievements = ref.watch(sjAchievementsProvider);
    final favorites = ref.watch(sjFavoritesProvider);
    final profile = ref.watch(sjProfileProvider);
    final bookCount = ref.watch(sjBookCountProvider);

    final error = statistics.error ??
        achievements.error ??
        favorites.error ??
        profile.error ??
        bookCount.error;
    if (error != null) {
      return Scaffold(
        backgroundColor: c.paper,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(SjSpace.xl),
            child: Text(
              '数据加载失败\n$error',
              textAlign: TextAlign.center,
              style: SjText.meta(c.inkSoft),
            ),
          ),
        ),
      );
    }

    final loading = statistics.isLoading ||
        achievements.isLoading ||
        favorites.isLoading ||
        profile.isLoading ||
        bookCount.isLoading;
    if (loading) {
      return Scaffold(
        backgroundColor: c.paper,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return SjGallery(
      onImport: onImport,
      data: SjGalleryData(
        statistics: statistics.value ?? SjStatisticsData.empty,
        achievements: achievements.value ?? SjAchievementsData.empty,
        favorites: favorites.value ?? const <SjFavoriteBook>[],
        profile: profile.value ?? SjProfileData.empty,
        bookCount: bookCount.value ?? 0,
      ),
    );
  }
}
