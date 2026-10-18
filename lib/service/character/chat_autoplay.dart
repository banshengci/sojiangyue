// lib/service/character/chat_autoplay.dart
//
// 自动连播的续播判断。
//
// 单独抽出来是因为这是**唯一**决定"要不要再花一次钱"的地方：
// 条件写松了会无限烧 token，写紧了连播点不动。
// 放在页面里就没法测（页面要 DB、模型、Provider 一整套）。

/// 是否继续下一幕。
///
/// [turns] 已经播过的幕数，[limit] 上限；[hasError] 出错后必须停，
/// 否则会带着坏状态一直重试。
bool shouldContinueAutoPlay({
  required bool autoPlay,
  required int turns,
  required int limit,
  required bool hasError,
}) =>
    autoPlay && !hasError && turns < limit;

/// 连播时两幕之间的间隔。
///
/// 给用户一个能按到「停止」的窗口，也避免请求打得太密被服务端限流。
const Duration autoPlayGap = Duration(milliseconds: 400);
