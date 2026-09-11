import 'package:flutter/material.dart';

import '../sj_badge.dart';
import '../sj_icon.dart';
import '../sj_tokens.dart';

/// 「空状态」页视觉（对应画板 08 · 页面三）。
///
/// 真实数据：书架为空时展示引导态；已有藏书时展示当前册数（空状态不再出现）。
class SjEmptyStatePage extends StatelessWidget {
  const SjEmptyStatePage({
    super.key,
    required this.bookCount,
    this.onImport,
  });

  /// 书架藏书数（真实数据）。
  final int bookCount;

  /// 导入入口（书架为空时展示）。
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final isEmpty = bookCount <= 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(SjSpace.page, 12, SjSpace.page, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('书架', style: SjText.pageTitle(c.ink)),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SjIllustrationView(
                    SjIllustration.emptyShelf,
                    width: 240,
                  ),
                  const SizedBox(height: SjSpace.xl),
                  Text(
                    isEmpty ? '书架还空着' : '书架已有 $bookCount 本书',
                    style: SjText.coverTitle(c.ink).copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: SjSpace.s),
                  Text(
                    isEmpty ? '导入你的第一本书，开始专注阅读' : '空状态仅在书架为空时出现',
                    textAlign: TextAlign.center,
                    style: SjText.body(c.inkSoft),
                  ),
                  const SizedBox(height: SjSpace.xl),
                  if (isEmpty)
                    SjPrimaryButton(
                      label: '导入图书',
                      icon: Icons.add,
                      onTap: onImport,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
