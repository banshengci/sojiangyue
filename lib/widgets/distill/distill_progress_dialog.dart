// lib/widgets/distill/distill_progress_dialog.dart
//
// 蒸馏进度对话框：显示进度，并提供「停止 / 后台运行」。
//
// 任务的订阅由 DistillBackground 持有，本对话框只负责显示与发指令。
// 因此关掉对话框任务照跑（后台运行），而想停随时可以停——
// 要么在这里点「停止」，要么去任务中心停。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:songjiang_reader/service/character/distill_background.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

/// 与具体蒸馏类型解耦的展示模型。
///
/// 人物蒸馏是 DistillProgress、知识抽取是 KnowledgeProgress，字段不同；
/// 由调用方各自转换成本模型，对话框就不必关心来源。
class DistillProgressView {
  const DistillProgressView({
    required this.message,
    this.ratio,
    this.done = false,
    this.failed = false,
    this.countText,
    this.skipped,
  });

  final String message;

  /// 0~1；为 null 表示进度不确定（转圈）。
  final double? ratio;
  final bool done;
  final bool failed;

  /// 已产出数量的完整说明文案（如「已识别 12 位人物」）。
  final String? countText;

  /// 增量蒸馏跳过的片段数。
  final int? skipped;
}

class DistillProgressDialog extends StatelessWidget {
  const DistillProgressDialog({
    super.key,
    required this.view,
    required this.error,
    required this.tag,
    this.runningTitle = '正在蒸馏全书…',
    this.doneTitle = '完成',
    this.onStopped,
  });

  final ValueListenable<DistillProgressView?> view;
  final ValueListenable<Object?> error;

  /// DistillBackground 的任务 tag，用于停止。
  final String tag;
  final String runningTitle;
  final String doneTitle;
  final VoidCallback? onStopped;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DistillProgressView?>(
      valueListenable: view,
      builder: (context, v, _) {
        return ValueListenableBuilder<Object?>(
          valueListenable: error,
          builder: (context, err, __) {
            final failed = err != null || (v?.failed ?? false);
            final done = (v?.done ?? false) && !failed;

            final message =
                err != null ? '失败：$err' : (v?.message ?? '准备中…');

            return AlertDialog(
              title: Text(done ? doneTitle : runningTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!done && !failed)
                    LinearProgressIndicator(value: v?.ratio),
                  const SizedBox(height: 12),
                  Text(message),
                  if (v?.countText != null) ...[
                    const SizedBox(height: 8),
                    Text(v!.countText!),
                  ],
                  if ((v?.skipped ?? 0) > 0) ...[
                    const SizedBox(height: 4),
                    Text('已跳过 ${v!.skipped} 段未变内容',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
              actions: [
                if (done || failed)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  )
                else ...[
                  TextButton(
                    onPressed: () async {
                      final ok = await DistillBackground.cancel(tag);
                      if (context.mounted) Navigator.of(context).pop();
                      SjToast.show(ok ? '已停止' : '任务已结束');
                      onStopped?.call();
                    },
                    child: const Text('停止'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      SjToast.show('已转入后台，可到「任务中心」查看或停止');
                    },
                    child: const Text('后台运行'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
