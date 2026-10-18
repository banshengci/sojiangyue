import 'package:flutter/material.dart';

import 'package:songjiang_reader/design/songjiang/sj_icon.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/widgets/tips/sj_empty_tip.dart';

/// 笔记空态：品牌插画 + 标题 + 副标题。
///
/// 版式统一由 [SjEmptyTip] 提供（此前与书架/统计两处是逐字重复的三份代码）。
class NotesTips extends StatelessWidget {
  const NotesTips({super.key, this.action});

  /// 可选出口（例如「去书架挑一本」）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SjEmptyTip(
      illustration: SjIllustration.noNotes,
      title: L10n.of(context).notesTips_1,
      message: L10n.of(context).notesTips_2,
      action: action,
    );
  }
}
