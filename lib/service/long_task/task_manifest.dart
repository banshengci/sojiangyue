// lib/service/long_task/task_manifest.dart
//
// 长任务 manifest 状态机（2.6）：大书导入 / AI 深读 / 角色蒸馏等耗时任务的状态持久化。
// 单文件记录所有任务清单（JSON），支持 pending/running/done/failed/canceled 与进度，
// 中断（退出页面 / 后台被杀）后可由任务中心检测并断点续跑。
//
// 说明：Android 前台服务（进程级后台化）为平台专属能力，需原生集成，本层只负责
// 任务状态的落盘与续跑判定，不绑定具体平台。

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 长任务状态。
enum LongTaskStatus {
  pending,
  running,
  done,
  failed,
  canceled;

  bool get isInterrupted => this == failed || this == pending;
}

/// 单个长任务的清单。
class TaskManifest {
  TaskManifest({
    required this.key,
    required this.kind,
    this.bookId,
    this.status = LongTaskStatus.pending,
    this.processed = 0,
    this.total = 0,
    this.error,
    required this.updatedAt,
    this.startedAt,
  });

  final String key;
  final String kind;
  final int? bookId;
  final LongTaskStatus status;
  final int processed;
  final int total;
  final String? error;
  final DateTime updatedAt;
  final DateTime? startedAt;

  factory TaskManifest.fromJson(Map<String, dynamic> j) => TaskManifest(
        key: j['key'] as String,
        kind: j['kind'] as String,
        bookId: j['bookId'] as int?,
        status: LongTaskStatus.values
                .where((s) => s.name == (j['status'] as String? ?? 'pending'))
                .firstOrNull ??
            LongTaskStatus.pending,
        processed: (j['processed'] as int?) ?? 0,
        total: (j['total'] as int?) ?? 0,
        error: j['error'] as String?,
        startedAt: j['startedAt'] == null
            ? null
            : DateTime.tryParse(j['startedAt'] as String),
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'kind': kind,
        'bookId': bookId,
        'status': status.name,
        'processed': processed,
        'total': total,
        'error': error,
        'startedAt': startedAt?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  double get progress => total == 0 ? 0 : (processed / total).clamp(0, 1);

  bool get isInterrupted => status.isInterrupted;

  TaskManifest copyWith({
    LongTaskStatus? status,
    int? processed,
    int? total,
    String? error,
    DateTime? updatedAt,
  }) =>
      TaskManifest(
        key: key,
        kind: kind,
        bookId: bookId,
        status: status ?? this.status,
        processed: processed ?? this.processed,
        total: total ?? this.total,
        error: error ?? this.error,
        startedAt: startedAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );
}

/// 任务清单持久化（文件后端，应用支持目录下 long_tasks/manifests.json）。
class TaskManifestStore {
  TaskManifestStore._();
  static final TaskManifestStore instance = TaskManifestStore._();

  List<TaskManifest> _cache = const [];
  DateTime? _loadedAt;

  Future<File> get _file async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/long_tasks');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/manifests.json');
  }

  Future<List<TaskManifest>> list() async {
    if (_loadedAt != null) return _cache;
    await _reload();
    return _cache;
  }

  Future<void> _reload() async {
    try {
      final f = await _file;
      if (await f.exists()) {
        final raw = await f.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _cache = decoded
              .whereType<Map>()
              .map((m) => TaskManifest.fromJson(m))
              .toList();
        }
      }
    } catch (e) {
      SjLog.warning('TaskManifest: 读取失败 $e');
      _cache = const [];
    }
    _loadedAt = DateTime.now();
  }

  Future<void> _persist() async {
    final f = await _file;
    await f.writeAsString(
      jsonEncode(_cache.map((m) => m.toJson()).toList()),
      flush: true,
    );
  }

  /// 新增或更新一个任务清单。
  Future<TaskManifest> upsert(TaskManifest m) async {
    await _reload();
    final next = <TaskManifest>[];
    var replaced = false;
    for (final existing in _cache) {
      if (existing.key == m.key) {
        next.add(m);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(m);
    _cache = next;
    await _persist();
    return m;
  }

  Future<void> remove(String key) async {
    await _reload();
    _cache = _cache.where((m) => m.key != key).toList();
    await _persist();
  }

  /// 生成一个新任务清单（状态 running）。
  TaskManifest create({required String kind, int? bookId}) => TaskManifest(
        key: '${kind}_${bookId ?? ''}_'
            '${DateTime.now().millisecondsSinceEpoch}',
        kind: kind,
        bookId: bookId,
        status: LongTaskStatus.running,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}
