import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/data/sj_view_models.dart';
import 'package:songjiang_reader/design/songjiang/pages/sj_mine_page.dart';
import 'package:songjiang_reader/design/songjiang/sj_bottom_nav.dart';
import 'package:songjiang_reader/design/songjiang/sj_icon.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/widgets/tips/sj_empty_tip.dart';

/// 空状态组件 + 底栏图标一致性的护栏。
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: child),
      );

  group('SjEmptyTip', () {
    testWidgets('渲染插画、标题、正文', (tester) async {
      await tester.pumpWidget(host(
        const SjEmptyTip(
          illustration: SjIllustration.emptyShelf,
          title: '书架空空如也',
          message: '导入一本 epub 开始阅读',
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SjIllustrationView), findsOneWidget);
      expect(find.text('书架空空如也'), findsOneWidget);
      expect(find.text('导入一本 epub 开始阅读'), findsOneWidget);
    });

    testWidgets('正文限宽 280（避免长句拉成一条）', (tester) async {
      await tester.pumpWidget(host(
        const SjEmptyTip(
          illustration: SjIllustration.noResults,
          title: '还没有数据',
          message: '读一本书之后这里就会有统计',
        ),
      ));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.text('读一本书之后这里就会有统计'));
      expect(size.width, lessThanOrEqualTo(280.5));
    });

    testWidgets('传了 action 就显示出口', (tester) async {
      await tester.pumpWidget(host(
        SjEmptyTip(
          illustration: SjIllustration.emptyShelf,
          title: '书架空空如也',
          message: '导入一本 epub 开始阅读',
          action: FilledButton(
            onPressed: () {},
            child: const Text('导入书籍'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('导入书籍'), findsOneWidget);
    });

    testWidgets('没传 action 时不留空位', (tester) async {
      await tester.pumpWidget(host(
        const SjEmptyTip(
          illustration: SjIllustration.noNotes,
          title: '还没有笔记',
          message: '阅读时划一段话试试',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('深色模式下也能渲染', (tester) async {
      await tester.pumpWidget(host(
        const SjEmptyTip(
          illustration: SjIllustration.noNotes,
          title: '还没有笔记',
          message: '阅读时划一段话试试',
        ),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('底栏图标一致性', () {
    const items = <SjNavItem>[
      SjNavItem(label: '书架', brand: SjIconName.bookshelf),
      SjNavItem(label: '笔记', brand: SjIconName.note),
      SjNavItem(label: '玩法', material: Icons.casino_outlined),
      SjNavItem(label: '我的', material: Icons.person_outline),
    ];

    testWidgets('4 个图标都是 20×20', (tester) async {
      await tester.pumpWidget(host(
        SjBottomNav(items: items, selectedIndex: 0, onTap: (_) {}),
      ));
      await tester.pumpAndSettle();

      // 品牌图标（SvgPicture 由 SjIcon 包裹）
      expect(find.byType(SjIcon), findsNWidgets(2));
      for (final e in find.byType(SjIcon).evaluate()) {
        final w = e.widget as SjIcon;
        expect(w.size, 20, reason: '品牌图标尺寸应为 20');
      }

      // Material 图标
      for (final e in find.byType(Icon).evaluate()) {
        final w = e.widget as Icon;
        expect(w.size, 20, reason: 'Material 图标尺寸应为 20');
      }
    });

    testWidgets('品牌与 Material 图标用同一个前景色（选中态一致）', (tester) async {
      await tester.pumpWidget(host(
        SjBottomNav(items: items, selectedIndex: 0, onTap: (_) {}),
      ));
      await tester.pumpAndSettle();

      final c = SjColors.light;
      // 选中项用 onPine，未选中用 inkSoft —— 两条分支必须同色系
      final icons = find.byType(Icon).evaluate().map((e) => e.widget as Icon);
      for (final icon in icons) {
        expect(
          icon.color,
          anyOf(c.onPine, c.inkSoft),
          reason: 'Material 图标颜色必须取自令牌，而不是硬编码',
        );
      }
    });

    testWidgets('选中项与未选中项可区分（颜色不同）', (tester) async {
      // 选中第 3 项（Material 图标），这样 Material 里既有选中也有未选中
      await tester.pumpWidget(host(
        SjBottomNav(items: items, selectedIndex: 2, onTap: (_) {}),
      ));
      await tester.pumpAndSettle();

      final colors = find
          .byType(Icon)
          .evaluate()
          .map((e) => (e.widget as Icon).color)
          .toSet();
      expect(colors.length, greaterThanOrEqualTo(2),
          reason: '选中与未选中必须有两种颜色');
    });
  });

  group('设计页可独立使用', () {
    testWidgets('SjMinePage 不依赖外层 Scaffold（自带 Material）', (tester) async {
      // 该页含 InkWell，早期直接当 home 用会抛「No Material widget found」
      await tester.pumpWidget(MaterialApp(
        home: SjMinePage(profile: SjGalleryData.sample.profile),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
