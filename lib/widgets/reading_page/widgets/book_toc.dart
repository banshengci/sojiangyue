import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';
import 'package:songjiang_reader/models/search_result_model.dart';
import 'package:songjiang_reader/models/toc_item.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';
import 'package:songjiang_reader/providers/book_toc.dart';
import 'package:songjiang_reader/providers/toc_search.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:songjiang_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class BookToc extends ConsumerStatefulWidget {
  const BookToc({
    super.key,
    required this.epubPlayerKey,
    required this.hideAppBarAndBottomBar,
    required this.closeDrawer,
    this.palette,
  });

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function hideAppBarAndBottomBar;
  final VoidCallback closeDrawer;

  /// 阅读页调色板；为空时回退到 Material 主题色。
  final SjReaderPalette? palette;

  @override
  ConsumerState<BookToc> createState() => _BookTocState();
}

class _BookTocState extends ConsumerState<BookToc> {
  final TextEditingController searchBarController = TextEditingController();
  final ScrollController searchResultsScrollController = ScrollController();
  late List<TocItem> tocItems;
  List<_VisibleTocEntry> _visibleItems = const [];
  final Set<String> _expandedItemKeys = {};
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  String? _lastAutoScrolledHref;
  String? _pendingScrollKey;
  bool _pendingScrollAnimated = false;
  bool _hasRestoredScrollPosition = false;

  /// 阅读页调色板（纸张 + 字色派生），面板内所有控件共用。
  SjReaderPalette get _palette =>
      widget.palette ??
      SjReaderPalette.fromTheme(
        Theme.of(context).colorScheme.surface,
        Theme.of(context).colorScheme.onSurface,
      );

  @override
  void initState() {
    super.initState();
    searchBarController.text = ref.read(tocSearchProvider).query ?? '';
    // Add listener to save scroll position
    searchResultsScrollController.addListener(_saveScrollPosition);
  }

  void _saveScrollPosition() {
    if (searchResultsScrollController.hasClients) {
      ref.read(tocSearchProvider.notifier).updateScrollOffset(
            searchResultsScrollController.offset,
          );
    }
  }

  @override
  void dispose() {
    searchBarController.dispose();
    searchResultsScrollController.dispose();
    super.dispose();
  }

  String _keyForItem(TocItem item) => '${item.id}_${item.href}';

  List<TocItem>? _findPath(List<TocItem> items, String href) {
    for (final item in items) {
      if (item.href == href) {
        return [item];
      }
      final nested = _findPath(item.subitems, href);
      if (nested != null) {
        return [item, ...nested];
      }
    }
    return null;
  }

  void _ensureItemVisible(TocItem item, {bool animated = false}) {
    if (!mounted) {
      return;
    }
    final path = _findPath(tocItems, item.href);
    if (path == null) {
      return;
    }

    final keysToExpand = <String>{};
    for (final ancestor in path) {
      if (ancestor.subitems.isNotEmpty) {
        final key = _keyForItem(ancestor);
        if (!_expandedItemKeys.contains(key)) {
          keysToExpand.add(key);
        }
      }
    }

    void scheduleScroll() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final key = _keyForItem(item);
        if (!_itemScrollController.isAttached) {
          _pendingScrollKey = key;
          _pendingScrollAnimated = animated;
          return;
        }
        final index = _visibleItems.indexWhere((entry) => entry.key == key);
        if (index == -1) {
          _pendingScrollKey = key;
          _pendingScrollAnimated = animated;
          return;
        }
        _pendingScrollKey = null;
        _pendingScrollAnimated = false;
        final duration = animated
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 1);
        _itemScrollController.scrollTo(
          index: index,
          duration: duration,
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      });
    }

    if (keysToExpand.isNotEmpty) {
      setState(() {
        _expandedItemKeys.addAll(keysToExpand);
      });
    }
    scheduleScroll();
  }

  void _scrollToCurrent({bool animated = false}) {
    final currentHref = widget.epubPlayerKey.currentState?.chapterHref ?? '';
    if (currentHref.isEmpty) {
      return;
    }
    final path = _findPath(tocItems, currentHref);
    if (path == null || path.isEmpty) {
      return;
    }
    _ensureItemVisible(path.last, animated: animated);
  }

  void _toggleExpanded(TocItem item) {
    final key = _keyForItem(item);
    setState(() {
      if (_expandedItemKeys.contains(key)) {
        _expandedItemKeys.remove(key);
      } else {
        _expandedItemKeys.add(key);
      }
    });
  }

  void _pruneExpandedKeys(List<TocItem> items) {
    final validKeys = <String>{};

    void collect(List<TocItem> children) {
      for (final child in children) {
        final key = _keyForItem(child);
        validKeys.add(key);
        if (child.subitems.isNotEmpty) {
          collect(child.subitems);
        }
      }
    }

    collect(items);
    _expandedItemKeys.removeWhere((key) => !validKeys.contains(key));
  }

  List<_VisibleTocEntry> _buildVisibleItems(List<TocItem> items) {
    final entries = <_VisibleTocEntry>[];

    void visit(List<TocItem> nodes, int depth) {
      for (final node in nodes) {
        final key = _keyForItem(node);
        final isExpanded = _expandedItemKeys.contains(key);
        entries.add(
          _VisibleTocEntry(
            item: node,
            key: key,
            depth: depth,
            isExpanded: isExpanded,
          ),
        );
        if (node.subitems.isNotEmpty && isExpanded) {
          visit(node.subitems, depth + 1);
        }
      }
    }

    visit(items, 0);
    return entries;
  }

  void _fulfillPendingScrollIfPossible() {
    if (!mounted) {
      return;
    }
    final pendingKey = _pendingScrollKey;
    if (pendingKey == null) {
      return;
    }
    if (!_itemScrollController.isAttached) {
      return;
    }

    final index = _visibleItems.indexWhere((entry) => entry.key == pendingKey);
    if (index == -1) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_itemScrollController.isAttached) {
        return;
      }
      _pendingScrollKey = null;
      final duration = _pendingScrollAnimated
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 1);
      _pendingScrollAnimated = false;
      _itemScrollController.scrollTo(
        index: index,
        duration: duration,
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    tocItems = ref.watch(bookTocProvider);
    _pruneExpandedKeys(tocItems);
    _visibleItems = _buildVisibleItems(tocItems);
    _fulfillPendingScrollIfPossible();
    final tocSearchState = ref.watch(tocSearchProvider);
    final currentQuery = tocSearchState.query ?? '';
    if (searchBarController.text != currentQuery) {
      searchBarController.value = TextEditingValue(
        text: currentQuery,
        selection: TextSelection.collapsed(offset: currentQuery.length),
      );
    }
    final isSearchActive = tocSearchState.isActive;
    final searchResults = tocSearchState.results;
    final showSearchProgress = tocSearchState.isSearching;
    final progressValue = tocSearchState.progress <= 0.0
        ? null
        : tocSearchState.progress.clamp(0.0, 1.0);

    // Restore scroll position when search results are available (only once)
    if (isSearchActive &&
        searchResults.isNotEmpty &&
        !_hasRestoredScrollPosition &&
        tocSearchState.scrollOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && searchResultsScrollController.hasClients) {
          final targetOffset = tocSearchState.scrollOffset.clamp(
            0.0,
            searchResultsScrollController.position.maxScrollExtent,
          );
          searchResultsScrollController.jumpTo(targetOffset);
          _hasRestoredScrollPosition = true;
        }
      });
    }

    // Reset the flag when search becomes inactive
    if (!isSearchActive && _hasRestoredScrollPosition) {
      _hasRestoredScrollPosition = false;
    }

    final currentHref = widget.epubPlayerKey.currentState?.chapterHref ?? '';
    final currentPath = currentHref.isEmpty
        ? <TocItem>[]
        : (_findPath(tocItems, currentHref) ?? <TocItem>[]);

    if (!isSearchActive &&
        currentHref.isNotEmpty &&
        currentHref != _lastAutoScrolledHref &&
        currentPath.isNotEmpty) {
      _lastAutoScrolledHref = currentHref;
      final target = currentPath.last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _ensureItemVisible(target);
      });
    }

    final selectedKeys = currentPath.map(_keyForItem).toSet();
    final currentState = widget.epubPlayerKey.currentState;
    final currentProgress = currentState == null
        ? ''
        : '${currentState.chapterCurrentPage} / ${currentState.chapterTotalPages}';

    var locatingButton = IconButton(
      tooltip: '回到当前章节',
      icon: Icon(
        Icons.my_location_rounded,
        size: 19,
        color: _palette.subForeground,
      ),
      onPressed: () {
        _scrollToCurrent(animated: true);
      },
    );

    // 微信读书是「胶囊搜索框 + 定位按钮」，不再用 Material SearchBar
    final palette = _palette;
    var searchBox = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(SjReaderSize.pillRadius),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 17, color: palette.faint),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: searchBarController,
              cursorColor: palette.accent,
              style: TextStyle(fontSize: 13, color: palette.foreground),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '搜本书',
                hintStyle: TextStyle(fontSize: 13, color: palette.faint),
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) {
                  searchBarController.clear();
                  widget.epubPlayerKey.currentState?.clearSearch();
                } else {
                  widget.epubPlayerKey.currentState?.search(trimmed);
                }
              },
            ),
          ),
          if (isSearchActive)
            GestureDetector(
              onTap: () {
                searchBarController.clear();
                widget.epubPlayerKey.currentState?.clearSearch();
              },
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: palette.subForeground,
              ),
            ),
        ],
      ),
    );
    var searchResult = Expanded(
        child: Column(
      children: [
        const SizedBox(height: 6.0),
        if (showSearchProgress)
          LinearProgressIndicator(
            value: progressValue,
          ),
        Expanded(
          // 原来搜不到时是空白，用户会以为搜索卡住了；补一个空状态，
          // 但搜索进行中不显示（避免每敲一个字闪一下）
          child: (searchResults.isEmpty && !showSearchProgress && isSearchActive)
              ? _buildSearchEmptyState(context)
              : searchResults.isEmpty
                  ? const SizedBox()
                  : ListView.builder(
                  controller: searchResultsScrollController,
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    return searchResultWidget(
                      searchResult: searchResults[index],
                      hideAppBarAndBottomBar: widget.hideAppBarAndBottomBar,
                      epubPlayerKey: widget.epubPlayerKey,
                      closeDrawer: widget.closeDrawer,
                    );
                  },
                ),
        ),
      ],
    ));
    final columnChildren = <Widget>[
      Row(
        children: [
          Expanded(child: searchBox),
          if (!isSearchActive) locatingButton,
        ],
      ),
    ];

    columnChildren.add(
      isSearchActive
          ? searchResult
          : Expanded(
              child: ScrollablePositionedList.builder(
                itemScrollController: _itemScrollController,
                itemPositionsListener: _itemPositionsListener,
                itemCount: _visibleItems.length,
                itemBuilder: (context, index) {
                  final entry = _visibleItems[index];
                  final tocItem = entry.item;
                  final key = entry.key;
                  final isSelected = selectedKeys.contains(key);
                  final isCurrentLeaf =
                      currentHref == tocItem.href && tocItem.subitems.isEmpty;

                  return TocItemWidget(
                    tocItem: tocItem,
                    depth: entry.depth,
                    isExpanded: entry.isExpanded,
                    isSelected: isSelected,
                    showProgress: isCurrentLeaf,
                    progressText: currentProgress,
                    palette: _palette,
                    onToggle: tocItem.subitems.isEmpty
                        ? null
                        : () => _toggleExpanded(tocItem),
                    onTap: () {
                      widget.hideAppBarAndBottomBar(false);
                      widget.epubPlayerKey.currentState!.goToHref(tocItem.href);
                      widget.closeDrawer();
                    },
                  );
                },
              ),
            ),
    );
    return Column(children: columnChildren);
  }
}

/// 书内搜索没有命中时的空状态（与书架空状态同一套品牌语言）
Widget _buildSearchEmptyState(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final pine = SongJiangColors.pine;

  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pine.withAlpha(isDark ? 26 : 18),
          ),
          child: Icon(
            Icons.search_off_outlined,
            size: 40,
            color: pine.withAlpha(isDark ? 190 : 200),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '没有找到相关内容',
          style: TextStyle(
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
          ),
        ),
      ],
    ),
  );
}

Widget searchResultWidget({
  required SearchResultModel searchResult,
  required Function hideAppBarAndBottomBar,
  required GlobalKey<EpubPlayerState> epubPlayerKey,
  required VoidCallback closeDrawer,
}) {
  bool isExpanded = true;
  return StatefulBuilder(
    builder: (context, setState) {
      // 用 StatefulBuilder 给的 context 取主题，不再依赖 navigatorKey
      // （后者在页面未挂载时 currentContext 为 null，`!` 会直接抛异常）
      final scheme = Theme.of(context).colorScheme;
      final matchStyle = TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.bold,
      );
      final prePostStyle = TextStyle(
        color: scheme.onSurface.withAlpha(160),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            onPressed: () {
              setState(() {
                isExpanded = !isExpanded;
              });
            },
            child: Row(
              children: [
                Flexible(child: Text(searchResult.label)),
                isExpanded
                    ? const Icon(Icons.expand_less)
                    : const Icon(Icons.expand_more),
                // const Spacer(),
                Text(
                  searchResult.subitems.length.toString(),
                  style: prePostStyle,
                ),
              ],
            ),
          ),
          if (isExpanded)
            for (var subItem in searchResult.subitems)
              FilledContainer(
                margin: EdgeInsets.only(bottom: 5),
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                radius: 10,
                child: InkWell(
                  onTap: () {
                    hideAppBarAndBottomBar(false);
                    epubPlayerKey.currentState!.goToCfi(subItem.cfi);
                    closeDrawer();
                  },
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(text: subItem.pre, style: prePostStyle),
                        TextSpan(text: subItem.match, style: matchStyle),
                        TextSpan(text: subItem.post, style: prePostStyle),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      );
    },
  );
}

class TocItemWidget extends StatelessWidget {
  const TocItemWidget({
    super.key,
    required this.tocItem,
    required this.depth,
    required this.isExpanded,
    required this.isSelected,
    required this.showProgress,
    required this.progressText,
    required this.onToggle,
    required this.onTap,
    this.palette,
  });

  final TocItem tocItem;
  final int depth;
  final bool isExpanded;
  final bool isSelected;
  final bool showProgress;
  final String progressText;
  final VoidCallback? onToggle;
  final VoidCallback onTap;

  /// 阅读页调色板；为空时回退到 Material 主题色。
  final SjReaderPalette? palette;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = palette ??
        SjReaderPalette.fromTheme(scheme.surface, scheme.onSurface);

    final labelStyle = TextStyle(
      fontFamily: SjReaderText.serif,
      fontSize: 15,
      height: 1.35,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      color: isSelected ? p.accent : p.foreground,
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: showProgress ? 62 : 46),
        padding: EdgeInsets.only(
          left: depth == 0 ? 2 : 2 + depth * 18.0,
          right: 2,
          top: 12,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (tocItem.subitems.isNotEmpty)
              GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: p.faint,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tocItem.label.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                  if (isSelected && showProgress) ...<Widget>[
                    const SizedBox(height: 5),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.menu_book_rounded,
                          size: 12,
                          color: p.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '当前读到',
                          style: TextStyle(fontSize: 11, color: p.accent),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          progressText,
                          style: TextStyle(fontSize: 11, color: p.faint),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              tocItem.percentage,
              style: TextStyle(fontSize: 12, color: p.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibleTocEntry {
  const _VisibleTocEntry({
    required this.item,
    required this.key,
    required this.depth,
    required this.isExpanded,
  });

  final TocItem item;
  final String key;
  final int depth;
  final bool isExpanded;
}
