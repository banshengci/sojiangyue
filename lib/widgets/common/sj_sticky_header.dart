// lib/widgets/common/sj_sticky_header.dart
//
// 吸顶头 + 内容的组合，缺滚动容器时自动降级为普通上下排列。
//
// 为什么要包一层：`sticky_headers` 的 `StickyHeader` 在 `createRenderObject`
// 里直接调 `Scrollable.of(context)!`——**没有滚动祖先时会抛异常**，
// 而且它抛在 element 半挂载阶段，最终报出来的是
// `LateInitializationError: Field '_children' has not been initialized`，
// 跟真实原因毫无关系，红屏上根本看不出是"少了一层滚动容器"。
//
// 阅读页的笔记面板就是这种情况：面板用的是普通 Column，没有 Scrollable，
// 一点「笔记」就整页红屏。这里先探测有没有滚动祖先，没有就直接排成 Column。

import 'package:flutter/material.dart';
import 'package:sticky_headers/sticky_headers.dart';

/// 有滚动容器时吸顶，没有时退化为普通的两段竖排。
class SjStickyHeader extends StatelessWidget {
  const SjStickyHeader({
    super.key,
    required this.header,
    required this.content,
    this.overlapHeaders = false,
  });

  final Widget header;
  final Widget content;
  final bool overlapHeaders;

  @override
  Widget build(BuildContext context) {
    // 关键判断：没有 Scrollable 就不能交给 StickyHeader
    if (Scrollable.maybeOf(context) == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[header, content],
      );
    }
    return StickyHeader(
      header: header,
      content: content,
      overlapHeaders: overlapHeaders,
    );
  }
}
