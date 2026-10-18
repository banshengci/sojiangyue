import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/design/songjiang/sj_progress_ring.dart';
import 'package:songjiang_reader/design/songjiang/sj_reader_toolbar.dart';
import 'package:songjiang_reader/design/songjiang/sj_selection_bar.dart';
import 'package:songjiang_reader/design/songjiang/sj_segmented.dart';
import 'package:songjiang_reader/design/songjiang/sj_tap_target.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';

/// v3 新增组件的护栏测试。
///
/// 这些组件不依赖 L10n（项目用的是 deferred loading，widget 测试里加载不完），
/// 也不依赖数据库，因此可以直接渲染验证。
///
/// 重点验证两件在评审里被点名的硬约束：
///  1. 触控目标 ≥44×44
///  2. 阅读底栏 ≤5 项、选中浮条首行 ≤4 项（写成 assert）
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  group('SjTapTarget', () {
    testWidgets('默认热区为 44×44', (tester) async {
      await tester.pumpWidget(host(
        SjTapTarget(
          semanticLabel: '返回',
          onTap: () {},
          child: const Icon(Icons.chevron_left, size: 18),
        ),
      ));
      final size = tester.getSize(find.byType(SjTapTarget));
      expect(size.width, SjSizes.minTouchTarget);
      expect(size.height, SjSizes.minTouchTarget);
    });

    testWidgets('视觉内容小于热区时被居中，热区不变', (tester) async {
      await tester.pumpWidget(host(
        SjTapTarget(
          onTap: () {},
          child: Container(
            key: const ValueKey('dot'),
            width: 18,
            height: 18,
            color: const Color(0xFF2E6B4F),
          ),
        ),
      ));
      final outer = tester.getSize(find.byType(SjTapTarget));
      final inner = tester.getSize(find.byKey(const ValueKey('dot')));
      expect(outer.width, SjSizes.minTouchTarget);
      expect(inner.width, 18);
    });
  });

  group('SjSegmented', () {
    testWidgets('每项高度不低于 44', (tester) async {
      var index = 0;
      await tester.pumpWidget(host(
        SjSegmented(
          labels: const ['全部', '在读', '已读'],
          selectedIndex: index,
          onChanged: (i) => index = i,
        ),
      ));
      for (final label in ['全部', '在读', '已读']) {
        final size = tester.getSize(find.text(label));
        expect(size.height, greaterThan(0));
      }
      // 整组高度 = 3px padding*2 + 项高（≥44-6=38）→ 至少 44
      final total = tester.getSize(find.byType(SjSegmented));
      expect(total.height, greaterThanOrEqualTo(SjSizes.minTouchTarget));
    });

    testWidgets('点击可切换选中项', (tester) async {
      var index = 0;
      await tester.pumpWidget(host(
        StatefulBuilder(
          builder: (context, setState) => SjSegmented(
            labels: const ['全部', '在读'],
            selectedIndex: index,
            onChanged: (i) => setState(() => index = i),
          ),
        ),
      ));
      expect(index, 0);
      await tester.tap(find.text('在读'));
      await tester.pumpAndSettle();
      expect(index, 1);
    });
  });

  group('SjReaderToolbar', () {
    const item = SjReaderToolItem(icon: Icons.toc, label: '目录');

    testWidgets('5 项可正常渲染，且每项 ≥44 高', (tester) async {
      await tester.pumpWidget(host(
        SjReaderToolbar(
          items: List<SjReaderToolItem>.filled(5, item),
          selectedIndex: -1,
          onTap: (_) {},
          showSafeArea: false,
        ),
      ));
      expect(find.text('目录'), findsNWidgets(5));
      final size = tester.getSize(find.byType(SjReaderToolbar));
      expect(size.height, greaterThanOrEqualTo(SjSizes.minTouchTarget));
    });

    test('超过 5 项直接抛断言（评审要求：底栏 ≤5）', () {
      expect(
        () => SjReaderToolbar(
          items: List<SjReaderToolItem>.filled(6, item),
          selectedIndex: 0,
          onTap: (_) {},
        ),
        throwsAssertionError,
      );
    });
  });

  group('SjSelectionBar', () {
    final actions = <SjSelectionAction>[
      SjSelectionAction(icon: Icons.brush, label: '高亮'),
      SjSelectionAction(icon: Icons.format_underline, label: '划线'),
      SjSelectionAction(icon: Icons.edit_note, label: '批注'),
      SjSelectionAction(icon: Icons.copy, label: '复制'),
    ];

    testWidgets('4 项 + 更多可渲染', (tester) async {
      await tester.pumpWidget(host(
        SjSelectionBar(actions: actions, onMore: () {}),
      ));
      expect(find.text('高亮'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('更多'), findsOneWidget);
    });

    test('超过 4 项直接抛断言（评审要求：浮条首行 ≤4）', () {
      expect(
        () => SjSelectionBar(
          actions: [...actions, actions.first],
          onMore: () {},
        ),
        throwsAssertionError,
      );
    });
  });

  group('SjProgressRing', () {
    testWidgets('0 与 1 都不抛异常', (tester) async {
      await tester.pumpWidget(host(const SjProgressRing(progress: 0)));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(host(const SjProgressRing(progress: 1)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('越界值被 clamp，不抛异常', (tester) async {
      await tester.pumpWidget(host(const SjProgressRing(progress: 1.8)));
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(SjProgressRing));
      expect(size.width, 28);
    });
  });
}
