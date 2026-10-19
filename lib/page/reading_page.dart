import 'dart:async';
import 'dart:math' as math;

import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/bookshelf_prefs.dart';
import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/plugin/plugin_event_dispatcher.dart';
import 'package:songjiang_reader/dao/reading_time.dart';
import 'package:songjiang_reader/dao/theme.dart';
import 'package:songjiang_reader/enums/ai_panel_position.dart';
import 'package:songjiang_reader/enums/ai_chat_display_mode.dart';
import 'package:songjiang_reader/enums/sync_direction.dart';
import 'package:songjiang_reader/enums/sync_trigger.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/theme/songjiang_icons.dart';
import 'package:songjiang_reader/models/ai_quick_prompt_chip.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/models/read_theme.dart';
import 'package:songjiang_reader/page/book_detail.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';
import 'package:songjiang_reader/providers/sync.dart';
import 'package:songjiang_reader/service/ai/index.dart';
import 'package:songjiang_reader/service/ai/prompt_generate.dart';
import 'package:songjiang_reader/utils/env_var.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/utils/ui/status_bar.dart';
import 'package:songjiang_reader/widgets/ai/ai_chat_stream.dart';
import 'package:songjiang_reader/widgets/ai/ai_stream.dart';
import 'package:songjiang_reader/models/reading_time.dart';
import 'package:songjiang_reader/widgets/reading_page/sj_reading_sheets.dart';
import 'package:songjiang_reader/widgets/reading_page/tts_fab.dart';
import 'package:songjiang_reader/widgets/reading_page/tts_widget.dart';
import 'package:songjiang_reader/widgets/reading_page/style_widget.dart';
import 'package:songjiang_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_chrome.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_controls.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';
import 'package:songjiang_reader/widgets/common/axis_flex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:flutter/foundation.dart'
// show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({
    super.key,
    required this.book,
    this.cfi,
    required this.initialThemes,
    this.heroTag,
  });

  final Book book;
  final String? cfi;
  final List<ReadTheme> initialThemes;
  final String? heroTag;

  @override
  ConsumerState<ReadingPage> createState() => ReadingPageState();
}

final GlobalKey<ReadingPageState> readingPageKey =
    GlobalKey<ReadingPageState>();
final epubPlayerKey = GlobalKey<EpubPlayerState>();

class ReadingPageState extends ConsumerState<ReadingPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const empty = SizedBox.shrink();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Book _book;

  /// 当前展开的阅读工具位（目录 / 笔记 / 进度 / 亮度 / 字体）。
  ///
  /// 微信读书的底栏只有五个图标位，展开哪个就高亮哪个；
  /// 面板内容按工具位在 [build] 里现算，主题切换后能立刻刷新。
  SjReaderTool? _activeTool;

  /// 面板内的二级页面（主题编辑、背景图选择等）临时覆盖当前工具位。
  Widget? _overridePage;

  /// 阅读页亮度遮罩，1 为不遮罩。
  late double _brightness = ReadingUiPrefs.readerBrightness;
  final Stopwatch _readTimeWatch = Stopwatch();
  DateTime? _sessionStart;
  Timer? _awakeTimer;
  bool bottomBarOffstage = true;
  late String heroTag;
  Widget? _aiChat;
  final aiChatKey = GlobalKey<AiChatStreamState>();
  static const double _aiChatMinWidth = 240;
  late double _aiChatWidth;
  static const double _aiChatMinHeight = 200;
  late double _aiChatHeight;
  bool _isResizingAiChat = false;
  bool bookmarkExists = false;

  late final FocusNode _readerFocusNode;
  // late final VolumeKeyBoard _volumeKeyBoard;
  // bool _volumeKeyListenerAttached = false;

  @override
  void initState() {
    _readerFocusNode = FocusNode(debugLabel: 'reading_page_focus');

    // Initialize AI panel sizes from persistent storage
    _aiChatWidth = AiPrefs.aiPanelWidth;
    _aiChatHeight = AiPrefs.aiPanelHeight;

    if (widget.book.isDeleted) {
      Navigator.pop(context);
      SjToast.show(L10n.of(context).bookDeleted);
      return;
    }
    if (ReadingUiPrefs.hideStatusBar) {
      hideStatusBar();
    }

    WidgetsBinding.instance.addObserver(this);
    _readTimeWatch.start();
    _sessionStart = DateTime.now();
    setAwakeTimer(ReadingUiPrefs.awakeTime);

    _book = widget.book;
    heroTag = widget.heroTag ?? 'preventHeroWhenStart';
    // 触发插件「打开书籍」事件（发即弃，不阻塞阅读器初始化）。
    PluginEventDispatcher.instance.onBookOpened(_book.id);
    // _volumeKeyBoard = VolumeKeyBoard.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestReaderFocus();
        // _attachVolumeKeyListener();
      }
    });
    // delay 1000ms to prevent hero animation
    if (widget.heroTag == null) {
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            heroTag = _book.coverFullPath;
          });
        }
      });
    }
    super.initState();
  }

  @override
  void dispose() {
    Sync().syncData(SyncDirection.upload, ref, trigger: SyncTrigger.auto);
    _readTimeWatch.stop();
    _awakeTimer?.cancel();
    WakelockPlus.disable();
    showStatusBar();
    WidgetsBinding.instance.removeObserver(this);
    readingTimeDao.insertReadingTime(
      ReadingTime(
        bookId: _book.id,
        readingTime: _readTimeWatch.elapsed.inSeconds,
      ),
      startedAt: _sessionStart,
    );
    _sessionStart = null;
    audioHandler.stop();
    // if (_volumeKeyListenerAttached) {
    //   unawaited(_volumeKeyBoard.removeListener());
    // }
    _readerFocusNode.dispose();
    super.dispose();
  }

  void _requestReaderFocus() {
    if (bottomBarOffstage && !_readerFocusNode.hasFocus) {
      _readerFocusNode.requestFocus();
    }
  }

  void _releaseReaderFocus() {
    if (_readerFocusNode.hasFocus) {
      _readerFocusNode.unfocus();
    }
  }

  // Future<void> _attachVolumeKeyListener() async {
  //   if (defaultTargetPlatform != TargetPlatform.iOS ||
  //       _volumeKeyListenerAttached) {
  //     return;
  //   }

  //   try {
  //     await _volumeKeyBoard.addListener(_handleVolumeKeyEvent);
  //     _volumeKeyListenerAttached = true;
  //   } catch (error) {
  //     debugPrint('Failed to attach volume key listener: $error');
  //   }
  // }

  // void _handleVolumeKeyEvent(VolumeKey key) {
  //   if (!ReadingUiPrefs.volumeKeyTurnPage || !_readerFocusNode.hasFocus) {
  //     return;
  //   }

  //   if (key == VolumeKey.up) {
  //     epubPlayerKey.currentState?.prevPage();
  //   } else if (key == VolumeKey.down) {
  //     epubPlayerKey.currentState?.nextPage();
  //   }
  // }

  KeyEventResult _handleReaderKeyEvent(FocusNode node, KeyEvent event) {
    if (!_readerFocusNode.hasFocus) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;

    if (logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.pageDown ||
        logicalKey == LogicalKeyboardKey.space) {
      epubPlayerKey.currentState?.nextPage();
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.pageUp) {
      epubPlayerKey.currentState?.prevPage();
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.enter) {
      showOrHideAppBarAndBottomBar(true);
      return KeyEventResult.handled;
    }

    // Handle Ctrl+[ and Ctrl+] for page turning when keyboard shortcut is enabled
    if (ReadingUiPrefs.keyboardShortcutTurnPage) {
      final isControlPressed = HardwareKeyboard.instance.isControlPressed;
      if (isControlPressed && logicalKey == LogicalKeyboardKey.bracketLeft) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (isControlPressed && logicalKey == LogicalKeyboardKey.bracketRight) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
      final bool isSimulatedCtrlLeft = event.character == '\u001b';
      final bool isSimulatedCtrlRight = event.character == '\u001d';
      if (isSimulatedCtrlLeft) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (isSimulatedCtrlRight) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
    }

    if (ReadingUiPrefs.volumeKeyTurnPage) {
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeUp) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeDown) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_readTimeWatch.isRunning) {
          _readTimeWatch.start();
        }
        _sessionStart ??= DateTime.now();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_readTimeWatch.isRunning) {
          _readTimeWatch.stop();
        }
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          final elapsedSeconds = _readTimeWatch.elapsed.inSeconds;
          if (elapsedSeconds > 5) {
            epubPlayerKey.currentState?.saveReadingProgress();
            readingTimeDao.insertReadingTime(
              ReadingTime(
                bookId: _book.id,
                readingTime: elapsedSeconds,
              ),
              startedAt: _sessionStart,
            );
          }
          _readTimeWatch.reset();
          _sessionStart = null;
        }
        break;
    }
  }

  Future<void> setAwakeTimer(int minutes) async {
    _awakeTimer?.cancel();
    _awakeTimer = null;
    WakelockPlus.enable();
    _awakeTimer = Timer.periodic(Duration(minutes: minutes), (timer) {
      WakelockPlus.disable();
      _awakeTimer?.cancel();
      _awakeTimer = null;
    });
  }

  void resetAwakeTimer() {
    setAwakeTimer(ReadingUiPrefs.awakeTime);
  }

  void showBottomBar() {
    setState(() {
      showStatusBarWithoutResize();
      bottomBarOffstage = false;
      _releaseReaderFocus();
    });
  }

  void hideBottomBar() {
    setState(() {
      _activeTool = null;
      _overridePage = null;
      bottomBarOffstage = true;
      if (ReadingUiPrefs.hideStatusBar) {
        hideStatusBar();
      }
      _requestReaderFocus();
    });
  }

  void showOrHideAppBarAndBottomBar(bool show) {
    if (show) {
      showBottomBar();
    } else {
      hideBottomBar();
    }
  }

  /// 阅读页调色板：由当前阅读主题的底色 / 字色派生，
  /// 工具栏、面板、分隔线都跟着纸张走，不会出现「米黄纸张 + 白底面板」。
  SjReaderPalette get _palette => SjReaderPalette.fromTheme(
        Color(int.parse('0x${AppMiscPrefs.readTheme.backgroundColor}')),
        Color(int.parse('0x${AppMiscPrefs.readTheme.textColor}')),
      );

  /// 打开某个工具位；再次点击同一个图标收起面板。
  void _openTool(SjReaderTool tool) {
    if (!bottomBarOffstage && _activeTool == tool && _overridePage == null) {
      showOrHideAppBarAndBottomBar(false);
      return;
    }
    showBottomBar();
    setState(() {
      _activeTool = tool;
      _overridePage = null;
    });
  }

  void tocHandler() => _openTool(SjReaderTool.toc);

  void noteHandler() => _openTool(SjReaderTool.notes);

  void progressHandler() => _openTool(SjReaderTool.progress);

  void appearanceHandler() => _openTool(SjReaderTool.appearance);

  void typographyHandler() => _openTool(SjReaderTool.typography);

  /// 复制本章内容（沿用原顶栏的「分享」位）。
  Future<void> _copyChapter() async {
    try {
      final content = await epubPlayerKey.currentState?.theChapterContent();
      final length = content?.length ?? 0;
      if (length > 0) {
        await Clipboard.setData(ClipboardData(text: content!));
      }
      // 取正文与写剪贴板都是 await，期间阅读页可能已退出
      if (!mounted) return;
      SjToast.show(L10n.of(context).readingPageCopiedCharacters(length));
    } catch (e) {
      if (!mounted) return;
      SjToast.show(L10n.of(context).readingPageErrorCopyingContent);
    }
  }

  void _openBookDetail() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => BookDetail(book: widget.book),
      ),
    );
  }

  /// 打开完整的排版设置（既有 StyleWidget，含字体、页边距、翻页方式、自定义 CSS）。
  Future<void> styleHandler() async {
    final themes = await themeDao.selectThemes();
    if (!mounted) return;
    showBottomBar();
    setState(() {
      _overridePage = StyleWidget(
        themes: themes,
        epubPlayerKey: epubPlayerKey,
        setCurrentPage: (Widget page) {
          setState(() {
            _overridePage = page;
          });
        },
        hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  void ttsHandler() {
    showBottomBar();
    setState(() {
      _activeTool = null;
      _overridePage = TtsWidget(
        epubPlayerKey: epubPlayerKey,
      );
    });
  }

  double _aiChatMaxWidth(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width;
    final maxByPercentage = totalWidth * 0.65;
    final maxByRemaining = totalWidth - 320;
    final maxWidth = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinWidth, maxWidth);
  }

  double _aiChatMaxHeight(BuildContext context) {
    final totalHeight = MediaQuery.of(context).size.height;
    final maxByPercentage = totalHeight * 0.60;
    final maxByRemaining = totalHeight - 320;
    final maxHeight = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinHeight, maxHeight);
  }

  void _beginAiChatResize(double globalDx) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDelta(double delta, BuildContext context) {
    final maxWidth = _aiChatMaxWidth(context);
    final updated =
        (_aiChatWidth - delta).clamp(_aiChatMinWidth, maxWidth).toDouble();
    if (updated != _aiChatWidth) {
      setState(() {
        _aiChatWidth = updated;
      });
    }
  }

  void _endAiChatResize() {
    if (_isResizingAiChat) {
      setState(() {
        _isResizingAiChat = false;
      });
      // Save the panel sizes to persistent storage
      AiPrefs.aiPanelWidth = _aiChatWidth;
      AiPrefs.aiPanelHeight = _aiChatHeight;
    }
  }

  void _beginAiChatResizeVertical(double globalDy) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDeltaVertical(double delta, BuildContext context) {
    final maxHeight = _aiChatMaxHeight(context);
    final updated =
        (_aiChatHeight - delta).clamp(_aiChatMinHeight, maxHeight).toDouble();
    if (updated != _aiChatHeight) {
      setState(() {
        _aiChatHeight = updated;
      });
    }
  }

  Future<void> onLoadEnd() async {
    if (ReadingUiPrefs.autoSummaryPreviousContent) {
      final previousContent =
          await epubPlayerKey.currentState!.previousContent(2000);
      final prompt = generatePromptSummaryThePreviousContent(previousContent);
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).readingPageSummaryPreviousContent),
          content: AiStream(
            prompt: prompt,
          ),
        ),
        onDismiss: () {
          cancelActiveAiRequest();
        },
      );
    }
  }

  List<Widget> _buildAiChatTrailing(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          setState(() {
            AiPrefs.aiPanelPosition =
                AiPrefs.aiPanelPosition == AiPanelPositionEnum.right
                    ? AiPanelPositionEnum.bottom
                    : AiPanelPositionEnum.right;
            // Rebuild the _aiChat widget to update the button
            _rebuildAiChat();
          });
        },
        icon: Icon(
          AiPrefs.aiPanelPosition == AiPanelPositionEnum.right
              ? Icons.arrow_downward
              : Icons.arrow_forward,
        ),
        tooltip: AiPrefs.aiPanelPosition == AiPanelPositionEnum.right
            ? L10n.of(context).aiShowAtBottom
            : L10n.of(context).aiShowAtRight,
      ),
      IconButton(
        onPressed: () {
          setState(() {
            _aiChat = null;
          });
        },
        icon: const Icon(Icons.close),
      ),
    ];
  }

  void _rebuildAiChat() {
    if (_aiChat == null) return;
    final maxWidth = _aiChatMaxWidth(context);
    final maxHeight = _aiChatMaxHeight(context);
    _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
    _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
    _aiChat = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: AiChatStream(
            key: aiChatKey,
            initialMessage: null,
            sendImmediate: false,
            quickPromptChips: _getAiQuickPromptChips(),
            trailing: _buildAiChatTrailing(context),
          ),
        ),
      ],
    );
  }

  List<AiQuickPromptChip> _getAiQuickPromptChips() {
    // 按「读前 → 读中 → 读后」排序，强化深读闭环，而不是一堆平铺入口。
    return [
      AiQuickPromptChip(
        icon: SongJiangIcons.aiPreview,
        label: L10n.of(context).settingsAiPromptChapterPreview,
        prompt: generatePromptChapterPreview().buildString(),
      ),
      AiQuickPromptChip(
        icon: SongJiangIcons.aiQuiz,
        label: L10n.of(context).settingsAiPromptChapterQuiz,
        prompt: generatePromptChapterQuiz().buildString(),
      ),
      AiQuickPromptChip(
        icon: SongJiangIcons.aiRecap,
        label: L10n.of(context).settingsAiPromptChapterRecap,
        prompt: generatePromptChapterRecap().buildString(),
      ),
      AiQuickPromptChip(
        icon: SongJiangIcons.aiChapter,
        label: L10n.of(context).settingsAiPromptSummaryTheChapter,
        prompt: generatePromptSummaryTheChapter().buildString(),
      ),
      AiQuickPromptChip(
        icon: SongJiangIcons.aiMindmap,
        label: L10n.of(context).settingsAiPromptMindmap,
        prompt: generatePromptMindmap().buildString(),
      ),
      AiQuickPromptChip(
        icon: SongJiangIcons.aiBook,
        label: L10n.of(context).settingsAiPromptSummaryTheBook,
        prompt: generatePromptSummaryTheBook().buildString(),
      ),
      // User custom prompts (enabled only)
      ...AiPrefs.userPrompts
          .where((p) => p.enabled)
          .map((userPrompt) => AiQuickPromptChip(
                icon: Icons.person_outline,
                label: userPrompt.name,
                prompt: userPrompt.content,
              )),
    ];
  }

  Future<void> showAiChat({
    String? content,
    bool sendImmediate = false,
  }) async {
    List<AiQuickPromptChip> quickPrompts = _getAiQuickPromptChips();

    // Determine display mode
    final displayMode = AiPrefs.aiChatDisplayMode;
    final screenWidth = MediaQuery.of(navigatorKey.currentContext!).size.width;

    bool shouldShowAsPopup = false;

    switch (displayMode) {
      case AiChatDisplayMode.adaptive:
        // Show as popup if width < 600
        shouldShowAsPopup = screenWidth < 600;
        break;
      case AiChatDisplayMode.popup:
        // Always show as popup
        shouldShowAsPopup = true;
        break;
      case AiChatDisplayMode.split:
        // Always show as split screen
        shouldShowAsPopup = false;
        break;
    }

    if (shouldShowAsPopup) {
      showModalBottomSheet(
          context: navigatorKey.currentContext!,
          isScrollControlled: true,
          showDragHandle: false,
          clipBehavior: Clip.hardEdge,
          // 用主题 surface 色，避免默认黑色遮罩造成割裂感
          backgroundColor: Theme.of(navigatorKey.currentContext!).colorScheme.surface,
          builder: (context) => PointerInterceptor(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: AiChatStream(
                      key: aiChatKey,
                      initialMessage: content,
                      sendImmediate: sendImmediate,
                      quickPromptChips: quickPrompts,
                    ),
                  ),
                ),
              ));
    } else {
      setState(() {
        final maxWidth = _aiChatMaxWidth(navigatorKey.currentContext!);
        final maxHeight = _aiChatMaxHeight(navigatorKey.currentContext!);
        _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
        _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
        _aiChat = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AiChatStream(
                key: aiChatKey,
                initialMessage: content,
                sendImmediate: sendImmediate,
                quickPromptChips: quickPrompts,
                trailing: _buildAiChatTrailing(navigatorKey.currentContext!),
              ),
            ),
          ],
        );
      });
    }
  }

  void updateState() {
    if (mounted) {
      setState(() {
        bookmarkExists = epubPlayerKey.currentState!.bookmarkExists;
      });
    }
  }

  /// 右下角「A↑ / 听」是否显示。
  ///
  /// 微信读书在目录、笔记这两个大面板里会收起它们，只留底栏。
  bool get _showsFloatActions {
    if (_overridePage != null) return false;
    switch (_activeTool) {
      case null:
      case SjReaderTool.progress:
      case SjReaderTool.appearance:
      case SjReaderTool.typography:
        return true;
      case SjReaderTool.toc:
      case SjReaderTool.notes:
        return false;
    }
  }

  /// 高面板（目录 / 笔记）的高度。
  ///
  /// 顶栏 + 底栏 + 浮动按钮都在同一列里，短屏（640 高）上直接用 86% 会顶出屏幕，
  /// 所以按「屏幕高 - 顶栏 - 底栏 - 状态栏」再夹一次。
  double _panelHeight(double fraction) {
    final media = MediaQuery.of(context);
    final available = media.size.height -
        SjReaderSize.topBar -
        SjReaderSize.bottomBar -
        media.padding.top -
        20;
    return math.min(media.size.height * fraction, available);
  }

  /// 按当前工具位现算面板内容（主题改动后面板颜色能立刻跟上）。
  Widget? _buildReaderPanel(SjReaderPalette palette) {
    if (_overridePage != null) {
      return SizedBox(
        height: _panelHeight(0.62),
        child: SjReaderSheet(
          palette: palette,
          expand: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: _overridePage!,
        ),
      );
    }

    switch (_activeTool) {
      case SjReaderTool.toc:
        return SizedBox(
          height: _panelHeight(0.86),
          child: SjTocSheet(
            palette: palette,
            book: _book,
            epubPlayerKey: epubPlayerKey,
            onClose: () => showOrHideAppBarAndBottomBar(false),
          ),
        );
      case SjReaderTool.notes:
        return SizedBox(
          height: _panelHeight(0.80),
          child: SjNotesSheet(
            palette: palette,
            book: _book,
            epubPlayerKey: epubPlayerKey,
            onClose: () => showOrHideAppBarAndBottomBar(false),
            onBookDetail: _openBookDetail,
          ),
        );
      case SjReaderTool.progress:
        return SjProgressSheet(
          palette: palette,
          book: _book,
          epubPlayerKey: epubPlayerKey,
          onBookDetail: _openBookDetail,
        );
      case SjReaderTool.appearance:
        return SjAppearanceSheet(
          palette: palette,
          epubPlayerKey: epubPlayerKey,
          onBrightnessChanged: (double value) {
            setState(() => _brightness = value);
          },
          onThemeChanged: () => setState(() {}),
          onOpenBgImage: () {
            setState(() {
              _activeTool = SjReaderTool.appearance;
              _overridePage = const BgimgSelector();
            });
          },
        );
      case SjReaderTool.typography:
        return SjTypographySheet(
          palette: palette,
          epubPlayerKey: epubPlayerKey,
          onOpenMoreSettings: styleHandler,
          // 面板里的纸张圆点改了主题，调色板得跟着重建。
          onThemeChanged: () => setState(() {}),
        );
      case null:
        return null;
    }
  }

  /// 打开 AI 助手（沿用原来的分屏 / 弹窗判定）。
  void _openAiChat() {
    final displayMode = AiPrefs.aiChatDisplayMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final shouldShowAsSplit = switch (displayMode) {
      AiChatDisplayMode.adaptive => screenWidth >= 600,
      AiChatDisplayMode.split => true,
      AiChatDisplayMode.popup => false,
    };
    if (shouldShowAsSplit && _aiChat != null) {
      setState(() => _aiChat = null);
      return;
    }
    showOrHideAppBarAndBottomBar(false);
    showAiChat();
  }

  /// 顶栏「更多」：AI 助手 / 书签 / 书籍详情 / 完整排版设置。
  Future<void> _showReaderMoreMenu() async {
    final palette = _palette;
    final screen = MediaQuery.of(context).size;
    final selected = await showMenu<String>(
      context: context,
      color: palette.surface,
      position: RelativeRect.fromLTRB(screen.width - 52, 96, 8, 0),
      items: <PopupMenuEntry<String>>[
        if (EnvVar.enableAIFeature)
          _readerMenuItem('ai', Icons.auto_awesome_rounded, 'AI 助手', palette),
        _readerMenuItem(
          'bookmark',
          bookmarkExists ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          bookmarkExists ? L10n.of(context).readingPageBookmark : '添加书签',
          palette,
        ),
        _readerMenuItem('copy', Icons.copy_rounded, '复制本章', palette),
        _readerMenuItem('detail', Icons.info_outline_rounded, '书籍详情', palette),
        _readerMenuItem('settings', Icons.tune_rounded, '完整排版设置', palette),
      ],
    );

    switch (selected) {
      case 'ai':
        _openAiChat();
      case 'bookmark':
        if (bookmarkExists) {
          epubPlayerKey.currentState!.removeAnnotation(
            epubPlayerKey.currentState!.bookmarkCfi,
          );
        } else {
          epubPlayerKey.currentState!.addBookmarkHere();
        }
        updateState();
      case 'copy':
        await _copyChapter();
      case 'detail':
        _openBookDetail();
      case 'settings':
        await styleHandler();
    }
  }

  PopupMenuItem<String> _readerMenuItem(
    String value,
    IconData icon,
    String label,
    SjReaderPalette palette,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: palette.subForeground),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 14, color: palette.foreground)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final panel = _buildReaderPanel(palette);

    Offstage controller = Offstage(
      offstage: bottomBarOffstage,
      child: PointerInterceptor(
        child: Stack(
          children: [
            // 微信读书的工具栏浮在正文上，不压暗纸张，只有一层可点击的透明层
            Positioned.fill(
              child: GestureDetector(
                  onTap: () {
                    showOrHideAppBarAndBottomBar(false);
                  },
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {},
                  onVerticalDragEnd: (details) {},
                  child: const SizedBox.expand()),
            ),
            Column(
              children: [
                // 状态栏区域也用纸色铺满，避免文字从顶栏上方透出来
                ColoredBox(
                  color: palette.background,
                  child: SafeArea(
                    bottom: false,
                    child: SjReaderTopBar(
                      palette: palette,
                      onBack: () => Navigator.pop(context),
                      onToc: tocHandler,
                      onShare: _copyChapter,
                      onMore: _showReaderMoreMenu,
                    ),
                  ),
                ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // A↑ / 听 浮在面板之上（微信读书把它们压在工具栏上方）
                      if (_showsFloatActions)
                        Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 10),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: SjReaderFloatActions(
                              palette: palette,
                              onTypography: typographyHandler,
                              onListen: ttsHandler,
                            ),
                          ),
                        ),
                      if (panel != null) panel,
                      Container(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          border: Border(
                            top: BorderSide(color: palette.divider, width: 0.8),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: SjReaderBottomBar(
                            palette: palette,
                            active: _activeTool,
                            onSelected: _openTool,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      // 与阅读主题同底，透明 WebView 边缘不透出主题灰造成割裂
      backgroundColor: Color(int.parse('0x${AppMiscPrefs.readTheme.backgroundColor}')),
      body: Hero(
        tag: widget.heroTag ??
            (BookshelfPrefs.openBookAnimation ? _book.coverFullPath : heroTag),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: Scaffold(
              key: _scaffoldKey,
              resizeToAvoidBottomInset: false,
              // 与外层 Scaffold 同底色，消除安全区与内容区的割裂感
              backgroundColor: Color(int.parse('0x${AppMiscPrefs.readTheme.backgroundColor}')),
              body: Stack(
                children: [
                  AxisFlex(
                    axis: AiPrefs.aiPanelPosition == AiPanelPositionEnum.right
                        ? Axis.horizontal
                        : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: MouseRegion(
                          onHover: (PointerHoverEvent detail) {
                            if (!ReadingUiPrefs.showMenuOnHover) return;
                            var y = detail.position.dy;
                            if (y < 30 ||
                                y > MediaQuery.of(context).size.height - 30) {
                              showOrHideAppBarAndBottomBar(true);
                            }
                          },
                          child: Focus(
                            focusNode: _readerFocusNode,
                            onKeyEvent: _handleReaderKeyEvent,
                            child: Stack(
                              children: [
                                // 安全区由 WebView 内部 topMargin/bottomMargin 处理
                                // （generateUrl 传入 viewPadding），外层不再重复 Padding，
                                // 避免安全区被双重计算导致上下留空过多。
                                EpubPlayer(
                                  key: epubPlayerKey,
                                  book: _book,
                                  cfi: widget.cfi,
                                  showOrHideAppBarAndBottomBar:
                                      showOrHideAppBarAndBottomBar,
                                  onLoadEnd: onLoadEnd,
                                  initialThemes: widget.initialThemes,
                                  updateParent: updateState,
                                ),
                                if (_isResizingAiChat)
                                  SizedBox.expand(
                                    child: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withAlpha(1),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_aiChat != null)
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? (details) {
                                  _beginAiChatResize(details.globalPosition.dx);
                                }
                              : null,
                          onHorizontalDragUpdate: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? (details) {
                                  _applyAiChatResizeDelta(
                                    details.delta.dx,
                                    context,
                                  );
                                }
                              : null,
                          onHorizontalDragEnd: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? (_) {
                                  _endAiChatResize();
                                }
                              : null,
                          onHorizontalDragCancel: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? () {
                                  _endAiChatResize();
                                }
                              : null,
                          onVerticalDragStart: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? (details) {
                                  _beginAiChatResizeVertical(
                                      details.globalPosition.dy);
                                }
                              : null,
                          onVerticalDragUpdate: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? (details) {
                                  _applyAiChatResizeDeltaVertical(
                                    details.delta.dy,
                                    context,
                                  );
                                }
                              : null,
                          onVerticalDragEnd: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? (_) {
                                  _endAiChatResize();
                                }
                              : null,
                          onVerticalDragCancel: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? () {
                                  _endAiChatResize();
                                }
                              : null,
                          child: MouseRegion(
                            cursor: AiPrefs.aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? SystemMouseCursors.resizeColumn
                                : SystemMouseCursors.resizeRow,
                            child: AiPrefs.aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? VerticalDivider(
                                    width: 2,
                                    thickness: 1,
                                  )
                                : Divider(
                                    height: 2,
                                    thickness: 1,
                                  ),
                          ),
                        ),
                      if (_aiChat != null)
                        SizedBox(
                          key: const ValueKey('ai-chat-panel'),
                          width: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? _aiChatWidth
                              : null,
                          height: AiPrefs.aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? _aiChatHeight
                              : null,
                          child: _aiChat,
                        )
                    ],
                  ),
                  // 亮度遮罩：只压正文，不压工具栏（微信读书同款）
                  if (_brightness < 0.99)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: Colors.black.withValues(
                            alpha: (1 - _brightness).clamp(0.0, 0.85),
                          ),
                        ),
                      ),
                    ),
                  controller,
                  // TTS floating action button: always in the tree when toolbar
                  // is hidden; TtsFab handles its own show/hide internally so
                  // its State (expanded flag) is never destroyed mid-session.
                  if (bottomBarOffstage)
                    const Positioned(
                      right: 16,
                      bottom: 24,
                      child: TtsFab(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
