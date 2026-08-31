import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:flutter/material.dart';

class BookshelfTips extends StatelessWidget {
  const BookshelfTips({super.key});

  final TextStyle textStyleBig = const TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );
  final TextStyle textStyle = const TextStyle(
    fontSize: 15,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final pine = SongJiangColors.pine;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 品牌化空状态：松绿柔光圆盘里放一本摊开的书，
          // 取代原来的灰色颜文字 `(´。＿。｀)`
          Container(
            width: 136,
            height: 136,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pine.withAlpha(isDark ? 26 : 18),
            ),
            child: Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pine.withAlpha(isDark ? 34 : 24),
                  border: Border.all(
                    color: pine.withAlpha(isDark ? 60 : 45),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 46,
                  color: pine.withAlpha(isDark ? 190 : 210),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            L10n.of(context).bookshelfTips_1,
            style: textStyleBig.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Text(
            L10n.of(context).bookshelfTips_2,
            style: textStyle.copyWith(
              color: scheme.onSurface.withAlpha(170),
            ),
          ),
        ],
      ),
    );
  }
}
