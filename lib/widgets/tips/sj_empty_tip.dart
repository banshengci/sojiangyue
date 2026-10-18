import 'package:flutter/material.dart';

import 'package:songjiang_reader/design/songjiang/sj_icon.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';

/// 空状态 / 无结果状态的统一骨架。
///
/// 原来 `NotesTips` / `BookshelfTips` / `StatisticsTips` 是**三份几乎逐字重复**的
/// 代码（插画 + 标题 + 副标题），而且用的是 `Theme.textTheme.titleLarge`，
/// 与新的设计令牌脱节：字号、行宽、间距都不受 [SjText] / [SjSpace] 约束。
///
/// 现在三处共用这一个组件：
///  - 字号走 [SjType]（标题 20，正文 16）
///  - 间距走 [SjSpace]（24 / 8）
///  - 颜色走 [SjColors]（ink / inkSoft，浅深色都达标）
///  - 正文限宽 280，避免长句在大屏上拉成一条
///  - 可选 [action]：空态给一个出口（如「导入书籍」），比纯文字更有用
class SjEmptyTip extends StatelessWidget {
  const SjEmptyTip({
    super.key,
    required this.illustration,
    required this.title,
    required this.message,
    this.action,
  });

  final SjIllustration illustration;
  final String title;
  final String message;

  /// 可选的主行动按钮。空状态没有出口是最常见的可用性问题。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SjSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SjIllustrationView(illustration, width: 200),
            const SizedBox(height: SjSpace.l),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SjText.cardTitle(c.ink),
            ),
            const SizedBox(height: SjSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: SjText.body(c.inkSoft),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: SjSpace.l),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
