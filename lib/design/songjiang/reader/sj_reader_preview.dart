/// 松江阅 · 小说阅读页（微信读书风格）设计预览
///
/// 独立入口，不依赖 App 初始化（不需要数据库 / 阅读器），
/// 用来逐屏校对阅读页、工具栏与五个面板的视觉：
///
/// ```bash
/// flutter run -t lib/design/songjiang/reader/sj_reader_preview.dart
/// ```
///
/// 两种用法：
///  - [SjReaderPreviewApp]：单屏交互预览，顶部切换七种状态与四种纸张，
///    点正文可收起 / 展开工具栏，点底栏图标可展开对应面板；
///  - [SjReaderGalleryPage]：七种状态并排铺开，用于整体比对
///    （`--dart-define=SJ_READER_GALLERY=true` 时作为启动页）。
library;

import 'package:flutter/material.dart';

import 'sj_reader_chrome.dart';
import 'sj_reader_controls.dart';
import 'sj_reader_panels.dart';
import 'sj_reader_surface.dart';
import 'sj_reader_tokens.dart';

/// 预览可切换的状态。
enum SjReaderDemoState {
  /// 纯阅读（工具栏收起）。
  reading('阅读'),

  /// 工具栏展开、无面板。
  chrome('工具栏'),

  /// 目录面板。
  toc('目录'),

  /// 笔记面板。
  notes('笔记'),

  /// 进度面板。
  progress('进度'),

  /// 亮度 / 颜色面板。
  appearance('亮度'),

  /// 字体面板。
  typography('字体');

  const SjReaderDemoState(this.label);

  /// 顶部切换器上的文案。
  final String label;
}

// ---------------------------------------------------------------------------
// 示例数据
// ---------------------------------------------------------------------------

/// 示例章节（取自《酒神》开篇）。
const SjReaderChapter _sampleChapter = SjReaderChapter(
  index: '第1章',
  title: '阴阳魔师',
  pageText: '2 / 18602',
  paragraphs: <String>[
    '引子',
    '“下面紧急插播一条新闻，我国著名的调酒大师、品酒大师李解冻先生，因其对美酒的执着，'
        '冒然品尝不久前刚刚出土的汉代美酒陷入昏迷后七十二小时医治无效去世。享年三十二岁。”',
    '“李解冻先生，是我国乃至全世界最为优秀的调酒、品酒大师，曾连续五次获得富达国际调酒师大赛冠军，'
        '国际调酒师联合会荣誉会长。李氏调酒法创始人。同时也是国际品酒师协会荣誉理事，'
        '全世界唯一一位国际六星皇钻奖章获得者，六感品酒法创始人。被誉为当今国际第一酒神。”',
  ],
);

const List<SjTocEntry> _sampleToc = <SjTocEntry>[
  SjTocEntry(title: '扉页', pageText: '1'),
  SjTocEntry(title: '第1章 阴阳魔师', pageText: '2'),
  SjTocEntry(title: '第2章 烈焰焚情（上）', pageText: '5'),
  SjTocEntry(title: '第3章 烈焰焚情（下）', pageText: '12'),
  SjTocEntry(title: '第4章 一代酒神（上）', pageText: '19'),
  SjTocEntry(title: '第5章 一代酒神（下）', pageText: '26'),
  SjTocEntry(title: '第6章 魔师阴阳冕（上）', pageText: '34'),
  SjTocEntry(title: '第7章 魔师阴阳冕（下）', pageText: '41'),
  SjTocEntry(title: '第8章 阴阳魔师（上）', pageText: '48'),
  SjTocEntry(title: '第9章 阴阳魔师（下）', pageText: '55'),
];

const List<SjReaderBackground> _sampleBackgrounds = <SjReaderBackground>[
  SjReaderBackground(colors: <Color>[Color(0xFFF4E6C8), Color(0xFFEED9B4)]),
  SjReaderBackground(colors: <Color>[Color(0xFFF7E9EC), Color(0xFFEFD6DC)]),
  SjReaderBackground(colors: <Color>[Color(0xFFF9D9B0), Color(0xFFF0BE8A)]),
  SjReaderBackground(colors: <Color>[Color(0xFFDCD3E6), Color(0xFFC6BAD8)]),
];

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

const bool _startWithGallery =
    bool.fromEnvironment('SJ_READER_GALLERY', defaultValue: false);

void main() => runApp(
      _startWithGallery
          ? const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: SjReaderGalleryPage(),
            )
          : const SjReaderPreviewApp(),
    );

/// 单屏交互预览。
class SjReaderPreviewApp extends StatelessWidget {
  const SjReaderPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '松江阅 · 阅读页预览',
      home: const _PreviewHome(),
    );
  }
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  SjReaderDemoState _state = SjReaderDemoState.chrome;
  int _paperIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _previewBackdrop,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      for (final state in SjReaderDemoState.values)
                        _PreviewChip(
                          label: state.label,
                          selected: _state == state,
                          onTap: () => setState(() => _state = state),
                        ),
                      _PreviewChip(
                        label: '全部',
                        selected: false,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SjReaderGalleryPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _PaperSwitcher(
                    index: _paperIndex,
                    onChanged: (int i) => setState(() => _paperIndex = i),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SjReaderPhoneDemo(
                    key: const ValueKey<String>('single'),
                    initialState: _state,
                    paperIndex: _paperIndex,
                    onStateChanged: (SjReaderDemoState state, int paperIndex) {
                      setState(() {
                        _state = state;
                        _paperIndex = paperIndex;
                      });
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 七种状态并排展示。
class SjReaderGalleryPage extends StatefulWidget {
  const SjReaderGalleryPage({super.key});

  @override
  State<SjReaderGalleryPage> createState() => _SjReaderGalleryPageState();
}

class _SjReaderGalleryPageState extends State<SjReaderGalleryPage> {
  int _paperIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _previewBackdrop,
      appBar: AppBar(
        backgroundColor: _previewBackdrop,
        foregroundColor: Colors.white,
        title: const Text('松江阅 · 阅读页全状态', style: TextStyle(fontSize: 15)),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _PaperSwitcher(
                index: _paperIndex,
                onChanged: (int i) => setState(() => _paperIndex = i),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: <Widget>[
                    for (final state in SjReaderDemoState.values)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SjReaderPhoneDemo(
                            initialState: state,
                            paperIndex: _paperIndex,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            state.label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9AA0A8),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const Color _previewBackdrop = Color(0xFF17181A);

// ---------------------------------------------------------------------------
// 单台「手机」
// ---------------------------------------------------------------------------

/// 一台手机尺寸的阅读页演示。
///
/// [onStateChanged] 为空时为静态展示（画廊用），否则可点击交互。
class SjReaderPhoneDemo extends StatefulWidget {
  const SjReaderPhoneDemo({
    super.key,
    required this.initialState,
    this.paperIndex = 1,
    this.onStateChanged,
  });

  /// 初始状态。
  final SjReaderDemoState initialState;

  /// 初始纸张下标。
  final int paperIndex;

  /// 状态变化回调（交互模式）。
  final void Function(SjReaderDemoState state, int paperIndex)? onStateChanged;

  @override
  State<SjReaderPhoneDemo> createState() => _SjReaderPhoneDemoState();
}

class _SjReaderPhoneDemoState extends State<SjReaderPhoneDemo> {
  static const double _phoneWidth = 390;
  static const double _phoneHeight = 780;

  late SjReaderDemoState _state = widget.initialState;
  late int _paperIndex = widget.paperIndex;
  double _fontSize = 19;
  double _brightness = 0.72;
  int _marginIndex = 1;
  int _lineHeightIndex = 1;
  bool _autoPage = false;

  @override
  void didUpdateWidget(covariant SjReaderPhoneDemo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialState != widget.initialState) {
      _state = widget.initialState;
    }
    if (oldWidget.paperIndex != widget.paperIndex) {
      _paperIndex = widget.paperIndex;
    }
  }

  SjReaderPaper get _paper => SjReaderPaper.presets[_paperIndex];

  SjReaderPalette get _palette => SjReaderPalette.from(
        background: _paper.background,
        foreground: _paper.foreground,
      );

  SjReaderTool? get _activeTool {
    switch (_state) {
      case SjReaderDemoState.toc:
        return SjReaderTool.toc;
      case SjReaderDemoState.notes:
        return SjReaderTool.notes;
      case SjReaderDemoState.progress:
        return SjReaderTool.progress;
      case SjReaderDemoState.appearance:
        return SjReaderTool.appearance;
      case SjReaderDemoState.typography:
        return SjReaderTool.typography;
      case SjReaderDemoState.reading:
      case SjReaderDemoState.chrome:
        return null;
    }
  }

  bool get _chromeVisible => _state != SjReaderDemoState.reading;

  /// 右下「A↑ / 听」是否显示：目录、笔记两个大面板里收起。
  bool get _showsFloatActions {
    switch (_state) {
      case SjReaderDemoState.reading:
      case SjReaderDemoState.toc:
      case SjReaderDemoState.notes:
        return false;
      case SjReaderDemoState.chrome:
      case SjReaderDemoState.progress:
      case SjReaderDemoState.appearance:
      case SjReaderDemoState.typography:
        return true;
    }
  }

  void _setState(SjReaderDemoState state) {
    setState(() => _state = state);
    widget.onStateChanged?.call(state, _paperIndex);
  }

  void _onToolSelected(SjReaderTool tool) {
    final target = switch (tool) {
      SjReaderTool.toc => SjReaderDemoState.toc,
      SjReaderTool.notes => SjReaderDemoState.notes,
      SjReaderTool.progress => SjReaderDemoState.progress,
      SjReaderTool.appearance => SjReaderDemoState.appearance,
      SjReaderTool.typography => SjReaderDemoState.typography,
    };
    _setState(_state == target ? SjReaderDemoState.chrome : target);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;

    return Container(
      width: _phoneWidth,
      height: _phoneHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(38),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _setState(
                  _chromeVisible
                      ? SjReaderDemoState.reading
                      : SjReaderDemoState.chrome,
                ),
                child: SjReaderSurface(
                  palette: palette,
                  chapter: _sampleChapter,
                  fontSize: _fontSize,
                  showHint: !_chromeVisible,
                  topPadding: _chromeVisible ? 100 : 30,
                ),
              ),
            ),
            if (_chromeVisible) ...<Widget>[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  children: <Widget>[
                    _StatusBarMock(palette: palette),
                    SjReaderTopBar(
                      palette: palette,
                      onBack: () => _setState(SjReaderDemoState.reading),
                      onToc: () => _setState(SjReaderDemoState.toc),
                      onShare: () {},
                      onMore: () {},
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_showsFloatActions)
                      Padding(
                        padding: const EdgeInsets.only(right: 16, bottom: 10),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SjReaderFloatActions(
                            palette: palette,
                            onTypography: () =>
                                _setState(SjReaderDemoState.typography),
                            onListen: () {},
                          ),
                        ),
                      ),
                    if (_panel(palette) != null) _panel(palette)!,
                    Container(
                      color: palette.surface,
                      child: SafeArea(
                        top: false,
                        child: SjReaderBottomBar(
                          palette: palette,
                          active: _activeTool,
                          onSelected: _onToolSelected,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _panel(SjReaderPalette palette) {
    switch (_state) {
      case SjReaderDemoState.toc:
        return _sheet(
          palette,
          showHandle: true,
          height: 671,
          child: SjTocPanel(
            palette: palette,
            bookTitle: '酒神',
            entries: _sampleToc,
            currentIndex: 1,
            onLocate: () {},
            onToggleMode: () {},
          ),
        );
      case SjReaderDemoState.notes:
        return _sheet(
          palette,
          showHandle: true,
          height: 624,
          child: SjNotesPanel(
            palette: palette,
            bookTitle: '酒神',
            cover: Container(color: palette.accentSoft),
            onSeeAllNotes: () {},
          ),
        );
      case SjReaderDemoState.progress:
        return _sheet(
          palette,
          height: 208,
          child: SjProgressPanel(
            palette: palette,
            percent: 0.01,
            readingTimeText: '1分钟',
            noteCountText: '0条',
            secondaryActive: _autoPage,
            onSeek: (_) {},
            onPrimary: () {},
            onSecondary: () => setState(() => _autoPage = !_autoPage),
          ),
        );
      case SjReaderDemoState.appearance:
        return _sheet(
          palette,
          height: 232,
          child: SjAppearancePanel(
            palette: palette,
            brightness: _brightness,
            papers: SjReaderPaper.presets,
            selectedPaperId: _paper.id,
            onBrightness: (double v) => setState(() => _brightness = v),
            onPaperSelected: (SjReaderPaper paper) {
              final index = SjReaderPaper.presets.indexOf(paper);
              setState(() => _paperIndex = index);
              widget.onStateChanged?.call(_state, index);
            },
            backgrounds: _sampleBackgrounds,
            onBackgroundSelected: (_) {},
            onMoreBackgrounds: () {},
          ),
        );
      case SjReaderDemoState.typography:
        return _sheet(
          palette,
          height: 222,
          child: SjTypographyPanel(
            palette: palette,
            fontSize: _fontSize,
            marginIndex: _marginIndex,
            lineHeightIndex: _lineHeightIndex,
            onFontSize: (double v) => setState(() => _fontSize = v),
            onMargin: (int i) => setState(() => _marginIndex = i),
            onLineHeight: (int i) => setState(() => _lineHeightIndex = i),
            onFontFamily: () {},
            onIndent: () {},
            onPageTurn: () {},
          ),
        );
      case SjReaderDemoState.reading:
      case SjReaderDemoState.chrome:
        return null;
    }
  }

  Widget _sheet(
    SjReaderPalette palette, {
    required Widget child,
    bool showHandle = false,
    double? height,
  }) {
    final content = SjReaderSheet(
      palette: palette,
      showHandle: showHandle,
      expand: height != null,
      padding: EdgeInsets.fromLTRB(16, showHandle ? 2 : 14, 16, 14),
      child: child,
    );
    if (height == null) return content;
    return SizedBox(height: height, child: content);
  }
}

// ---------------------------------------------------------------------------
// 预览外壳小部件
// ---------------------------------------------------------------------------

class _StatusBarMock extends StatelessWidget {
  const _StatusBarMock({required this.palette});

  final SjReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = palette.foreground.withValues(alpha: 0.85);
    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: <Widget>[
            Text(
              '18:16',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.signal_cellular_alt_rounded, size: 14, color: color),
            const SizedBox(width: 5),
            Icon(Icons.wifi_rounded, size: 14, color: color),
            const SizedBox(width: 5),
            Icon(Icons.battery_5_bar_rounded, size: 15, color: color),
          ],
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2E6B4F) : const Color(0xFF2A2B2E),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF59A17D) : const Color(0xFF3A3C40),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : const Color(0xFFB9BDC4),
          ),
        ),
      ),
    );
  }
}

class _PaperSwitcher extends StatelessWidget {
  const _PaperSwitcher({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (var i = 0; i < SjReaderPaper.presets.length; i++)
          _PreviewChip(
            label: SjReaderPaper.presets[i].label,
            selected: index == i,
            onTap: () => onChanged(i),
          ),
      ],
    );
  }
}
