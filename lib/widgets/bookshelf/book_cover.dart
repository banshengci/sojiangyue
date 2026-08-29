import 'dart:io';

import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:flutter/material.dart';

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.height,
    this.width,
    this.radius,
  });

  final Book book;
  final double? height;
  final double? width;
  final double? radius;

  // Calculate text color based on background brightness
  Color _getContrastColor(Color backgroundColor) {
    final brightness = ThemeData.estimateBrightnessForColor(backgroundColor);
    return brightness == Brightness.dark ? Colors.white : Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    final double effectiveRadius = radius ?? 8;
    final BorderRadius borderRadius = BorderRadius.circular(effectiveRadius);
    final File file = File(book.coverFullPath);

    Widget child;

    if (file.existsSync()) {
      child = Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: FileImage(file),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      // Default cover with responsive text and icon
      child = LayoutBuilder(
        builder: (context, constraints) {
          final coverWidth = constraints.maxWidth;

          // Calculate responsive sizes based on width
          final titleFontSize = coverWidth * 0.12;
          final authorFontSize = coverWidth * 0.08;
          final iconSize = coverWidth * 0.8;
          final padding = coverWidth * 0.08;

          // 松江阅：用品牌色板（水墨 / 江南意象）取代 Material 彩虹色，
          // 同一本书稳定映射到同一色，书架整体调性统一。
          final palette = SongJiangColors.themePalette;
          final baseColor = palette[
              (book.title.hashCode & 0x7FFFFFFF) % palette.length];
          final backgroundColor = baseColor;
          final textColor = _getContrastColor(backgroundColor);

          final showTitle = Prefs().showBookTitleOnDefaultCover;
          final showAuthor = Prefs().showAuthorOnDefaultCover;

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(backgroundColor, Colors.white, 0.12)!,
                  backgroundColor,
                  Color.lerp(backgroundColor, Colors.black, 0.18)!,
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 书脊：左侧一条深色竖带，强化「书」的隐喻
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: coverWidth * 0.055,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                // 水印「阅」，与设置页品牌头图呼应
                Positioned(
                  right: -coverWidth * 0.12,
                  bottom: -coverWidth * 0.12,
                  child: Text(
                    '阅',
                    style: TextStyle(
                      fontSize: iconSize * 0.72,
                      fontWeight: FontWeight.w700,
                      color: textColor.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                // Text content (title at top, author at bottom)
                if (showTitle || showAuthor)
                  Padding(
                    padding: EdgeInsets.only(
                      left: padding + coverWidth * 0.055,
                      right: padding,
                      top: padding,
                      bottom: padding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title at top
                        if (showTitle)
                          Text(
                            book.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'SourceHanSerif',
                              color: textColor,
                              height: 1.25,
                            ),
                          ),
                        const Spacer(),
                        // 分隔细线，让书名与作者之间有呼吸
                        Container(
                          width: coverWidth * 0.22,
                          height: 1.2,
                          margin: EdgeInsets.only(bottom: padding * 0.5),
                          color: textColor.withValues(alpha: 0.45),
                        ),
                        // Author at bottom
                        if (showAuthor)
                          Text(
                            book.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: authorFontSize,
                              fontWeight: FontWeight.w300,
                              color: textColor.withValues(alpha: 0.9),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    final RoundedSuperellipseBorder borderShape = RoundedSuperellipseBorder(
      borderRadius: borderRadius,
      side: BorderSide(
        width: 0.6,
        color: SongJiangColors.pine.withValues(alpha: 0.35),
      ),
    );

    return SizedBox(
      height: height,
      width: width,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: borderShape,
        ),
        child: ClipRSuperellipse(
          borderRadius: borderRadius,
          child: child,
        ),
      ),
    );
  }
}
