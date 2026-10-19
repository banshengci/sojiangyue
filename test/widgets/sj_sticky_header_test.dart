import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/widgets/common/sj_sticky_header.dart';

/// 吸顶头在「没有滚动容器」时不能炸。
///
/// 这条回归来自实机：阅读页点「笔记」，整块内容变成红屏，报的是
/// `LateInitializationError: Field '_children' has not been initialized`——
/// 真实原因是 `sticky_headers` 的 `StickyHeader` 在 createRenderObject 里
/// 直接 `Scrollable.of(context)!`，面板是普通 Column，没有滚动祖先。
///
/// 这个测试固定两件事：无滚动容器时退化成普通竖排；有滚动容器时仍然正常渲染。
void main() {
  Widget sheet({required bool scrollable}) {
    final header = const Text('头部');
    final content = const Column(
      children: [Text('内容一'), Text('内容二')],
    );
    return MaterialApp(
      home: Scaffold(
        body: scrollable
            ? ListView(
                children: [
                  SjStickyHeader(header: header, content: content),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SjStickyHeader(header: header, content: content),
                ],
              ),
      ),
    );
  }

  testWidgets('没有滚动容器时不抛异常，头部与内容都在', (tester) async {
    await tester.pumpWidget(sheet(scrollable: false));
    expect(tester.takeException(), isNull);
    expect(find.text('头部'), findsOneWidget);
    expect(find.text('内容一'), findsOneWidget);
    expect(find.text('内容二'), findsOneWidget);
  });

  testWidgets('有滚动容器时正常工作', (tester) async {
    await tester.pumpWidget(sheet(scrollable: true));
    expect(tester.takeException(), isNull);
    expect(find.text('头部'), findsOneWidget);
    expect(find.text('内容一'), findsOneWidget);
  });
}
