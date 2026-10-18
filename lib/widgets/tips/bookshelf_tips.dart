import 'package:flutter/material.dart';

import 'package:songjiang_reader/design/songjiang/sj_icon.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/widgets/tips/sj_empty_tip.dart';

/// 书架空态：品牌插画 + 标题 + 副标题。
///
/// 版式统一由 [SjEmptyTip] 提供。书架是最该给出口的空态
/// （用户来这里就是为了加书），调用方可传 [action] 放「导入」。
class BookshelfTips extends StatelessWidget {
  const BookshelfTips({super.key, this.action});

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SjEmptyTip(
      illustration: SjIllustration.emptyShelf,
      title: L10n.of(context).bookshelfTips_1,
      message: L10n.of(context).bookshelfTips_2,
      action: action,
    );
  }
}
