import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/enums/book_sync_status.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/providers/bookshelf_selection.dart';
import 'package:songjiang_reader/providers/sync_status.dart';
import 'package:songjiang_reader/service/book.dart';
import 'package:songjiang_reader/theme/songjiang_icons.dart';
import 'package:songjiang_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:songjiang_reader/widgets/bookshelf/book_cover.dart';
import 'package:songjiang_reader/widgets/bookshelf/book_sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookItem extends ConsumerWidget {
  const BookItem({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(bookshelfSelectionProvider);
    final selecting = selection.isNotEmpty;
    final selected = selection.contains(book.id);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Future<void> handleLongPress() async {
      if (selecting) {
        ref.read(bookshelfSelectionProvider.notifier).toggle(book.id);
        return;
      }
      showModalBottomSheet(
          context: context,
          builder: (BuildContext context) {
            return BookBottomSheet(book: book);
          });
    }

    BookSyncStatusEnum bookSyncStatus =
        ref.watch(syncStatusProvider).whenOrNull(data: (data) {
              if (data.downloading.contains(book.id)) {
                return BookSyncStatusEnum.downloading;
              } else if (data.uploading.contains(book.id)) {
                return BookSyncStatusEnum.uploading;
              } else if (data.localOnly.contains(book.id)) {
                return BookSyncStatusEnum.localOnly;
              } else if (data.remoteOnly.contains(book.id)) {
                return BookSyncStatusEnum.remoteOnly;
              } else if (data.both.contains(book.id)) {
                return BookSyncStatusEnum.both;
              } else if (data.nonExistent.contains(book.id)) {
                return BookSyncStatusEnum.nonExistent;
              } else {
                return BookSyncStatusEnum.checking;
              }
            }) ??
            BookSyncStatusEnum.checking;

    final seriesLabel = (book.seriesName != null &&
            book.seriesName!.isNotEmpty &&
            book.seriesIndex != null)
        ? '${book.seriesName} · #${book.seriesIndex}'
        : (book.seriesName != null && book.seriesName!.isNotEmpty)
            ? book.seriesName!
            : null;

    return GestureDetector(
      onTap: () {
        if (selecting) {
          ref.read(bookshelfSelectionProvider.notifier).toggle(book.id);
          return;
        }
        pushToReadingPage(ref, context, book);
      },
      onLongPress: handleLongPress,
      onSecondaryTap: handleLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: book.coverFullPath,
              child: AnimatedScale(
                scale: selected ? 0.97 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    if (!ThemePrefs.eInkMode)
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withAlpha(90)
                            : scheme.primary.withAlpha(selected ? 50 : 22),
                        spreadRadius: selected ? 1 : 0.5,
                        blurRadius: selected ? 14 : 8,
                        offset: const Offset(0, 3),
                      ),
                  ],
                  border: Border.all(
                    color: selected
                        ? scheme.primary
                        : SongJiangThemeHelper.hairline(isDark),
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      BookCover(book: book, radius: 0),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        top: selected ? 6 : -8,
                        right: selected ? 6 : -8,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: selected ? 1 : 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.primary.withAlpha(80),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Icon(
                              SongJiangIcons.check,
                              color: scheme.onPrimary,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: seriesLabel != null ? 66 : 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.25,
                    color: scheme.onSurface,
                  ),
                ),
                if (seriesLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    seriesLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: scheme.primary,
                    ),
                  ),
                ],
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (SyncPrefs.webdavStatus) ...[
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: BookSyncStatusIcon(
                          syncStatus: bookSyncStatus,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '${(book.readingPercentage * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                        color: book.readingPercentage > 0
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 书架细线边框色（避免在 widget 内重复写 alpha 逻辑）。
class SongJiangThemeHelper {
  static Color hairline(bool isDark) =>
      isDark ? Colors.white.withAlpha(28) : Colors.black.withAlpha(28);
}
