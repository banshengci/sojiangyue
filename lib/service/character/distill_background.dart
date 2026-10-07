// lib/service/character/distill_background.dart
//
// 后台蒸馏任务持有者。
//
// 背景：蒸馏是个长任务（大书要几分钟、几十次模型调用）。如果订阅只挂在
// 页面/对话框上，用户点「后台运行」关掉对话框、或直接退出页面，async*
// 生成器会随订阅一起被取消——表现就是"点了后台，回来发现根本没跑"。
//
// 这里用一个进程级持有者托住订阅：任务与 UI 生命周期解耦，页面怎么关都不影响，
// 进度依旧通过 TaskManifestStore 落盘，回页面能续上。

import 'dart:async';

import 'package:songjiang_reader/utils/log/common.dart';

class DistillBackground {
  DistillBackground._();

  static final Set<StreamSubscription<dynamic>> _subs = {};

  /// 当前仍在后台跑的蒸馏任务数。
  static int get running => _subs.length;

  /// 把一条蒸馏流交给后台执行。
  ///
  /// [onDone] 在任务正常结束时回调（页面可能已销毁，调用方需自行判断 mounted）。
  static void run(
    Stream<dynamic> stream, {
    String tag = 'distill',
    void Function()? onDone,
  }) {
    late StreamSubscription<dynamic> sub;
    sub = stream.listen(
      (_) {},
      onError: (Object e, StackTrace s) {
        SjLog.warning('DistillBackground[$tag]: 任务出错: $e\n$s');
      },
      onDone: () {
        _subs.remove(sub);
        SjLog.info('DistillBackground[$tag]: 任务结束（剩余 ${_subs.length}）');
        onDone?.call();
      },
      cancelOnError: false,
    );
    _subs.add(sub);
    SjLog.info('DistillBackground[$tag]: 已转入后台（共 ${_subs.length} 个）');
  }

  /// 便于测试/退出时统一收尾。
  static Future<void> cancelAll() async {
    final subs = List<StreamSubscription<dynamic>>.of(_subs);
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }
}
