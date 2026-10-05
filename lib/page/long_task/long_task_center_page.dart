// lib/page/long_task/long_task_center_page.dart
//
// 任务中心（2.6）：列出长任务 manifest，展示状态 / 进度，对中断任务提供「继续」，
// 对完成 / 失败任务提供「清除」。蒸馏类任务可在此断点续跑。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/ai/langchain_ai_config.dart';
import 'package:songjiang_reader/service/ai/langchain_registry.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart';
import 'package:songjiang_reader/service/long_task/task_manifest.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

class LongTaskCenterPage extends StatefulWidget {
  const LongTaskCenterPage({super.key});

  @override
  State<LongTaskCenterPage> createState() => _LongTaskCenterPageState();
}

class _LongTaskCenterPageState extends State<LongTaskCenterPage> {
  List<TaskManifest> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final tasks = await TaskManifestStore.instance.list();
    if (!mounted) return;
    // 最新更新在前。
    tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _remove(String key) async {
    await TaskManifestStore.instance.remove(key);
    await _reload();
  }

  Future<void> _resumeDistill(int bookId) async {
    final id = AiPrefs.selectedServiceId;
    final raw = AiPrefs.getConfig(id);
    if (raw.isEmpty) {
      SjToast.show('尚未配置 AI 服务，无法续跑蒸馏');
      return;
    }
    final config = LangchainAiConfig.fromPrefs(id, raw);
    final model = LangchainAiRegistry(null).resolve(config).model;
    final service = CharacterDistillService(
      dao: characterDao,
      repository: CharacterDistillRepository(bookDao: bookDao),
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StreamBuilder<DistillProgress>(
        stream: service.distill(bookId: bookId, model: model),
        builder: (context, snap) {
          final p = snap.data;
          final done = p?.phase == DistillPhase.done;
          final failed = p?.phase == DistillPhase.failed || snap.hasError;
          return AlertDialog(
            title: Text(done ? '续跑完成' : '继续蒸馏'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!done && !failed)
                  LinearProgressIndicator(
                    value: (p?.totalChunks ?? 0) == 0
                        ? null
                        : (p?.processedChunks ?? 0) / (p!.totalChunks),
                  ),
                const SizedBox(height: 12),
                Text(snap.hasError ? '失败：${snap.error}' : (p?.message ?? '')),
              ],
            ),
            actions: [
              if (done || failed)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('关闭'),
                )
              else
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('后台运行'),
                ),
            ],
          );
        },
      ),
    );
    await _reload();
  }

  Color _statusColor(LongTaskStatus s, SjColors c) {
    switch (s) {
      case LongTaskStatus.running:
        return c.river;
      case LongTaskStatus.done:
        return c.clay;
      case LongTaskStatus.failed:
        return c.clay;
      case LongTaskStatus.pending:
        return c.inkSoft;
      case LongTaskStatus.canceled:
        return c.inkSoft;
    }
  }

  String _statusLabel(LongTaskStatus s) => switch (s) {
        LongTaskStatus.running => '进行中',
        LongTaskStatus.done => '已完成',
        LongTaskStatus.failed => '失败',
        LongTaskStatus.pending => '待续跑',
        LongTaskStatus.canceled => '已取消',
      };

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务中心'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingHint()
          : _tasks.isEmpty
              ? EmptyStateHint(
                  icon: Icons.task_outlined,
                  title: '任务中心',
                  subtitle: '大书导入 / 角色蒸馏等长任务会在此记录，中断后可续跑。',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    final t = _tasks[index];
                    final canResume = t.isInterrupted && t.bookId != null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${t.kind}${t.bookId != null ? ' · 书#${t.bookId}' : ''}',
                                    style: SjText.cardTitle(c.ink),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _statusColor(t.status, c)
                                        .withAlpha(28),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _statusLabel(t.status),
                                    style: SjText.meta(c.inkSoft),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: t.progress,
                              backgroundColor: c.divider,
                              valueColor:
                                  AlwaysStoppedAnimation(_statusColor(t.status, c)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '进度 ${t.processed}/${t.total}'
                              '${t.error != null ? ' · ${t.error}' : ''}',
                              style: SjText.meta(c.inkSoft),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (canResume)
                                  TextButton.icon(
                                    icon: const Icon(Icons.play_arrow, size: 18),
                                    label: const Text('继续'),
                                    onPressed: () =>
                                        _resumeDistill(t.bookId!),
                                  ),
                                TextButton(
                                  onPressed: () => _remove(t.key),
                                  child: const Text('清除'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
