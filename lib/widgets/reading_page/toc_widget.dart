import 'package:songjiang_reader/design/songjiang/reader/sj_reader_controls.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';
import 'package:songjiang_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:songjiang_reader/widgets/reading_page/widgets/bookmark.dart';
import 'package:flutter/material.dart';

class TocWidget extends StatefulWidget {
  const TocWidget({
    super.key,
    required this.epubPlayerKey,
    required this.hideAppBarAndBottomBar,
    required this.closeDrawer,
    this.bookTitle,
    this.palette,
  });

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function hideAppBarAndBottomBar;
  final VoidCallback closeDrawer;

  /// 面板顶部显示的书名（微信读书目录会把书名放在列表上方）。
  final String? bookTitle;

  /// 阅读页调色板；为空时回退到 Material 主题色。
  final SjReaderPalette? palette;

  @override
  State<TocWidget> createState() => _TocWidgetState();
}

class _TocWidgetState extends State<TocWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ??
        SjReaderPalette.fromTheme(
          Theme.of(context).colorScheme.surface,
          Theme.of(context).colorScheme.onSurface,
        );

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.bookTitle ?? L10n.of(context).readingContents,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SjReaderText.chapterTitle(palette.foreground)
                    .copyWith(fontSize: 20),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 132,
              child: SjSegmented(
                palette: palette,
                labels: <String>[
                  L10n.of(context).readingContents,
                  L10n.of(context).readingBookmark,
                ],
                index: _tabController.index,
                onChanged: (int index) {
                  _tabController.animateTo(index);
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: <Widget>[
              buildBookToc(),
              buildBookmarkList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildBookmarkList() {
    return BookmarkWidget(
      epubPlayerKey: widget.epubPlayerKey,
      onNavigate: () {
        widget.hideAppBarAndBottomBar(false);
        widget.closeDrawer();
      },
    );
  }

  BookToc buildBookToc() {
    return BookToc(
      epubPlayerKey: widget.epubPlayerKey,
      hideAppBarAndBottomBar: widget.hideAppBarAndBottomBar,
      closeDrawer: widget.closeDrawer,
      palette: widget.palette,
    );
  }
}
