/// 翻页方式。
///
/// 从 `lib/widgets/reading_page/style_widget.dart` 下沉到 `lib/enums/`。
/// 动机：`lib/config/reading_style_prefs.dart` 需要读写该类型，而 config 反向
/// 依赖 widgets 会形成 `config <-> widgets` 环，并把 UI 层拖进配置层。
/// 下沉后 config 只依赖 enums；`style_widget.dart` 原样 re-export，
/// 其余使用方（epub_player.dart 等）无需改动。
///
/// 五种方式与参考的阅读器（Legado）一致：覆盖 / 滑动 / 仿真 / 滚动 / 无动画。
/// - `slide` / `scroll` / `noAnimation` 由阅读引擎（foliate-js）直接实现；
/// - `cover` / `simulation` 引擎做不到（分页是一整张连续画布，没有「两页同时在场」
///   的图层），改由 Flutter 侧在翻页前抓一张当前页的截图盖在上面做过渡，
///   详见 `epub_player.dart` 的 `_animatedTurn`。
library;

import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

enum PageTurn {
  cover,
  slide,
  simulation,
  scroll,
  noAnimation;

  String getLabel(BuildContext context) {
    switch (this) {
      case PageTurn.cover:
        return L10n.of(context).pageTurnCover;
      case PageTurn.slide:
        return L10n.of(context).slide;
      case PageTurn.simulation:
        return L10n.of(context).pageTurnSimulation;
      case PageTurn.scroll:
        return L10n.of(context).scroll;
      case PageTurn.noAnimation:
        return L10n.of(context).noAnimation;
    }
  }

  /// 这一档是否由 Flutter 侧接管过渡（需要先抓截图）。
  bool get isFlutterDriven =>
      this == PageTurn.cover || this == PageTurn.simulation;
}
