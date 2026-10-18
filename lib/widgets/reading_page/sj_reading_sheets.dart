/// 松江阅 · 微信读书风格上滑面板（接真实阅读状态）
///
/// 设计模块 `lib/design/songjiang/reader/` 里的面板是纯展示组件，
/// 这里把它们接到真实数据上：
///  - 目录 / 笔记复用既有的 [TocWidget]、[BookNotesList]，避免重写搜索与笔记逻辑；
///  - 进度、亮度、字体绑定 [EpubPlayerState] 与阅读偏好。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/dao/book_note.dart';
import 'package:songjiang_reader/dao/reading_time.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_controls.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_panels.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/models/read_theme.dart';
import 'package:songjiang_reader/page/book_notes_page.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';
import 'package:songjiang_reader/service/notes/export_notes.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/book_notes/book_notes_list.dart';
import 'package:songjiang_reader/widgets/bookshelf/book_cover.dart';
import 'package:songjiang_reader/widgets/reading_page/style_widget.dart';
import 'package:songjiang_reader/widgets/reading_page/toc_widget.dart';

// ---------------------------------------------------------------------------
// 目录
// ---------------------------------------------------------------------------

/// 目录面板：微信读书同款上滑大面板，内容沿用既有目录树。
class SjTocSheet extends StatelessWidget {
  const SjTocSheet({
    super.key,
    required this.palette,
    required this.book,
    required this.epubPlayerKey,
    required this.onClose,
  });

  final SjReaderPalette palette;
  final Book book;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SjReaderSheet(
      palette: palette,
      showHandle: true,
      expand: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: TocWidget(
        epubPlayerKey: epubPlayerKey,
        hideAppBarAndBottomBar: (bool show) {
          if (!show) onClose();
        },
        closeDrawer: onClose,
        bookTitle: book.title,
        palette: palette,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 笔记
// ---------------------------------------------------------------------------

/// 笔记面板：书籍摘要卡 + 入口 + 本书笔记列表。
class SjNotesSheet extends StatefulWidget {
  const SjNotesSheet({
    super.key,
    required this.palette,
    required this.book,
    required this.epubPlayerKey,
    required this.onClose,
    required this.onBookDetail,
  });

  final SjReaderPalette palette;
  final Book book;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final VoidCallback onClose;
  final VoidCallback onBookDetail;

  @override
  State<SjNotesSheet> createState() => _SjNotesSheetState();
}

class _SjNotesSheetState extends State<SjNotesSheet> {
  String _readingTimeText = '';

  @override
  void initState() {
    super.initState();
    _loadReadingTime();
  }

  Future<void> _loadReadingTime() async {
    try {
      final seconds =
          await readingTimeDao.selectTotalReadingTimeByBookId(widget.book.id);
      if (!mounted) return;
      setState(() {
        _readingTimeText = _formatDuration(seconds);
      });
    } catch (_) {
      // 统计失败不影响面板主体
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '时长 0 分钟';
    if (seconds < 60) return '时长 <1 分钟';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '时长 $minutes 分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '时长 $hours 小时' : '时长 $hours 小时 $rest 分钟';
  }

  Future<void> _addBookmark() async {
    widget.epubPlayerKey.currentState?.addBookmarkHere();
    SjToast.show('已添加书签');
  }

  Future<void> _export() async {
    final notes = await bookNoteDao.selectBookNotesByBookId(widget.book.id);
    if (!mounted) return;
    if (notes.isEmpty) {
      SjToast.show('本书还没有笔记可以导出');
      return;
    }
    final type = await showModalBottomSheet<ExportType>(
      context: context,
      backgroundColor: widget.palette.surface,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final entry in const <(String, ExportType)>[
              ('复制到剪贴板', ExportType.copy),
              ('导出 Markdown', ExportType.md),
              ('导出 TXT', ExportType.txt),
              ('导出 CSV', ExportType.csv),
            ])
              ListTile(
                title: Text(
                  entry.$1,
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.palette.foreground,
                  ),
                ),
                onTap: () => Navigator.pop(context, entry.$2),
              ),
          ],
        ),
      ),
    );
    if (type == null) return;
    await exportNotes(widget.book, notes, type);
  }

  void _openAllNotes() {
    widget.onClose();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BookNotesPage(
          book: widget.book,
          numberOfNotes: 0,
          isMobile: MediaQuery.of(context).size.width < 600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return SjReaderSheet(
      palette: palette,
      showHandle: true,
      expand: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SjNotesPanel(
        palette: palette,
        bookTitle: widget.book.title,
        readingTimeText:
            _readingTimeText.isEmpty ? '时长统计中…' : _readingTimeText,
        cover: BookCover(book: widget.book, width: 46, height: 64, radius: 6),
        onAddBookmark: _addBookmark,
        onAllNotes: _openAllNotes,
        onExportNotes: _export,
        onBookDetail: () {
          widget.onClose();
          widget.onBookDetail();
        },
        onSeeAllNotes: _openAllNotes,
        child: BookNotesList(book: widget.book, reading: true),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 进度
// ---------------------------------------------------------------------------

/// 进度面板：阅读进度 / 阅读时长 / 笔记数 + 进度滑块。
class SjProgressSheet extends StatefulWidget {
  const SjProgressSheet({
    super.key,
    required this.palette,
    required this.book,
    required this.epubPlayerKey,
    required this.onBookDetail,
  });

  final SjReaderPalette palette;
  final Book book;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final VoidCallback onBookDetail;

  @override
  State<SjProgressSheet> createState() => _SjProgressSheetState();
}

class _SjProgressSheetState extends State<SjProgressSheet> {
  double _percent = 0;
  int _noteCount = 0;
  int _seconds = 0;
  Timer? _seekTimer;

  @override
  void initState() {
    super.initState();
    _percent =
        (widget.epubPlayerKey.currentState?.percentage ?? 0).clamp(0.0, 1.0);
    _loadStats();
  }

  @override
  void dispose() {
    _seekTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final notes = await bookNoteDao.selectBookNotesByBookId(widget.book.id);
      final seconds =
          await readingTimeDao.selectTotalReadingTimeByBookId(widget.book.id);
      if (!mounted) return;
      setState(() {
        _noteCount = notes.length;
        _seconds = seconds;
      });
    } catch (_) {
      // 统计失败时保持默认值
    }
  }

  String get _durationText {
    if (_seconds <= 0) return '0分钟';
    if (_seconds < 60) return '<1分钟';
    final minutes = _seconds ~/ 60;
    if (minutes < 60) return '$minutes分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours小时' : '$hours小时$rest分';
  }

  void _seek(double value) {
    setState(() => _percent = value);
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 120), () {
      widget.epubPlayerKey.currentState?.goToPercentage(value);
    });
  }

  void _addBookmark() {
    widget.epubPlayerKey.currentState?.addBookmarkHere();
    SjToast.show('已添加书签');
  }

  @override
  Widget build(BuildContext context) {
    return SjReaderSheet(
      palette: widget.palette,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: SjProgressPanel(
        palette: widget.palette,
        percent: _percent,
        readingTimeText: _durationText,
        noteCountText: '$_noteCount条',
        primaryLabel: '阅读笔记',
        secondaryLabel: '添加书签',
        onSeek: _seek,
        onPrimary: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => BookNotesPage(
                book: widget.book,
                numberOfNotes: _noteCount,
                isMobile: MediaQuery.of(context).size.width < 600,
              ),
            ),
          );
        },
        onSecondary: _addBookmark,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 亮度 / 颜色
// ---------------------------------------------------------------------------

/// 亮度面板：亮度遮罩 + 四张纸张色 + 背景入口。
class SjAppearanceSheet extends StatefulWidget {
  const SjAppearanceSheet({
    super.key,
    required this.palette,
    required this.epubPlayerKey,
    required this.onBrightnessChanged,
    required this.onThemeChanged,
    required this.onOpenBgImage,
  });

  final SjReaderPalette palette;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final ValueChanged<double> onBrightnessChanged;
  final VoidCallback onThemeChanged;
  final VoidCallback onOpenBgImage;

  @override
  State<SjAppearanceSheet> createState() => _SjAppearanceSheetState();
}

class _SjAppearanceSheetState extends State<SjAppearanceSheet> {
  late double _brightness = ReadingUiPrefs.readerBrightness;

  static const List<SjReaderBackground> _backgrounds = <SjReaderBackground>[
    SjReaderBackground(colors: <Color>[Color(0xFFF4E6C8), Color(0xFFEED9B4)]),
    SjReaderBackground(colors: <Color>[Color(0xFFF7E9EC), Color(0xFFEFD6DC)]),
    SjReaderBackground(colors: <Color>[Color(0xFFF9D9B0), Color(0xFFF0BE8A)]),
    SjReaderBackground(colors: <Color>[Color(0xFFDCD3E6), Color(0xFFC6BAD8)]),
  ];

  String get _currentPaperId => SjReaderPaper.match(
        Color(
          int.parse('0x${AppMiscPrefs.readTheme.backgroundColor}'),
        ),
      ).id;

  /// 把 Color 转成主题表里存的 8 位 ARGB 字符串。
  String _hex(Color color) =>
      color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0');

  Future<void> _applyPaper(SjReaderPaper paper) async {
    final theme = ReadTheme(
      name: paper.label,
      backgroundColor: _hex(paper.background),
      textColor: _hex(paper.foreground),
      backgroundImagePath: '',
    );
    AppMiscPrefs.saveReadTheme(theme);
    widget.epubPlayerKey.currentState?.changeTheme(theme);
    widget.onThemeChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SjReaderSheet(
      palette: widget.palette,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: SjAppearancePanel(
        palette: widget.palette,
        brightness: _brightness,
        papers: SjReaderPaper.presets,
        selectedPaperId: _currentPaperId,
        onBrightness: (double value) {
          setState(() => _brightness = value);
          widget.onBrightnessChanged(value);
        },
        onBrightnessEnd: () => ReadingUiPrefs.readerBrightness = _brightness,
        onPaperSelected: _applyPaper,
        backgrounds: _backgrounds,
        onBackgroundSelected: (_) => widget.onOpenBgImage(),
        onMoreBackgrounds: widget.onOpenBgImage,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 字体
// ---------------------------------------------------------------------------

/// 字体面板：字号 / 边距 / 行距，以及字体样式、缩进、翻页入口。
class SjTypographySheet extends StatefulWidget {
  const SjTypographySheet({
    super.key,
    required this.palette,
    required this.epubPlayerKey,
    required this.onOpenMoreSettings,
  });

  final SjReaderPalette palette;
  final GlobalKey<EpubPlayerState> epubPlayerKey;

  /// 打开完整排版设置（既有 StyleWidget）。
  final VoidCallback onOpenMoreSettings;

  @override
  State<SjTypographySheet> createState() => _SjTypographySheetState();
}

class _SjTypographySheetState extends State<SjTypographySheet> {
  /// 边距档位对应的左右留白。
  static const List<double> _margins = <double>[4, 12, 20];

  /// 行距档位。
  static const List<double> _lineHeights = <double>[1.5, 1.8, 2.1];

  /// foliate 的 fontSize 是 em 倍数，1em ≈ 16px。
  static const double _emToPx = 16;

  late final BookStyle _style = ReadingStylePrefs.bookStyle;

  void _apply() {
    widget.epubPlayerKey.currentState?.changeStyle(_style);
    ReadingStylePrefs.saveBookStyle(_style);
    setState(() {});
  }

  int get _marginIndex {
    var best = 0;
    for (var i = 0; i < _margins.length; i++) {
      if ((_margins[i] - _style.sideMargin).abs() <
          (_margins[best] - _style.sideMargin).abs()) {
        best = i;
      }
    }
    return best;
  }

  int get _lineHeightIndex {
    var best = 0;
    for (var i = 0; i < _lineHeights.length; i++) {
      if ((_lineHeights[i] - _style.lineHeight).abs() <
          (_lineHeights[best] - _style.lineHeight).abs()) {
        best = i;
      }
    }
    return best;
  }

  Future<void> _pickPageTurn() async {
    final labels = <PageTurn, String>{
      PageTurn.noAnimation: L10n.of(context).noAnimation,
      PageTurn.slide: L10n.of(context).slide,
      PageTurn.scroll: L10n.of(context).scroll,
    };
    final current = ReadingStylePrefs.pageTurnStyle;
    final picked = await showModalBottomSheet<PageTurn>(
      context: context,
      backgroundColor: widget.palette.surface,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final entry in labels.entries)
              ListTile(
                title: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 14,
                    color: entry.key == current
                        ? widget.palette.accent
                        : widget.palette.foreground,
                  ),
                ),
                trailing: entry.key == current
                    ? Icon(Icons.check_rounded,
                        size: 18, color: widget.palette.accent)
                    : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    ReadingStylePrefs.pageTurnStyle = picked;
    widget.epubPlayerKey.currentState?.changePageTurnStyle(picked);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SjReaderSheet(
      palette: widget.palette,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: SjTypographyPanel(
        palette: widget.palette,
        fontSize: (_style.fontSize * _emToPx).clamp(12.0, 30.0),
        marginIndex: _marginIndex,
        lineHeightIndex: _lineHeightIndex,
        onMore: widget.onOpenMoreSettings,
        moreLabel: '更多设置',
        onFontSize: (double px) {
          _style.fontSize = px / _emToPx;
          _apply();
        },
        onFontSizeEnd: () => ReadingStylePrefs.saveBookStyle(_style),
        onMargin: (int index) {
          _style.sideMargin = _margins[index];
          _apply();
        },
        onLineHeight: (int index) {
          _style.lineHeight = _lineHeights[index];
          _apply();
        },
        onFontFamily: widget.onOpenMoreSettings,
        onIndent: () {
          _style.indent = _style.indent > 0 ? 0 : 2;
          _apply();
          SjToast.show(_style.indent > 0 ? '已开启首行缩进' : '已关闭首行缩进');
        },
        onPageTurn: _pickPageTurn,
      ),
    );
  }
}
