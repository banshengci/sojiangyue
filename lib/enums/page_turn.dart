/// 翻页方式。
///
/// 从 `lib/widgets/reading_page/style_widget.dart` 下沉到 `lib/enums/`。
/// 动机：`lib/config/reading_style_prefs.dart` 需要读写该类型，而 config 反向
/// 依赖 widgets 会形成 `config <-> widgets` 环，并把 UI 层拖进配置层。
/// 下沉后 config 只依赖 enums；`style_widget.dart` 原样 re-export，
/// 其余使用方（epub_player.dart 等）无需改动。
/// 行为无变化：枚举值、顺序与 `getLabel` 实现逐字保持（仅补上本文件所需的
/// `L10n` / `material` import，与 `lib/enums/reading_info.dart` 等既有枚举文件同款）。
library;

import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

enum PageTurn {
  noAnimation,
  slide,
  scroll;

  String getLabel(BuildContext context) {
    switch (this) {
      case PageTurn.noAnimation:
        return L10n.of(context).noAnimation;
      case PageTurn.slide:
        return L10n.of(context).slide;
      case PageTurn.scroll:
        return L10n.of(context).scroll;
    }
  }
}
