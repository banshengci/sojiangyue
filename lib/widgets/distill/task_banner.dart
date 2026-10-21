// lib/widgets/distill/task_banner.dart
//
// 后台任务横幅：只在真有任务时出现，不占常驻空间。
//
// 任务中心原来只挂在「设置 → AI」里，从书架点到它要三层。
// 蒸馏和知识抽取都从各自的功能页发起，入口理应在那儿——
// 但常驻一个图标又太吵，所以做成「有任务才出现」的一条。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';

class TaskBanner extends StatelessWidget {
  const TaskBanner({
    super.key,
    required this.onTap,
    this.text = '有后台任务 · 可以停下，回头在这儿接着跑',
  });

  final VoidCallback onTap;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
        color: c.pine.withValues(alpha: 0.08),
        child: Row(
          children: [
            Icon(Icons.downloading, size: 15, color: c.pine),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: SjText.meta(c.pine),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: c.pine),
          ],
        ),
      ),
    );
  }
}
