import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 收藏页书卡：顶部色块封面（书名 + 作者）+ 底部元信息。
///
/// 封面底色取品牌色（松墨 / 松绿 / 江青 / 砂朱），文字为纸白。
class SjBookCoverCard extends StatelessWidget {
  const SjBookCoverCard({
    super.key,
    required this.title,
    required this.author,
    required this.coverColor,
    required this.meta,
    this.coverHeight = 104,
    this.onTap,
  });

  final String title;
  final String author;
  final Color coverColor;
  final String meta;
  final double coverHeight;
  final VoidCallback? onTap;

  /// 封面上的前景色（纸白）。
  static const Color _onCover = Color(0xFFF5F0E8);

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(SjSizes.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SjSizes.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SjSizes.radiusCard),
            border: Border.all(color: c.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: coverHeight,
                color: coverColor,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SjText.coverTitle(_onCover),
                    ),
                    const SizedBox(height: SjSpace.xs),
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SjText.coverSubtitle(_onCover.withAlpha(210)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Text(meta, style: SjText.meta(c.inkSoft)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
