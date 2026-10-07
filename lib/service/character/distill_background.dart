// lib/service/character/distill_background.dart
//
// 蒸馏任务的进程级持有者。
//
// 背景：蒸馏是长任务（实测一本 741 章的书要切片几十段、每段一次模型调用）。
// 如果订阅只挂在页面/对话框上，会有两个问题：
//   1) 用户关掉界面，任务就被连带取消——「后台运行」形同虚设；
//   2) 反过来，任务跑起来后**没有任何地方能停它**（用户点了两次就并发跑两个）。
//
// 所以这里用一个进程级持有者托住订阅，并给每个任务一个稳定 tag：
//   - 任务与 UI 生命周期解耦，页面怎么关都不影响；
//   - 任务中心可以据此列出「正在跑什么」，并逐个停止。

import 'dart:async';

import 'package:songjiang_reader/utils/log/common.dart';

class DistillBackground {
  DistillBackground._();

  /// tag 约定：`<kind>-<bookId>`，供任务中心回显与停止。
  static String charactersTag(int bookId) => 'characters-$bookId';

  static String knowledgeTag(int bookId) => 'knowledge-$bookId';

  static final Map<String, _RunningTask> _tasks = {};

  /// 当前后台任务数。
  static int get running => _tasks.length;

  static List<String> get runningTags => List.unmodifiable(_tasks.keys);

  static bool isRunning(String tag) => _tasks.containsKey(tag);

  /// 接管一条蒸馏流。
  ///
  /// - [onEvent] / [onError]：把进度转发给 UI（可为 null）。
  /// - [onDone]：任务自然结束。
  /// - [onCanceled]：用户主动停止时回调（调用方可据此把任务标记为「已取消」）。
  ///
  /// 同一 tag 重复调用会先取消上一个，避免并发跑同一本书的蒸馏。
  static void run(
    Stream<dynamic> stream, {
    required String tag,
    void Function(dynamic event)? onEvent,
    void Function(Object error)? onError,
    void Function()? onDone,
    void Function()? onCanceled,
  }) {
    final previous = _tasks.remove(tag);
    if (previous != null) {
      previous.sub.cancel();
      SjLog.info('DistillBackground[$tag]: 覆盖了上一个同名任务');
    }

    late StreamSubscription<dynamic> sub;
    sub = stream.listen(
      (event) => onEvent?.call(event),
      onError: (Object e, StackTrace s) {
        SjLog.warning('DistillBackground[$tag]: 任务出错: $e\n$s');
        onError?.call(e);
      },
      onDone: () {
        _tasks.remove(tag);
        SjLog.info('DistillBackground[$tag]: 任务结束（剩余 ${_tasks.length}）');
        onDone?.call();
      },
      cancelOnError: false,
    );
    _tasks[tag] = _RunningTask(sub, onCanceled);
    SjLog.info('DistillBackground[$tag]: 已接管（共 ${_tasks.length} 个）');
  }

  /// 停止指定任务，返回是否确实停到了一个。
  static Future<bool> cancel(String tag) async {
    final task = _tasks.remove(tag);
    if (task == null) return false;
    await task.sub.cancel();
    SjLog.info('DistillBackground[$tag]: 已停止（剩余 ${_tasks.length}）');
    task.onCanceled?.call();
    return true;
  }

  static Future<void> cancelAll() async {
    for (final tag in List<String>.of(_tasks.keys)) {
      await cancel(tag);
    }
  }
}

class _RunningTask {
  _RunningTask(this.sub, this.onCanceled);

  final StreamSubscription<dynamic> sub;
  final void Function()? onCanceled;
}
