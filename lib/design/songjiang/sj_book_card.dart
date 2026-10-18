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

  /// 封面上的前景色。
  ///
  /// 按底色亮度动态选深/浅，避免「浅底浅字」。
  /// 但注意：**动态选择救不了中间调**——相对亮度落在 0.15–0.23 的底色上，
  /// 白字与深字都到不了 4.5:1（L=0.19 时两者都是 3.86）。
  /// 所以调用方应传深色调（见 [SjCoverColors]），这里只是兜底。
  Color get _onCover =>
      coverColor.computeLuminance() > 0.179
          ? const Color(0xFF10211B)
          : SjCoverColors.onCover;

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
                      // 不再 withAlpha(210)：半透明会把 13px 的副标题压到 4.5 以下。
                      // 层级差异交给字号（13 vs 25）去表达，不靠降低不透明度。
                      style: SjText.coverSubtitle(_onCover),
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
