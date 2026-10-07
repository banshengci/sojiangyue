// lib/page/long_task/long_task_center_page.dart
//
// 任务中心（2.6）：列出长任务 manifest，展示状态 / 进度，对中断任务提供「继续」，
// 对完成 / 失败任务提供「清除」。蒸馏类任务可在此断点续跑。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart';
import 'package:songjiang_reader/service/character/distill_background.dart';
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

  /// 真实在跑的后台任务（tag → 展示名）。以 DistillBackground 为准，
  /// 而不是清单里的 status——进程被系统回收后清单会残留「进行中」。
  List<String> _runningTags = [];
  final Map<String, String> _runningLabels = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final store = TaskManifestStore.instance;
    var tasks = await store.list();

    // 清单里标着「进行中」但其实没有对应任务（进程重启 / 被系统杀掉）
    // → 改成「待续跑」，否则用户会以为它还在跑。
    for (final t in tasks) {
      if (t.status != LongTaskStatus.running) continue;
      final tag = _tagOf(t);
      if (tag != null && DistillBackground.isRunning(tag)) continue;
      final updated =
          await store.upsert(t.copyWith(status: LongTaskStatus.pending));
      tasks = [for (final e in tasks) if (e.key == updated.key) updated else e];
    }

    // 正在运行的以 DistillBackground 为唯一依据：这样知识抽取这种
    // 尚未登记清单的任务也能被看见并停止。
    _runningTags = DistillBackground.runningTags;
    _runningLabels.clear();
    for (final tag in _runningTags) {
      _runningLabels[tag] = await _labelForTag(tag);
    }

    if (!mounted) return;
    // 最新更新在前。
    tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  /// 任务清单项 → 后台任务 tag。
  String? _tagOf(TaskManifest t) {
    final bookId = t.bookId;
    if (bookId == null) return null;
    switch (t.kind) {
      case 'distill':
        return DistillBackground.charactersTag(bookId);
      case 'knowledge':
        return DistillBackground.knowledgeTag(bookId);
      default:
        return null;
    }
  }

  /// 把 tag（如 `characters-3`）翻成「人物蒸馏 · 书名」。
  Future<String> _labelForTag(String tag) async {
    final idx = tag.lastIndexOf('-');
    if (idx <= 0) return tag;
    final kind = tag.substring(0, idx);
    final bookId = int.tryParse(tag.substring(idx + 1));
    final kindLabel = switch (kind) {
      'characters' => '人物蒸馏',
      'knowledge' => '原著知识抽取',
      _ => kind,
    };
    if (bookId == null) return kindLabel;
    try {
      final book = await bookDao.selectBookById(bookId);
      return '$kindLabel · ${book.title}';
    } catch (_) {
      return '$kindLabel · 书#$bookId';
    }
  }

  Future<void> _stop(String tag) async {
    final ok = await DistillBackground.cancel(tag);
    SjToast.show(ok ? '已停止' : '任务已结束');
    await _reload();
  }

  Future<void> _remove(String key) async {
    await TaskManifestStore.instance.remove(key);
    await _reload();
  }

  Future<void> _resumeDistill(int bookId) async {
    final model = resolveCurrentModel();
    if (model == null) {
      SjToast.show('尚未配置 AI 服务，无法续跑蒸馏');
      return;
    }
    final service = CharacterDistillService(
      dao: characterDao,
      repository: CharacterDistillRepository(bookDao: bookDao),
    );
    // 提前建流：写在 StreamBuilder 的 builder 里会导致每次重建都重新发起蒸馏。
    // 内容指纹快照会跳过上次已完成的部分，所以这里天然就是「续跑」。
    final stream = service
        .distill(bookId: bookId, model: model)
        .asBroadcastStream();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StreamBuilder<DistillProgress>(
        stream: stream,
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
          : (_tasks.isEmpty && _runningTags.isEmpty)
              ? EmptyStateHint(
                  icon: Icons.task_outlined,
                  title: '任务中心',
                  subtitle: '大书导入 / 角色蒸馏等长任务会在此记录；'
                      '正在运行的任务也可以在这里停止。',
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_runningTags.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child:
                            Text('正在运行', style: SjText.sectionTitle(c.ink)),
                      ),
                      for (final tag in _runningTags)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.river,
                              ),
                            ),
                            title: Text(
                              _runningLabels[tag] ?? tag,
                              style: SjText.cardTitle(c.ink),
                            ),
                            subtitle: Text('后台运行中，可随时停止',
                                style: SjText.meta(c.inkSoft)),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.stop_circle_outlined,
                                  size: 18),
                              label: const Text('停止'),
                              onPressed: () => _stop(tag),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                    ],
                    if (_tasks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child:
                            Text('任务记录', style: SjText.sectionTitle(c.ink)),
                      ),
                      for (final t in _tasks) _buildTaskCard(t, c),
                    ],
                  ],
                ),
    );
  }

  /// 单条任务记录。
  Widget _buildTaskCard(TaskManifest t, SjColors c) {
    final tag = _tagOf(t);
    final running = tag != null && DistillBackground.isRunning(tag);
    // 正在跑的时候「继续」没有意义，只有真的中断了才给
    final canResume = !running && t.isInterrupted && t.bookId != null;
    final status = running ? LongTaskStatus.running : t.status;

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
                    _kindLabel(t.kind) +
                        (t.bookId != null ? ' · 书#${t.bookId}' : ''),
                    style: SjText.cardTitle(c.ink),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(status, c).withAlpha(28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: SjText.meta(c.inkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: t.progress,
              backgroundColor: c.divider,
              valueColor: AlwaysStoppedAnimation(_statusColor(status, c)),
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
                if (running)
                  TextButton.icon(
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('停止'),
                    onPressed: () => _stop(tag),
                  ),
                if (canResume)
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('继续'),
                    onPressed: () => _resumeDistill(t.bookId!),
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
  }

  String _kindLabel(String kind) => switch (kind) {
        'distill' => '人物蒸馏',
        'knowledge' => '原著知识抽取',
        _ => kind,
      };
}
