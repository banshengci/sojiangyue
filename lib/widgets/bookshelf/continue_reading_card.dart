import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/service/book.dart';
import 'package:songjiang_reader/widgets/bookshelf/book_cover.dart';

/// 书架顶部的「继续阅读」大卡。
///
/// 设计意图：书架首屏原来是一整片等高书卡网格，用户要自己找「上次读到哪」。
/// 这张卡把「最近在读的那一本」提到最上面，给一个大按钮，一步回到上次位置。
///
/// 只在有「读到一半」的书时出现（0 < 进度 < 1）；否则不占位。
class ContinueReadingCard extends ConsumerWidget {
  const ContinueReadingCard({
    super.key,
    required this.book,
    this.heroTag,
  });

  final Book book;
  final String? heroTag;

  /// 从书架的分组数据里挑出「最该继续读」的那本。
  ///
  /// 规则：进度在 (0, 1) 之间，按 `updateTime` 取最新的一本。
  /// （Book 没有独立的 lastReadTime 列，`updateTime` 在保存阅读进度时会被刷新，
  /// 因此可作为「最近阅读」的代理。）
  static Book? pick(List<List<Book>> groups) {
    Book? best;
    for (final group in groups) {
      for (final b in group) {
        if (b.isDeleted) continue;
        final p = b.readingPercentage;
        if (p <= 0 || p >= 1) continue;
        if (best == null || b.updateTime.isAfter(best.updateTime)) {
          best = b;
        }
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SjColors.of(context);
    final percent = (book.readingPercentage * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SjSpace.page,
        SjSpace.xs,
        SjSpace.page,
        SjSpace.s,
      ),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(SjSizes.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(SjSizes.radiusCard),
          onTap: () => pushToReadingPage(ref, context, book, heroTag: heroTag),
          child: Container(
            padding: const EdgeInsets.all(SjSpace.s),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SjSizes.radiusCard),
              border: Border.all(color: c.cardBorder),
              boxShadow: SjShadow.card,
            ),
            child: Row(
              children: [
                BookCover(
                  book: book,
                  width: 48,
                  height: 64,
                  radius: SjSizes.radiusCover,
                ),
                const SizedBox(width: SjSpace.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '继续阅读',
                        style: SjText.caption(c.inkSoft)
                            .copyWith(letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        book.title,
                        style: SjText.cardTitle(c.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        book.author.isEmpty ? '读到 $percent%' : book.author,
                        style: SjText.caption(c.inkSoft),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SjSpace.xs),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(SjSizes.radiusPill),
                              child: LinearProgressIndicator(
                                value: book.readingPercentage.clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor: c.divider,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(c.pine),
                              ),
                            ),
                          ),
                          const SizedBox(width: SjSpace.xs),
                          Text('$percent%', style: SjText.caption(c.inkSoft)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SjSpace.s),
                // 44×44 最小热区由外层 InkWell 的整卡承担；这里只做视觉按钮。
                Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: SjSpace.m),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.pine,
                    borderRadius: BorderRadius.circular(SjSizes.radiusPill),
                  ),
                  child: Text(
                    '继续',
                    style: SjText.chip(c.onPine, selected: true),
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
