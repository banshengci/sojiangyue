import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_chrome.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_controls.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_panels.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_surface.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';

/// 阅读页版式冒烟测试。
///
/// 阅读页最容易翻车的不是配色而是「高度约束」：
/// 面板里用了 `Expanded` / `ListView`，只要外层少给一层有界高度就会直接抛
/// RenderFlex 断言。这里按 `reading_page.dart` 的真实叠放顺序复刻一遍，
/// 在四种屏宽下把五种面板都渲染一次。
void main() {
  const chapter = SjReaderChapter(
    index: '第1章',
    title: '阴阳魔师',
    pageText: '2 / 18602',
    paragraphs: <String>[
      '引子',
      '“下面紧急插播一条新闻，我国著名的调酒大师、品酒大师李解冻先生，因其对美酒的执着，'
          '冒然品尝不久前刚刚出土的汉代美酒陷入昏迷后七十二小时医治无效去世。享年三十二岁。”',
    ],
  );

  const tocEntries = <SjTocEntry>[
    SjTocEntry(title: '扉页', pageText: '1'),
    SjTocEntry(title: '第1章 阴阳魔师', pageText: '2'),
    SjTocEntry(title: '第2章 烈焰焚情（上）', pageText: '5'),
  ];

  /// 与 reading_page 的 `_panelHeight` 同规则：按可用高度再夹一次。
  double panelHeight(SjReaderTool tool, double screenHeight, double topInset) {
    final fraction = switch (tool) {
      SjReaderTool.toc => 0.86,
      SjReaderTool.notes => 0.80,
      _ => 0.0,
    };
    final available =
        screenHeight - SjReaderSize.topBar - SjReaderSize.bottomBar - topInset - 20;
    return fraction * screenHeight < available
        ? fraction * screenHeight
        : available;
  }

  Widget panelFor(SjReaderTool tool, SjReaderPalette palette, double height) {
    switch (tool) {
      case SjReaderTool.toc:
        return SizedBox(
          height: height,
          child: SjReaderSheet(
            palette: palette,
            showHandle: true,
            expand: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: SjTocPanel(
              palette: palette,
              bookTitle: '酒神',
              entries: tocEntries,
              currentIndex: 1,
              onLocate: () {},
              onToggleMode: () {},
            ),
          ),
        );
      case SjReaderTool.notes:
        return SizedBox(
          height: height,
          child: SjReaderSheet(
            palette: palette,
            showHandle: true,
            expand: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SjNotesPanel(palette: palette, bookTitle: '酒神'),
          ),
        );
      case SjReaderTool.progress:
        return SjReaderSheet(
          palette: palette,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: SjProgressPanel(
            palette: palette,
            percent: 0.42,
            readingTimeText: '1分钟',
            noteCountText: '0条',
            onSeek: (_) {},
            onPrimary: () {},
            onSecondary: () {},
          ),
        );
      case SjReaderTool.appearance:
        return SjReaderSheet(
          palette: palette,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: SjAppearancePanel(
            palette: palette,
            brightness: 0.7,
            papers: SjReaderPaper.presets,
            selectedPaperId: SjReaderPaper.cream.id,
            onBrightness: (_) {},
            onPaperSelected: (_) {},
            backgrounds: const <SjReaderBackground>[
              SjReaderBackground(colors: <Color>[Colors.white, Colors.white]),
            ],
            onMoreBackgrounds: () {},
          ),
        );
      case SjReaderTool.typography:
        return SjReaderSheet(
          palette: palette,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: SjTypographyPanel(
            palette: palette,
            fontSize: 19,
            marginIndex: 1,
            lineHeightIndex: 1,
            onFontSize: (_) {},
            onMargin: (_) {},
            onLineHeight: (_) {},
            onFontFamily: () {},
            onIndent: () {},
            onPageTurn: () {},
          ),
        );
    }
  }

  /// 复刻 reading_page 的叠放：正文 → 顶栏 → 浮动按钮 → 面板 → 底栏。
  Widget harness(
    SjReaderPaper paper,
    SjReaderTool? tool,
    double height,
  ) {
    final palette = SjReaderPalette.fromTheme(
      paper.background,
      paper.foreground,
    );
    final showsFloats = tool == null ||
        tool == SjReaderTool.progress ||
        tool == SjReaderTool.appearance ||
        tool == SjReaderTool.typography;

    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: SjReaderSurface(
                palette: palette,
                chapter: chapter,
                showHint: false,
              ),
            ),
            Column(
              children: <Widget>[
                ColoredBox(
                  color: palette.background,
                  child: SafeArea(
                    bottom: false,
                    child: SjReaderTopBar(palette: palette),
                  ),
                ),
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (showsFloats)
                        Padding(
                          padding: const EdgeInsets.only(right: 16, bottom: 10),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: SjReaderFloatActions(palette: palette),
                          ),
                        ),
                      if (tool != null)
                        panelFor(
                          tool,
                          palette,
                          tool == SjReaderTool.toc || tool == SjReaderTool.notes
                              ? panelHeight(tool, height, 0)
                              : height,
                        ),
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
                            active: tool,
                            onSelected: (_) {},
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
  }

  const sizes = <Size>[
    Size(320, 640),
    Size(360, 780),
    Size(390, 844),
    Size(430, 932),
  ];

  for (final size in sizes) {
    group('${size.width.toInt()}×${size.height.toInt()}', () {
      testWidgets('五种面板都不溢出', (WidgetTester tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        for (final tool in SjReaderTool.values) {
          await tester.pumpWidget(harness(SjReaderPaper.cream, tool, size.height));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${tool.label} 面板在 ${size.width} 宽下布局异常',
          );
        }
      });

      testWidgets('收起面板时只有工具栏', (WidgetTester tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness(SjReaderPaper.cream, null, size.height));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SjReaderBottomBar), findsOneWidget);
        expect(find.byType(SjReaderFloatActions), findsOneWidget);
      });

      testWidgets('夜间纸张', (WidgetTester tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(harness(SjReaderPaper.night, null, size.height));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('底栏交互', () {
    testWidgets('点击工具位回调对应枚举', (WidgetTester tester) async {
      final palette = SjReaderPalette.fromTheme(
        SjReaderPaper.cream.background,
        SjReaderPaper.cream.foreground,
      );
      final tapped = <SjReaderTool>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                child: SjReaderBottomBar(
                  palette: palette,
                  onSelected: tapped.add,
                ),
              ),
            ),
          ),
        ),
      );

      for (final tool in SjReaderTool.values) {
        await tester.tap(find.byType(SjReaderToolIcon).at(tool.index));
        await tester.pump();
      }

      expect(tapped, SjReaderTool.values);
    });
  });

  group('调色板', () {
    test('纸张匹配与派生', () {
      expect(SjReaderPaper.match(SjReaderPaper.cream.background).id, 'cream');
      final dark = SjReaderPalette.fromTheme(
        SjReaderPaper.night.background,
        SjReaderPaper.night.foreground,
      );
      expect(dark.isDark, isTrue);
      // 深色纸上强调色要提亮，保证对比度
      expect(dark.accent.computeLuminance(),
          greaterThan(const Color(0xFF2E6B4F).computeLuminance()));
    });
  });
}
