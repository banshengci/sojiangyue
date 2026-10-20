import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/translate_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/bookshelf_prefs.dart';
import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/bgimg_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/book_note.dart';
import 'package:songjiang_reader/enums/page_turn_mode.dart';
import 'package:songjiang_reader/enums/reading_info.dart';
import 'package:songjiang_reader/enums/translation_mode.dart';
import 'package:songjiang_reader/enums/writing_mode.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/models/bookmark.dart';
import 'package:songjiang_reader/models/font_model.dart';
import 'package:songjiang_reader/models/read_theme.dart';
import 'package:songjiang_reader/models/reading_rules.dart';
import 'package:songjiang_reader/models/reading_info.dart';
import 'package:songjiang_reader/models/search_result_model.dart';
import 'package:songjiang_reader/models/toc_item.dart';
import 'package:songjiang_reader/page/book_player/image_viewer.dart';
import 'package:songjiang_reader/page/home_page.dart';
import 'package:songjiang_reader/page/reading_page.dart';
import 'package:songjiang_reader/providers/book_list.dart';
import 'package:songjiang_reader/providers/book_toc.dart';
import 'package:songjiang_reader/providers/bookmark.dart';
import 'package:songjiang_reader/providers/chapter_content_bridge.dart';
import 'package:songjiang_reader/plugin/plugin_event_dispatcher.dart';
import 'package:songjiang_reader/providers/current_reading.dart';
import 'package:songjiang_reader/service/book_player/book_player_server.dart';
import 'package:songjiang_reader/providers/toc_search.dart';
import 'package:songjiang_reader/service/tts/base_tts.dart';
import 'package:songjiang_reader/service/tts/models/tts_sentence.dart';
import 'package:songjiang_reader/service/tts/tts_handler.dart';
import 'package:songjiang_reader/utils/coordinates_to_part.dart';
import 'package:songjiang_reader/utils/js/convert_dart_color_to_js.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';
import 'package:songjiang_reader/models/book_note.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/webView/gererate_url.dart';
import 'package:songjiang_reader/utils/webView/webview_console_message.dart';
import 'package:songjiang_reader/widgets/bookshelf/book_cover.dart';
import 'package:songjiang_reader/widgets/context_menu/context_menu.dart';
import 'package:songjiang_reader/widgets/reading_page/more_settings/page_turning/diagram.dart';
import 'package:songjiang_reader/widgets/reading_page/more_settings/page_turning/types_and_icons.dart';
import 'package:songjiang_reader/widgets/reading_page/style_widget.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'minute_clock.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

class EpubPlayer extends ConsumerStatefulWidget {
  final Book book;
  final String? cfi;
  final Function showOrHideAppBarAndBottomBar;
  final Function onLoadEnd;
  final List<ReadTheme> initialThemes;
  final Function updateParent;

  const EpubPlayer(
      {super.key,
      required this.showOrHideAppBarAndBottomBar,
      required this.book,
      this.cfi,
      required this.onLoadEnd,
      required this.initialThemes,
      required this.updateParent});

  @override
  ConsumerState<EpubPlayer> createState() => EpubPlayerState();
}

class EpubPlayerState extends ConsumerState<EpubPlayer>
    with TickerProviderStateMixin {
  late InAppWebViewController webViewController;
  late ContextMenu contextMenu;
  String cfi = '';
  double percentage = 0.0;
  String chapterTitle = '';
  String chapterHref = '';
  int chapterCurrentPage = 0;
  int chapterTotalPages = 0;
  String _dispatchedChapterHref = '';
  OverlayEntry? contextMenuEntry;
  AnimationController? _animationController;
  Animation<double>? _animation;
  bool showHistory = false;
  bool canGoBack = false;
  bool canGoForward = false;
  late Book book;
  String? backgroundColor;
  String? textColor;
  Timer? styleTimer;
  String bookmarkCfi = '';
  bool bookmarkExists = false;
  WritingModeEnum writingMode = WritingModeEnum.horizontalTb;
  String? _lastSelectionContextText;
  bool _selectionClearLocked = false;
  bool _selectionClearPending = false;

  // 覆盖 / 仿真两档需要 Flutter 参与：
  //
  // 引擎那边整本书是**一张连续的画布**，翻页就是把画布横向滚一格，
  // 没有「两页同时在场」的图层，所以「旧页停住、新页压上来」这件事
  // 它做不到。这里的做法是：翻页前抓一张旧页的截图盖在最上面，
  // 让引擎瞬间翻到新页，再把截图演走——用户看到的就是真正的覆盖/翻页。
  //
  // 抓不到截图时（桌面端没实现、视图还没画出来）直接退回引擎动画，
  // 不能因为动画把翻页本身弄坏。
  AnimationController? _turnController;
  Uint8List? _turnShot;
  bool _turnForward = true;
  bool _turnBusy = false;

  // Scroll wheel debounce
  Timer? _scrollDebounceTimer;
  double _accumulatedScrollDelta = 0;
  static const double _scrollThreshold = 50.0;

  // to know anytime if we are on top of navigation stack
  bool get _isTopOfNavigationStack =>
      ModalRoute.of(context)?.isCurrent ?? false;

  void prevPage() {
    _turnPage(forward: false);
  }

  void nextPage() {
    _turnPage(forward: true);
  }

  /// 翻一页。覆盖 / 仿真走 Flutter 过渡，其余三档交给引擎。
  Future<void> _turnPage({required bool forward}) async {
    final js = forward ? 'nextPage()' : 'prevPage()';
    final mode = ReadingStylePrefs.pageTurnStyle;
    // 抓图到动画结束之间不接受第二次翻页：连点两下会叠两层过渡。
    if (!mode.isFlutterDriven || _turnBusy) {
      await webViewController.evaluateJavascript(source: js);
      return;
    }

    // 1) 先抓旧页。抓不到就老老实实用引擎自己的动画。
    Uint8List? shot;
    _turnBusy = true;
    try {
      shot = await webViewController.takeScreenshot();
    } catch (_) {
      shot = null;
    }
    if (shot == null || !mounted) {
      _turnBusy = false;
      await webViewController.evaluateJavascript(source: js);
      return;
    }

    // 2) 盖上去：这一帧的像素和当前页一致，用户看不出发生了什么。
    setState(() {
      _turnShot = shot;
      _turnForward = forward;
    });

    // 3) 让引擎「瞬间」翻页：临时摘掉 animated，翻完再装回去。
    await webViewController.evaluateJavascript(source: '''
      (function () {
        var r = globalThis.reader && reader.view && reader.view.renderer;
        var had = r ? r.hasAttribute('animated') : false;
        if (had) r.removeAttribute('animated');
        $js;
        setTimeout(function () { if (had) r.setAttribute('animated', 'true'); }, 150);
      })();
    ''');

    if (!mounted) return;

    // 4) 截图演走，露出下面已经翻好的新页。
    final controller = _turnController;
    if (controller == null) {
      _turnBusy = false;
      setState(() => _turnShot = null);
      return;
    }
    await controller.forward(from: 0);
    _turnBusy = false;
    if (!mounted) return;
    setState(() => _turnShot = null);
  }

  /// 翻页过渡的一帧。[child] 是翻页前的截图。
  Widget _turnFrame(BuildContext context, Widget child) {
    final controller = _turnController;
    if (controller == null) return child;
    final t = Curves.easeOutCubic.transform(controller.value.clamp(0.0, 1.0));

    if (ReadingStylePrefs.pageTurnStyle == PageTurn.simulation) {
      // 仿真：旧页像一张纸一样绕书脊转走，带一点透视。
      final angle = (_turnForward ? -1 : 1) * (math.pi / 2) * t;
      return Transform(
        alignment: _turnForward ? Alignment.centerLeft : Alignment.centerRight,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(angle),
        child: child,
      );
    }

    // 覆盖：旧页整体滑出屏幕，新页在下面露出来。
    final width = MediaQuery.sizeOf(context).width;
    return Transform.translate(
      offset: Offset((_turnForward ? -1 : 1) * width * t, 0),
      child: child,
    );
  }

  void prevChapter() {
    webViewController.evaluateJavascript(source: '''
      prevSection()
      ''');
  }

  void nextChapter() {
    webViewController.evaluateJavascript(source: '''
      nextSection()
      ''');
  }

  void setTranslationMode(TranslationModeEnum mode) {
    webViewController.evaluateJavascript(source: '''
      if (typeof reader.view !== 'undefined' && reader.view.setTranslationMode) {
        reader.view.setTranslationMode('${mode.code}');
      }
      ''');
  }

  Future<void> goToPercentage(double value) async {
    await webViewController.evaluateJavascript(source: '''
      goToPercent($value); 
      ''');
  }

  void setSelectionClearLocked(bool locked) {
    _selectionClearLocked = locked;
    if (!locked && _selectionClearPending) {
      _selectionClearPending = false;
      _lastSelectionContextText = null;
      removeOverlay();
    }
  }

  void changeTheme(ReadTheme readTheme) {
    textColor = readTheme.textColor;
    backgroundColor = readTheme.backgroundColor;

    String bc = convertDartColorToJs(readTheme.backgroundColor);
    String tc = convertDartColorToJs(readTheme.textColor);

    webViewController.evaluateJavascript(source: '''
      changeStyle({
        backgroundColor: '#$bc',
        fontColor: '#$tc',
      })
      // 把整页（含视口里没有正文的空白区）也铺成纸色。
      // WebView 是透明平台视图，页面没有绘制到的地方在部分机型上会露成黑块——
      // 阅读页底部那条黑边就是这么来的。
      document.documentElement.style.backgroundColor = '#$bc';
      if (document.body) {
        document.body.style.backgroundColor = '#$bc';
        document.body.style.minHeight = '100vh';
      }
      ''');
  }

  /// 瀹夊叏鍖虹敱澶栧眰 reading_page.dart 鐨?Padding 缁熶竴澶勭悊锛?
  /// WebView 鍐呴儴涓嶅啀閲嶅娣诲姞锛岄伩鍏嶅弻閲嶇暀鐧姐€?
  ({double top, double bottom}) _safeInsets() {
    return (top: 0, bottom: 0);
  }

  void changeStyle(BookStyle? bookStyle) {
    styleTimer?.cancel();
    String bgimgUrl = BgimgPrefs.bgimg.getEffectiveUrl(
          isDarkMode: isDarkMode,
          autoAdjust: ThemePrefs.autoAdjustReadingTheme,
        );

    styleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      BookStyle style = bookStyle ?? ReadingStylePrefs.bookStyle;
      final insets = _safeInsets();
      webViewController.evaluateJavascript(source: '''
      changeStyle({
        fontSize: ${style.fontSize},
        spacing: ${style.lineHeight},
        fontWeight: ${style.fontWeight},
        paragraphSpacing: ${style.paragraphSpacing},
        topMargin: ${style.topMargin + insets.top + Prefs().readingInfo.reservedTop},
        bottomMargin: ${style.bottomMargin + insets.bottom + Prefs().readingInfo.reservedBottom},
        sideMargin: ${style.sideMargin},
        letterSpacing: ${style.letterSpacing},
        textIndent: ${style.indent},
        maxColumnCount: ${style.maxColumnCount},
        columnThreshold: ${style.columnThreshold},
        writingMode: '${ReadingStylePrefs.writingMode.code}',
        textAlign: '${ReadingStylePrefs.textAlignment.code}',
        backgroundImage: '$bgimgUrl',
        bgimgBlur: ${BgimgPrefs.bgimg.blur},
        bgimgOpacity: ${BgimgPrefs.bgimg.opacity},
        bgimgFit: '${BgimgPrefs.fit.code}',
        customCSS: `${[ReadingUiPrefs.customCss, ReadingStylePrefs.headingCss].where((s) => s.trim().isNotEmpty).join(' ').replaceAll('`', '\\`')}`,
        customCSSEnabled: ${ReadingUiPrefs.customCssEnabled || ReadingStylePrefs.headingCss.isNotEmpty},
        useBookStyles: ${ReadingStylePrefs.useBookStyles},
        headingFontSize: ${style.headingFontSize},
        codeHighlightTheme: '${ReadingUiPrefs.codeHighlightTheme.code}',
      })
      ''');
    });
  }

  void changeBgimgEffect() {
    if (!mounted) return;
    final bgimg = BgimgPrefs.bgimg;
    final bgimgUrl = bgimg.getEffectiveUrl(
      isDarkMode: isDarkMode,
      autoAdjust: ThemePrefs.autoAdjustReadingTheme,
    );
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        backgroundImage: '$bgimgUrl',
        bgimgBlur: ${bgimg.blur},
        bgimgOpacity: ${bgimg.opacity},
        bgimgFit: '${BgimgPrefs.fit.code}',
      })
    ''');
  }

  void changeReadingRules(ReadingRules readingRules) {
    webViewController.evaluateJavascript(source: '''
      readingFeatures({
        convertChineseMode: '${readingRules.convertChineseMode.name}',
        bionicReadingMode: ${readingRules.bionicReading},
      })
    ''');
  }

  void changeFont(FontModel font) {
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        fontName: '${font.name}',
        fontPath: '${font.path}',
      })
    ''');
  }

  void changePageTurnStyle(PageTurn pageTurnStyle) {
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        pageTurnStyle: '${pageTurnStyle.name}',
      })
    ''');
  }

  void goToHref(String href) =>
      webViewController.evaluateJavascript(source: "goToHref('$href')");

  void goToCfi(String cfi) =>
      webViewController.evaluateJavascript(source: "goToCfi('$cfi')");

  void addAnnotation(BookNote bookNote) {
    final noteContent =
        (bookNote.content).replaceAll('\n', ' ').replaceAll("'", "\\'");
    webViewController.evaluateJavascript(source: '''
      addAnnotation({
        id: ${bookNote.id},
        type: '${bookNote.type}',
        value: '${bookNote.cfi}',
        color: '#${bookNote.color}',
        note: '$noteContent',
      })
      ''');
  }

  void addBookmark(BookmarkModel bookmark) {
    webViewController.evaluateJavascript(source: '''
      addAnnotation({
        id: ${bookmark.id},
        type: 'bookmark',
        value: '${bookmark.cfi}',
        color: '#000000',
        note: 'None',
      })
      ''');
  }

  void addBookmarkHere() {
    webViewController.evaluateJavascript(source: '''
      addBookmarkHere()
      ''');
  }

  void removeAnnotation(String cfi) =>
      webViewController.evaluateJavascript(source: "removeAnnotation('$cfi')");

  void clearSearch() {
    ref.read(tocSearchProvider.notifier).clear();
    _clearSearchHighlights();
  }

  void search(String text) {
    final sanitized = text.trim();
    if (sanitized.isEmpty) {
      clearSearch();
      return;
    }
    _clearSearchHighlights();
    ref.read(tocSearchProvider.notifier).start(sanitized);
    webViewController.evaluateJavascript(source: '''
      search('$sanitized', {
        'scope': 'book',
        'matchCase': false,
        'matchDiacritics': false,
        'matchWholeWords': false,
      })
    ''');
  }

  void _clearSearchHighlights() {
    webViewController.evaluateJavascript(source: "clearSearch()");
  }

  Future<void> initTts({String? fromCfi}) async {
    if (fromCfi != null && fromCfi.isNotEmpty) {
      await webViewController.evaluateJavascript(
          source: "window.ttsFromCfi('$fromCfi')");
    } else {
      await webViewController.evaluateJavascript(source: "window.ttsHere()");
    }
  }

  void ttsStop() => webViewController.evaluateJavascript(source: "ttsStop()");

  // TTS 取文本的几个入口都兜成空串。
  //
  // `evaluateJavascript` / `callAsyncJavaScript` 返回的是 Object?，JS 侧
  // 没准备好时就是 null；直接塞进 `Future<String>` 会在运行时抛
  // 「type 'Null' is not a subtype of String」，而这些调用都发生在
  // flutter_tts 的平台回调里，异常没人接，表现为朗读突然停住、
  // 日志里只有一条无从下手的错误。
  //
  // 空串在 speak() 里会被安全跳过，下一句还会再进来。

  Future<String> ttsNext() async =>
      (await webViewController.callAsyncJavaScript(
                  functionBody: "return await ttsNext()"))
              ?.value ??
          '';

  Future<String> ttsPrev() async =>
      (await webViewController.callAsyncJavaScript(
                  functionBody: "return await ttsPrev()"))
              ?.value ??
          '';

  Future<String> ttsPrevSection() async =>
      (await webViewController.callAsyncJavaScript(
                  functionBody: "return await ttsPrevSection()"))
              ?.value ??
          '';

  Future<String> ttsNextSection() async =>
      (await webViewController.callAsyncJavaScript(
                  functionBody: "return await ttsNextSection()"))
              ?.value ??
          '';

  Future<String> ttsPrepare() async {
    final value =
        await webViewController.evaluateJavascript(source: "ttsPrepare()");
    return value?.toString() ?? '';
  }

  TtsSentence? _parseTtsSentence(dynamic value) {
    if (value is Map<dynamic, dynamic>) {
      try {
        return TtsSentence.fromMap(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  List<TtsSentence> _parseTtsSentences(dynamic value) {
    if (value is! List) return const [];

    final sentences = <TtsSentence>[];
    for (final item in value) {
      final sentence = _parseTtsSentence(item);
      if (sentence != null) {
        sentences.add(sentence);
      }
    }
    return sentences;
  }

  Future<TtsSentence?> ttsCurrentDetail() async {
    final result = await webViewController.callAsyncJavaScript(
      functionBody: 'return ttsCurrentDetail()',
    );
    return _parseTtsSentence(result?.value);
  }

  Future<List<TtsSentence>> ttsCollectDetails({
    required int count,
    bool includeCurrent = false,
    int offset = 1,
  }) async {
    final result = await webViewController.callAsyncJavaScript(
      functionBody:
          'return ttsCollectDetails($count, ${includeCurrent ? 'true' : 'false'}, $offset)',
    );
    return _parseTtsSentences(result?.value);
  }

  Future<void> ttsHighlightByCfi(String cfi) async {
    await webViewController.callAsyncJavaScript(
      functionBody: 'return ttsHighlightByCfi(${jsonEncode(cfi)})',
    );
  }

  Future<bool> isFootNoteOpen() async => (await webViewController
      .evaluateJavascript(source: "window.isFootNoteOpen()"));

  void backHistory() {
    webViewController.evaluateJavascript(source: "back()");
  }

  void forwardHistory() {
    webViewController.evaluateJavascript(source: "forward()");
  }

  void refreshToc() {
    webViewController.evaluateJavascript(source: "refreshToc()");
  }

  Future<String> theChapterContent() async =>
      await webViewController.evaluateJavascript(
        source: "theChapterContent()",
      );

  Future<String> previousContent(int count) async =>
      await webViewController.evaluateJavascript(
        source: "previousContent($count)",
      );

  Future<String> _getCurrentChapterContent({int? maxCharacters}) async {
    final raw = await theChapterContent();
    return _normalizeChapterContent(raw, maxCharacters);
  }

  Future<String> _getChapterContentByHref(
    String href, {
    int? maxCharacters,
  }) async {
    if (href.isEmpty) {
      return '';
    }

    final result = await webViewController.callAsyncJavaScript(
      functionBody:
          'return await getChapterContentByHref("${href.replaceAll('"', '\\"')}")',
    );

    final value = result?.value;
    if (value is String) {
      return _normalizeChapterContent(value, maxCharacters);
    }
    return '';
  }

  String _normalizeChapterContent(String? content, int? maxCharacters) {
    if (content == null || content.isEmpty) {
      return '';
    }
    final trimmed = content.trim();
    if (maxCharacters != null &&
        maxCharacters > 0 &&
        trimmed.length > maxCharacters) {
      return trimmed.substring(0, maxCharacters);
    }
    return trimmed;
  }

  void _registerChapterContentBridge() {
    ref.read(chapterContentBridgeProvider.notifier).state =
        ChapterContentHandlers(
      fetchCurrentChapter: ({int? maxCharacters}) =>
          _getCurrentChapterContent(maxCharacters: maxCharacters),
      fetchChapterByHref: (href, {int? maxCharacters}) =>
          _getChapterContentByHref(href, maxCharacters: maxCharacters),
    );
  }

  Future<void> _handleExternalLink(dynamic rawLink) async {
    String? normalizeExternalLink(dynamic raw) {
      if (raw == null) {
        return null;
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
      if (raw is Map && raw['href'] is String) {
        final href = raw['href'].toString().trim();
        return href.isEmpty ? null : href;
      }
      return null;
    }

    final link = normalizeExternalLink(rawLink);
    if (!mounted || link == null) {
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme.isEmpty || uri.scheme == 'javascript') {
      SjLog.warning('Ignored invalid external link: $link');
      return;
    }

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = L10n.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.readingPageOpenExternalLinkTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.readingPageOpenExternalLinkMessage),
              const SizedBox(height: 8),
              SelectableText(link),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.readingPageOpenExternalLinkAction),
            ),
          ],
        );
      },
    );

    if (shouldOpen != true) {
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      SjLog.warning('Failed to open external link: $link');
    }
  }

  void onClick(Map<String, dynamic> location) {
    readingPageKey.currentState?.resetAwakeTimer();
    if (contextMenuEntry != null) {
      removeOverlay();
      return;
    }
    final x = location['x'];
    final y = location['y'];
    final part = coordinatesToPart(x, y);

    PageTurningType action;
    final pageTurnMode = PageTurnMode.fromCode(ReadingStylePrefs.pageTurnMode);

    if (pageTurnMode == PageTurnMode.simple) {
      // Use predefined page turning types
      final currentPageTurningType = ReadingStylePrefs.pageTurningType;
      final pageTurningType = pageTurningTypes[currentPageTurningType];
      action = pageTurningType[part];

      // Apply swap if enabled
      if (ReadingUiPrefs.swapPageTurnArea) {
        if (action == PageTurningType.prev) {
          action = PageTurningType.next;
        } else if (action == PageTurningType.next) {
          action = PageTurningType.prev;
        }
      }
    } else {
      // Use custom configuration
      final customConfig = ReadingStylePrefs.customPageTurnConfig;
      action = PageTurningType.values[customConfig[part]];
    }

    // Disable mouse/touch page turning when keyboard shortcuts are enabled
    if (ReadingUiPrefs.keyboardShortcutTurnPage) {
      // Only allow menu action, disable prev/next page turning
      if (action == PageTurningType.prev || action == PageTurningType.next) {
        return;
      }
    }

    switch (action) {
      case PageTurningType.prev:
        prevPage();
        break;
      case PageTurningType.next:
        nextPage();
        break;
      case PageTurningType.menu:
        widget.showOrHideAppBarAndBottomBar(true);
        break;
      case PageTurningType.none:
        break;
    }
  }

  Future<void> renderAnnotations(InAppWebViewController controller) async {
    List<BookNote> annotationList =
        await bookNoteDao.selectBookNotesByBookId(widget.book.id);
    String allAnnotations =
        jsonEncode(annotationList.map((e) => e.toJson()).toList())
            .replaceAll('\'', '\\\'');
    controller.evaluateJavascript(source: '''
     const allAnnotations = $allAnnotations
     renderAnnotations()
    ''');
  }

  void getThemeColor() {
    if (ThemePrefs.autoAdjustReadingTheme) {
      List<ReadTheme> themes = widget.initialThemes;
      final isDayMode =
          Theme.of(navigatorKey.currentContext!).brightness == Brightness.light;
      backgroundColor =
          isDayMode ? themes[0].backgroundColor : themes[1].backgroundColor;
      textColor = isDayMode ? themes[0].textColor : themes[1].textColor;
    } else {
      backgroundColor = AppMiscPrefs.readTheme.backgroundColor;
      textColor = AppMiscPrefs.readTheme.textColor;
    }
  }

  Future<void> setHandler(InAppWebViewController controller) async {
    controller.addJavaScriptHandler(
        handlerName: 'onLoadEnd',
        callback: (args) {
          widget.onLoadEnd();
        });

    controller.addJavaScriptHandler(
        handlerName: 'onRelocated',
        callback: (args) {
          Map<String, dynamic> location = args[0];
          if (cfi == location['cfi']) return;
          final prevHref = chapterHref;
          final prevCfi = cfi;
          // if (chapterHref != location['chapterHref']) {
          //   refreshToc();
          // }
          setState(() {
            cfi = location['cfi'] ?? '';
            percentage =
                double.tryParse(location['percentage'].toString()) ?? 0.0;
            chapterTitle = location['chapterTitle'] ?? '';
            chapterHref = location['chapterHref'] ?? '';
            chapterCurrentPage = location['chapterCurrentPage'] ?? 0;
            chapterTotalPages = location['chapterTotalPages'] ?? 0;
            bookmarkExists = location['bookmark']['exists'] ?? false;
            bookmarkCfi = location['bookmark']['cfi'] ?? '';
            writingMode =
                WritingModeEnum.fromCode(location['writingMode'] ?? '');
          });
          // 杩涘叆鏂扮珷鑺傛椂瑙﹀彂鎻掍欢浜嬩欢锛堝彂鍗冲純锛宑hapterHref 鍘婚噸閬垮厤鍚岀珷鍐呯炕椤甸噸澶嶈Е鍙戯級銆?
          if (chapterHref != _dispatchedChapterHref) {
            _dispatchedChapterHref = chapterHref;
            PluginEventDispatcher.instance.onChapterEntered(
              widget.book.id,
              chapterIndex: chapterCurrentPage,
            );
          }
          // 同一章内翻页才算"翻页"；换章由 onChapterEntered 负责，
          // 否则一次跳转会同时发两个事件。
          if (prevHref == chapterHref &&
              prevCfi.isNotEmpty &&
              prevCfi != cfi &&
              PluginRegistry.instance.hasHooksFor(
                PluginEventType.onPageTurn,
              )) {
            PluginEventDispatcher.instance.onPageTurned(
              widget.book.id,
              cfi: cfi,
            );
          }

          ref.read(currentReadingProvider.notifier).update(
                cfi: cfi,
                percentage: percentage,
                chapterTitle: chapterTitle,
                chapterHref: chapterHref,
                chapterCurrentPage: chapterCurrentPage,
                chapterTotalPages: chapterTotalPages,
              );
          widget.updateParent();
          saveReadingProgress();
          readingPageKey.currentState?.resetAwakeTimer();
        });
    controller.addJavaScriptHandler(
        handlerName: 'onClick',
        callback: (args) {
          Map<String, dynamic> location = args[0];
          onClick(location);
        });
    controller.addJavaScriptHandler(
      handlerName: 'onExternalLink',
      callback: (args) async {
        final payload = args.isNotEmpty ? args.first : null;
        await _handleExternalLink(payload);
      },
    );
    controller.addJavaScriptHandler(
        handlerName: 'onSetToc',
        callback: (args) {
          List<dynamic> t = args[0];
          final toc = t.map((i) => TocItem.fromJson(i)).toList();
          ref.read(bookTocProvider.notifier).setToc(toc);
        });
    controller.addJavaScriptHandler(
        handlerName: 'onSelectionEnd',
        callback: (args) {
          removeOverlay();
          Map<String, dynamic> location = args[0];
          String cfi = location['cfi'];
          String text = location['text'];
          bool footnote = location['footnote'];
          final rawContextText = location['contextText']?.toString();
          _lastSelectionContextText =
              (rawContextText?.trim().isEmpty ?? true) ? null : rawContextText;
          double left = (location['pos']['left'] as num).toDouble();
          double top = (location['pos']['top'] as num).toDouble();
          double right = (location['pos']['right'] as num).toDouble();
          double bottom = (location['pos']['bottom'] as num).toDouble();
          // 划词钩子：只在真的有插件监听时才分发，避免每次选择都白跑一趟。
          final selected = text.trim();
          if (selected.length >= 2 &&
              PluginRegistry.instance.hasHooksFor(
                PluginEventType.onSelectText,
              )) {
            PluginEventDispatcher.instance.onSelectText(
              widget.book.id,
              text: selected,
            );
          }

          showContextMenu(
            context,
            left,
            top,
            right,
            bottom,
            text,
            cfi,
            null,
            footnote,
            writingMode.isVertical ? Axis.vertical : Axis.horizontal,
            contextText: _lastSelectionContextText,
          );
        });
    controller.addJavaScriptHandler(
        handlerName: 'onSelectionCleared',
        callback: (args) {
          if (_selectionClearLocked) {
            _selectionClearPending = true;
            return;
          }
          _lastSelectionContextText = null;
          removeOverlay();
        });
    controller.addJavaScriptHandler(
        handlerName: 'onAnnotationClick',
        callback: (args) {
          Map<String, dynamic> annotation = args[0];

          if (annotation['annotation'] == null) {
            // Check if TTS is active and the click is on the currently read text
            final currentTtsState = TtsHandler().ttsStateNotifier.value;
            if (currentTtsState == TtsStateEnum.playing ||
                currentTtsState == TtsStateEnum.paused) {
              if (currentTtsState == TtsStateEnum.playing) {
                audioHandler.pause();
              } else {
                audioHandler.play();
              }
              return;
            }
          }

          int id = annotation['annotation']['id'];
          String cfi = annotation['annotation']['value'];
          String note = annotation['annotation']['note'];
          final rawContextText = annotation['contextText']?.toString();
          _lastSelectionContextText =
              (rawContextText?.trim().isEmpty ?? true) ? null : rawContextText;
          double left = (annotation['pos']['left'] as num).toDouble();
          double top = (annotation['pos']['top'] as num).toDouble();
          double right = (annotation['pos']['right'] as num).toDouble();
          double bottom = (annotation['pos']['bottom'] as num).toDouble();
          showContextMenu(
            context,
            left,
            top,
            right,
            bottom,
            note,
            cfi,
            id,
            false,
            writingMode.isVertical ? Axis.vertical : Axis.horizontal,
            contextText: _lastSelectionContextText,
          );
        });
    controller.addJavaScriptHandler(
      handlerName: 'onSearch',
      callback: (args) {
        Map<String, dynamic> search = args[0];
        setState(() {
          final tocSearch = ref.read(tocSearchProvider.notifier);
          if (search['process'] != null) {
            final progress = search['process'].toDouble();
            tocSearch.updateProgress(progress);
          } else {
            tocSearch.addResult(SearchResultModel.fromJson(search));
          }
        });
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'renderAnnotations',
      callback: (args) {
        renderAnnotations(controller);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onPushState',
      callback: (args) {
        Map<String, dynamic> state = args[0];
        if (!mounted) return;
        setState(() {
          canGoBack = state['canGoBack'];
          canGoForward = state['canGoForward'];
          showHistory = canGoBack || canGoForward;
        });
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onImageClick',
      callback: (args) {
        String image = args[0];
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ImageViewer(
                      image: image,
                      bookName: widget.book.title,
                    )));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onFootnoteClose',
      callback: (args) {
        removeOverlay();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onPullUp',
      callback: (args) {
        widget.showOrHideAppBarAndBottomBar(true);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'handleBookmark',
      callback: (args) async {
        Map<String, dynamic> detail = args[0]['detail'];
        bool remove = args[0]['remove'];
        String cfi = detail['cfi'] ?? '';
        double percentage = double.parse(detail['percentage'].toString());
        String content = detail['content'];

        if (remove) {
          ref.read(bookmarkProvider(widget.book.id).notifier).removeBookmark(
                cfi: cfi,
              );
          bookmarkCfi = '';
          bookmarkExists = false;
        } else {
          BookmarkModel bookmark = await ref
              .read(BookmarkProvider(widget.book.id).notifier)
              .addBookmark(
                BookmarkModel(
                  bookId: widget.book.id,
                  cfi: cfi,
                  percentage: percentage,
                  content: content,
                  chapter: chapterTitle,
                  updateTime: DateTime.now(),
                  createTime: DateTime.now(),
                ),
              );
          bookmarkCfi = cfi;
          bookmarkExists = true;
          addBookmark(bookmark);
        }
        widget.updateParent();
        setState(() {});
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'translateText',
      callback: (args) async {
        try {
          String text = args[0];
          final service = TranslatePrefs.fullTextService;
          final from = TranslatePrefs.fullTextFrom;
          final to = TranslatePrefs.fullTextTo;

          return await service.provider
              .translateTextOnly(text, from, to, isFullText: true);
        } catch (e) {
          SjLog.severe('Translation error: $e');
          return 'Translation error: $e';
        }
      },
    );
  }

  Future<void> onWebViewCreated(InAppWebViewController controller) async {
    if (SjPlatform.isAndroid) {
      await InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
    webViewController = controller;
    setHandler(controller);
    _registerChapterContentBridge();

    // Initialize translation mode based on book-specific settings
    Future.delayed(const Duration(milliseconds: 300), () {
      setTranslationMode(
          Prefs().getBookTranslationMode(widget.book.id.toString()));
      // 鍐嶆涓嬪彂鏍峰紡锛氱‘淇濆畨鍏ㄥ尯杈硅窛鍦ㄩ灞忔覆鏌撳悗浠嶇敓鏁堬紙闃插渾瑙掕瀛楋級
      changeStyle(null);
    });
  }

  void removeOverlay() {
    _selectionClearLocked = false;
    _selectionClearPending = false;
    if (contextMenuEntry == null || contextMenuEntry?.mounted == false) return;
    contextMenuEntry?.remove();
    contextMenuEntry = null;
  }

  Future<void> _handlePointerEvents(PointerEvent event) async {
    if (await isFootNoteOpen() || ReadingStylePrefs.pageTurnStyle == PageTurn.scroll) {
      return;
    }
    // Disable scroll wheel page turning when keyboard shortcuts are enabled
    if (ReadingUiPrefs.keyboardShortcutTurnPage) {
      return;
    }
    if (event is PointerScrollEvent) {
      _accumulatedScrollDelta += event.scrollDelta.dy;

      _scrollDebounceTimer?.cancel();
      _scrollDebounceTimer = Timer(const Duration(milliseconds: 80), () {
        if (_accumulatedScrollDelta.abs() >= _scrollThreshold) {
          if (_accumulatedScrollDelta > 0) {
            nextPage();
          } else {
            prevPage();
          }
        }
        _accumulatedScrollDelta = 0;
      });
    }
  }

  @override
  void initState() {
    book = widget.book;
    getThemeColor();

    contextMenu = ContextMenu(
      settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: true),
      onCreateContextMenu: (hitTestResult) async {
        // webViewController.evaluateJavascript(source: "showContextMenu()");
      },
      onHideContextMenu: () {
        // removeOverlay();
      },
    );
    if (BookshelfPrefs.openBookAnimation) {
      _animationController = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      _animation =
          Tween<double>(begin: 1.0, end: 0.0).animate(_animationController!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animationController!.forward();
      });
    }
    _turnController = AnimationController(
      duration: const Duration(milliseconds: 260),
      vsync: this,
    );
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> saveReadingProgress() async {
    if (cfi == '' || widget.cfi != null) return;
    Book book = widget.book;
    book.lastReadPosition = cfi;
    book.readingPercentage = percentage;
    await bookDao.updateBook(book);
    if (mounted) {
      ref.read(bookListProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _animationController?.dispose();
    _turnController?.dispose();
    saveReadingProgress();
    removeOverlay();
    super.dispose();
  }

  InAppWebViewSettings initialSettings = InAppWebViewSettings(
    supportZoom: false,
    transparentBackground: true,
    isInspectable: kDebugMode,
    useHybridComposition: true,
  );

  bool get isDarkMode =>
      Theme.of(navigatorKey.currentContext!).brightness == Brightness.dark;

  void changeReadingInfo() {
    setState(() {});
  }

  Widget _buildHistoryCapsule() {
    final l10n = L10n.of(context);
    final buttonColor = Color(int.parse('0x$textColor')).withAlpha(200);

    // Common button style for all history navigation buttons
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
      ),
    );

    // Helper method to create history navigation buttons
    Widget createHistoryButton(
        IconData icon, String label, VoidCallback onPressed) {
      return TextButton.icon(
        icon: Icon(icon, size: 18, color: buttonColor),
        label: Text(label, style: TextStyle(color: buttonColor, fontSize: 14)),
        onPressed: onPressed,
        style: buttonStyle,
      );
    }

    // Build buttons list
    final List<Widget> buttons = [];

    if (canGoBack) {
      buttons.add(createHistoryButton(
        Icons.arrow_back,
        l10n.historyBack,
        backHistory,
      ));
    }

    buttons.add(createHistoryButton(
      Icons.close,
      l10n.historyClose,
      () => setState(() => showHistory = false),
    ));

    if (canGoForward) {
      buttons.add(createHistoryButton(
        Icons.arrow_forward,
        l10n.historyForward,
        forwardHistory,
      ));
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainer
                    .withAlpha(123),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: buttons,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget readingInfoWidget() {
    if (chapterCurrentPage == 0 && percentage == 0.0) {
      return const SizedBox();
    }

    final readingInfoColor = Color(int.parse('0x$textColor')).withAlpha(150);
    final iconColor = Color(int.parse('0x$textColor'));

    Widget getWidget(ReadingInfoEnum readingInfoEnum, TextStyle textStyle) {
      // 电量徽标按字号等比缩放：以前是拿 battery_0_bar 当底、把数字盖在图标
      // 中间，可那个字形右侧有电极帽、内腔并不居中，数字总是偏左偏上，
      // 字号一调就出界。现在自己画外壳，数字放在内腔正中。
      final baseFontSize = textStyle.fontSize ?? 10;
      final batteryBodyHeight = baseFontSize * 1.15;
      final batteryBodyWidth = batteryBodyHeight * 1.9;
      final batteryCapWidth = (batteryBodyHeight * 0.13).clamp(1.2, 2.6);
      final batteryCapHeight = batteryBodyHeight * 0.42;
      final batteryTextStyle = TextStyle(
        color: iconColor,
        fontSize: batteryBodyHeight * 0.62,
        height: 1,
        fontWeight: FontWeight.w500,
      );

      final chapterTitleWidget = Text(
        (chapterCurrentPage == 1 ? widget.book.title : chapterTitle),
        style: textStyle,
      );

      final chapterProgressWidget = Text(
        '$chapterCurrentPage/$chapterTotalPages',
        style: textStyle,
      );

      final bookProgressWidget =
          Text('${(percentage * 100).toStringAsFixed(2)}%', style: textStyle);

      final bookNameWidget = Text(widget.book.title, style: textStyle);

      // 只显示页码本身：窄格子里「3/12」常常被截断，只留数字更稳。
      final pageWidget = Text('$chapterCurrentPage', style: textStyle);

      final batteryPercentWidget = FutureBuilder(
          future: Battery().batteryLevel,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            return Text('${snapshot.data}%', style: textStyle);
          });

      final timeWidget = MinuteClock(textStyle: textStyle);

      final batteryWidget = FutureBuilder(
          future: Battery().batteryLevel,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: batteryBodyWidth,
                  height: batteryBodyHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: iconColor, width: 1),
                    borderRadius:
                        BorderRadius.circular(batteryBodyHeight * 0.28),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: batteryBodyHeight * 0.06,
                    ),
                    // FittedBox 兜底：三位数（100）或用户把字号调到很大时
                    // 宁可缩一点，也不要溢出到电池壳外面
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${snapshot.data}', style: batteryTextStyle),
                    ),
                  ),
                ),
                Container(
                  width: batteryCapWidth,
                  height: batteryCapHeight,
                  margin: const EdgeInsets.only(left: 0.8),
                  decoration: BoxDecoration(
                    color: iconColor,
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(batteryCapWidth),
                    ),
                  ),
                ),
              ],
            );
          });

      Widget batteryAndTimeWidget() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              batteryWidget,
              const SizedBox(width: 5),
              timeWidget,
            ],
          );

      // 「时间+电量」与「时间+电量%」的区别只在电量画成图标还是数字。
      Widget timeAndBatteryWidget() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              timeWidget,
              const SizedBox(width: 5),
              batteryWidget,
            ],
          );

      Widget timeAndBatteryPercentWidget() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              timeWidget,
              const SizedBox(width: 5),
              batteryPercentWidget,
            ],
          );

      switch (readingInfoEnum) {
        case ReadingInfoEnum.bookName:
          return bookNameWidget;
        case ReadingInfoEnum.page:
          return pageWidget;
        case ReadingInfoEnum.timeBattery:
          return timeAndBatteryWidget();
        case ReadingInfoEnum.timeBatteryPercent:
          return timeAndBatteryPercentWidget();
        case ReadingInfoEnum.chapterTitle:
          return chapterTitleWidget;
        case ReadingInfoEnum.chapterProgress:
          return chapterProgressWidget;
        case ReadingInfoEnum.bookProgress:
          return bookProgressWidget;
        case ReadingInfoEnum.battery:
          return batteryWidget;
        case ReadingInfoEnum.time:
          return timeWidget;
        case ReadingInfoEnum.batteryAndTime:
          return batteryAndTimeWidget();
        case ReadingInfoEnum.none:
          return const SizedBox(width: 30);
      }
    }

    final readingInfo = Prefs().readingInfo;

    final headerTextStyle = TextStyle(
      color: readingInfoColor,
      fontSize: readingInfo.header.fontSize,
    );
    final footerTextStyle = TextStyle(
      color: readingInfoColor,
      fontSize: readingInfo.footer.fontSize,
    );

    List<Widget> headerWidgets = [
      getWidget(readingInfo.header.left, headerTextStyle),
      getWidget(readingInfo.header.center, headerTextStyle),
      getWidget(readingInfo.header.right, headerTextStyle),
    ];

    List<Widget> footerWidgets = [
      getWidget(readingInfo.footer.left, footerTextStyle),
      getWidget(readingInfo.footer.center, footerTextStyle),
      getWidget(readingInfo.footer.right, footerTextStyle),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: readingInfo.header.verticalMargin,
            left: readingInfo.header.leftMargin,
            right: readingInfo.header.rightMargin,
          ),
          child: Row(
            // 三格各自对齐，中间那格才是真的居中——
            // 原来用 spaceBetween，只开「中」时它会贴在左边，看起来像设错了。
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: headerWidgets[0],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: headerWidgets[1],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: headerWidgets[2],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.only(
            bottom: readingInfo.footer.verticalMargin,
            left: readingInfo.footer.leftMargin,
            right: readingInfo.footer.rightMargin,
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: footerWidgets[0],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: footerWidgets[1],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: footerWidgets[2],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildWebviewWithIOSWorkaround(
      BuildContext context, String url, String initialCfi) {
    final webView = InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialUrlRequest: URLRequest(
        url: WebUri(
          generateUrl(
            url,
            initialCfi,
            backgroundColor: backgroundColor,
            textColor: textColor,
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
            safeTop: 0,
            safeBottom: 0,
          ),
        ),
      ),
      initialSettings: initialSettings,
      contextMenu: contextMenu,
      onLoadStop: (controller, uri) => onWebViewCreated(controller),
      onConsoleMessage: webviewConsoleMessage,
    );

    if (!SjPlatform.isIOS) {
      return SizedBox.expand(child: webView);
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          webView,
          Positioned.fill(
            child: PointerInterceptor(
              intercepting: !_isTopOfNavigationStack,
              debug: false,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String uri = Uri.encodeComponent(widget.book.fileFullPath);
    String url = 'http://127.0.0.1:${Server().port}/book/$uri';
    String initialCfi = widget.cfi ?? widget.book.lastReadPosition;

    return Listener(
      onPointerSignal: (event) {
        _handlePointerEvents(event);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            buildWebviewWithIOSWorkaround(context, url, initialCfi),
            // 覆盖 / 仿真的过渡层：翻页前那一页的截图，演完即撤。
            if (_turnShot != null && _turnController != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _turnController!,
                    builder: (context, child) => _turnFrame(context, child!),
                    child: Image.memory(
                      _turnShot!,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            readingInfoWidget(),
            if (showHistory) _buildHistoryCapsule(),
            if (BookshelfPrefs.openBookAnimation)
              SizedBox.expand(
                  child: IgnorePointer(
                ignoring: true,
                child: FadeTransition(
                    opacity: _animation!, child: BookCover(book: widget.book)),
              )),
          ],
        ),
      ),
    );
  }
}
