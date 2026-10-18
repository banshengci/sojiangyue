import 'package:flutter/material.dart';

import 'package:songjiang_reader/design/songjiang/sj_icon.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/widgets/tips/sj_empty_tip.dart';

/// 统计空态：品牌插画 + 标题 + 副标题。
///
/// 版式统一由 [SjEmptyTip] 提供。
class StatisticsTips extends StatelessWidget {
  const StatisticsTips({super.key, this.action});

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SjEmptyTip(
      illustration: SjIllustration.noResults,
      title: L10n.of(context).statisticsTips_1,
      message: L10n.of(context).statisticsTips_2,
      action: action,
    );
  }
}
