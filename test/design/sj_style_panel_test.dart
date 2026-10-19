import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_reader_tokens.dart';
import 'package:songjiang_reader/design/songjiang/reader/sj_style_panel.dart';
import 'package:songjiang_reader/enums/reading_info.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/reading_info.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';

/// 排版面板：页眉 / 页脚 / 标题三个入口，以及五档翻页动画能选。
///
/// 面板是「改了立刻生效」的界面，最容易坏在两层：
/// 一是行里塞不下（窄屏溢出红屏），二是选完了没落到 prefs 里
/// （用户以为设了，翻页却没变）。这两件都在这里钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ReadingStylePrefs.ensureInitialized();
    await ReadingUiPrefs.ensureInitialized();
    await Prefs().initPrefs();
  });

  Future<void> pumpPanel(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        // 面板里的「页眉 / 页脚 / 标题」是硬编码中文，翻页动画文案走 l10n；
        // 测试固定成中文，两边才对得上。
        locale: const Locale('zh'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SjStylePanel(
              palette: SjReaderPalette.paper,
              epubPlayerKey: GlobalKey<EpubPlayerState>(),
            ),
          ),
        ),
      ),
    );
    // 本地化 delegate 是异步加载的，首帧只有一个 SizedBox；
    // 不 settle 的话下面什么都找不到。
    await tester.pumpAndSettle();
  }

  testWidgets('三个新入口都在，五档翻页动画都能看到', (tester) async {
    await pumpPanel(tester);

    expect(find.text('页眉'), findsOneWidget);
    expect(find.text('页脚'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);

    expect(find.text('覆盖'), findsOneWidget);
    expect(find.text('仿真'), findsOneWidget);
    expect(find.text('滑动翻页'), findsOneWidget);
    expect(find.text('滚动翻页'), findsOneWidget);
    expect(find.text('无动画'), findsOneWidget);
  });

  testWidgets('窄屏也不溢出', (tester) async {
    for (final width in <double>[320, 360, 430]) {
      await pumpPanel(tester, width: width);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '宽度 $width 下排版面板溢出了',
      );
    }
  });

  testWidgets('页眉里选了「页码」，退出后真的落到了 prefs', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('页眉'));
    await tester.pumpAndSettle();

    // 三格的下拉都在
    expect(find.text('左'), findsOneWidget);
    expect(find.text('中'), findsOneWidget);
    expect(find.text('右'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<ReadingInfoEnum>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('页码').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(Prefs().readingInfo.header.left, ReadingInfoEnum.page);
  });

  testWidgets('点「清空」后三格都回到「无」', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('页脚'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final footer = Prefs().readingInfo.footer;
    expect(footer.left, ReadingInfoEnum.none);
    expect(footer.center, ReadingInfoEnum.none);
    expect(footer.right, ReadingInfoEnum.none);
    expect(footer.hasContent, isFalse, reason: '三格全空就不该再占正文边距');
  });

  testWidgets('选一档翻页动画会写进 prefs', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('仿真'));
    await tester.pumpAndSettle();

    expect(ReadingStylePrefs.pageTurnStyle.name, 'simulation');
  });
}
