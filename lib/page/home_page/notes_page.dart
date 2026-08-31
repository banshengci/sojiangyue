import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:songjiang_reader/page/book_notes_page.dart';
import 'package:songjiang_reader/providers/notes_page_current_book.dart';
import 'package:songjiang_reader/providers/notes_statistics.dart';
import 'package:songjiang_reader/utils/date/convert_seconds.dart';
import 'package:songjiang_reader/widgets/bookshelf/book_cover.dart';
import 'package:songjiang_reader/widgets/common/container/filled_container.dart';
import 'package:songjiang_reader/widgets/highlight_digit.dart';
import 'package:songjiang_reader/widgets/tips/notes_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 600) {
            return Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      notesStatistic(),
                      bookNotesList(false),
                    ],
                  ),
                ),
                VerticalDivider(
                  thickness: 1,
                  width: 1,
                  color: SongJiangColors.pine.withAlpha(120),
                ),
                const Expanded(
                  flex: 2,
                  child: NotesDetail(),
                ),
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                notesStatistic(),
                bookNotesList(true),
              ],
            );
          }
        },
      ),
    );
  }

  Widget notesStatistic() {
    final notesStats = ref.watch(notesStatisticsProvider);

    TextStyle digitStyle = TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: SongJiangColors.pine,
    );
    TextStyle textStyle =
        const TextStyle(fontSize: 18, fontFamily: 'SourceHanSerif');

    return notesStats.when(
      data: (data) {
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              highlightDigit(
                context,
                L10n.of(context).notesNotesAcross(data['numberOfNotes']!),
                textStyle,
                digitStyle,
              ),
              highlightDigit(
                context,
                L10n.of(context).notesBooks(data['numberOfBooks']!),
                textStyle,
                digitStyle,
              ),
            ]),
          ),
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }

  Widget bookNotesList(bool isMobile) {
    final bookIdAndNotes = ref.watch(bookIdAndNotesProvider);

    return bookIdAndNotes.when(
      data: (data) {
        return data.isEmpty
            ? const Expanded(child: Center(child: NotesTips()))
            : Expanded(
                child: ListView.builder(
                    padding: EdgeInsets.only(bottom: 80),
                    controller: _scrollController,
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      return bookNotesItem(
                        book: data[index]['book']!,
                        numberOfNotes: data[index]['numberOfNotes']!,
                        isMobile: isMobile,
                        readingTime: data[index]['readingTime']!,
                      );
                    }),
              );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('Error: $error'),
    );
  }

  Widget bookNotesItem({
    required Book book,
    required int numberOfNotes,
    required bool isMobile,
    required int readingTime,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandColor = isDark ? SongJiangColors.pineLight : SongJiangColors.pine;
    TextStyle digitStyle = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: brandColor,
    );
    TextStyle textStyle = const TextStyle(
      fontSize: 20,
    );
    TextStyle titleStyle = const TextStyle(
      overflow: TextOverflow.ellipsis,
      fontSize: 18,
      fontFamily: 'SourceHanSerif',
      fontWeight: FontWeight.bold,
    );
    TextStyle readingTimeStyle = TextStyle(
      fontSize: 14,
      color: brandColor.withAlpha(170),
    );
    return GestureDetector(
      onTap: () {
        if (isMobile) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => BookNotesPage(
                      book: book,
                      numberOfNotes: numberOfNotes,
                      isMobile: true,
                    )),
          );
        } else {
          ref
              .read(notesPageCurrentBookProvider.notifier)
              .setData(book, numberOfNotes);
        }
      },
      child: FilledContainer(
        margin: const EdgeInsets.only(top: 8, left: 15, right: 15),
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  highlightDigit(
                    context,
                    L10n.of(context).notesNotes(numberOfNotes),
                    textStyle,
                    digitStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(book.title, style: titleStyle),
                  const SizedBox(height: 18),
                  // Reading time
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: 16,
                            color: brandColor.withAlpha(190)),
                        const SizedBox(width: 4),
                        Text(
                          convertSeconds(readingTime),
                          style: readingTimeStyle,
                        ),
                        Text(" | ", style: readingTimeStyle),
                        Icon(Icons.bar_chart, size: 16,
                            color: brandColor.withAlpha(190)),
                        const SizedBox(width: 4),
                        Text(
                          '${(book.readingPercentage * 100).toStringAsFixed(1)}%',
                          style: readingTimeStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Expanded(child: SizedBox()),
            Hero(
              tag: isMobile
                  ? book.coverFullPath
                  : '${book.coverFullPath}notMobile',
              child: BookCover(
                book: book,
                height: 130,
                width: 90,
                radius: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotesDetail extends ConsumerWidget {
  const NotesDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(notesPageCurrentBookProvider).when(
          data: (current) {
            return BookNotesPage(
                isMobile: false,
                book: current.book,
                numberOfNotes: current.numberOfNotes);
          },
          loading: () => const CircularProgressIndicator(),
          error: (error, stack) => NotesTips(),
        );
  }
}
