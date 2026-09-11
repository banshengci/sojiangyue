import 'package:flutter/material.dart';

import '../data/sj_view_models.dart';
import '../sj_book_card.dart';
import '../sj_icon.dart';
import '../sj_list_items.dart';
import '../sj_tokens.dart';

/// 「收藏」页视觉（对应画板 07 · 页面二）。
///
/// 真实数据：书架中用户评分 > 0 的书（见 [SjFavoriteBook]）。
class SjFavoritesPage extends StatelessWidget {
  const SjFavoritesPage({super.key, required this.books});

  final List<SjFavoriteBook> books;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(SjSpace.page, 12, SjSpace.page, 120),
      children: [
        Row(
          children: [
            Expanded(child: Text('我的收藏', style: SjText.pageTitle(c.ink))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: c.pine,
                borderRadius: BorderRadius.circular(SjSizes.radiusPill),
              ),
              child: Text(
                '${books.length}',
                style: TextStyle(
                  fontFamily: SjText.serif,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.onPine,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: SjSpace.xl),
        if (books.isEmpty)
          _emptyHint(c)
        else
          for (var row = 0; row < books.length; row += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: SjSpace.l),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _card(c, books[row])),
                  const SizedBox(width: SjSpace.l),
                  Expanded(
                    child: row + 1 < books.length
                        ? _card(c, books[row + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// 由书名稳定推导封面配色（0–3 → 松绿 / 松墨 / 江青 / 砂朱）。
  Color _coverColor(SjColors c, int seed) => switch (seed) {
        0 => c.pine,
        1 => c.ink,
        2 => c.river,
        _ => c.clay,
      };

  Widget _card(SjColors c, SjFavoriteBook book) {
    return SjBookCoverCard(
      title: book.title,
      author: book.author,
      meta: book.progressLabel,
      coverColor: _coverColor(c, book.coverSeed),
      onTap: () {},
    );
  }

  Widget _emptyHint(SjColors c) {
    return SjCard(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          const SjIllustrationView(SjIllustration.noResults, width: 160),
          const SizedBox(height: SjSpace.l),
          Text('还没有收藏', style: SjText.cardTitle(c.ink)),
          const SizedBox(height: 6),
          Text(
            '在书籍详情里打分后，会自动出现在这里',
            textAlign: TextAlign.center,
            style: SjText.meta(c.inkSoft),
          ),
        ],
      ),
    );
  }
}
