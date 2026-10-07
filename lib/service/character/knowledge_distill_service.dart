// lib/service/character/knowledge_distill_service.dart
//
// 原著知识抽取：把全书的「可查阅事实」抽成条目，供按主题检索。
//
// 复用人物蒸馏那套骨架（同一份 EPUB/TXT 章节读取 + 切片规划 + 内容指纹快照），
// 但用独立的提示词与独立快照域（scope='knowledge'），互不干扰。
// 增量语义与人物蒸馏一致：内容没变过的切片直接跳过，不重复烧 token。

import 'dart:convert';

import 'package:langchain/langchain.dart';

import 'package:songjiang_reader/dao/character_extras_dao.dart';
import 'package:songjiang_reader/models/character_extras.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart';
import 'package:songjiang_reader/service/character/distill_snapshot.dart';
import 'package:songjiang_reader/service/character/knowledge_prompt.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 知识抽取进度。
class KnowledgeProgress {
  const KnowledgeProgress({
    required this.message,
    this.processed = 0,
    this.total = 0,
    this.skipped = 0,
    this.itemsFound = 0,
    this.done = false,
    this.failed = false,
  });

  final String message;
  final int processed;
  final int total;
  final int skipped;
  final int itemsFound;
  final bool done;
  final bool failed;
}

class KnowledgeDistillService {
  KnowledgeDistillService({required this.repository});

  final CharacterDistillRepository repository;

  static const String _scope = 'knowledge';

  /// 抽取全书知识；[incremental] 为真时只处理内容有变化的切片。
  Stream<KnowledgeProgress> distill({
    required int bookId,
    required BaseChatModel model,
    int chapterCharBudget = 12000,
    bool incremental = true,
  }) async* {
    yield const KnowledgeProgress(message: '读取章节…');

    final chapters = await repository.getChapters(bookId);
    final chunks =
        DistillChunkPlanner(chapterCharBudget: chapterCharBudget).plan(chapters);

    if (chunks.isEmpty) {
      yield const KnowledgeProgress(
        message: '未从书中提取到任何正文（当前仅支持 EPUB / TXT）',
        failed: true,
      );
      return;
    }

    final fingerprints = chunks.map((c) => chunkFingerprint(c.text)).toList();
    final snapshot = incremental
        ? await DistillSnapshotStore.load(bookId, scope: _scope)
        : DistillSnapshot.empty;
    final doIncremental = incremental && !snapshot.isEmpty;

    // 已有条目作为基础（增量时保留，全量时会被覆盖）
    final existing = doIncremental
        ? await characterExtrasDao.listKnowledge(bookId)
        : <KnowledgeItem>[];
    final collected = <KnowledgeItem>[...existing];
    final seenTopics = {for (final e in existing) e.topic};
    final hashes = <String>{...snapshot.hashes};

    yield KnowledgeProgress(
      message: '共 ${chunks.length} 个切片'
          '${doIncremental ? '（增量：已处理 ${snapshot.hashes.length} 段）' : ''}',
      total: chunks.length,
    );

    var processed = 0;
    var skipped = 0;
    var failedChunks = 0;

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final hash = fingerprints[i];
      if (doIncremental && snapshot.hashes.contains(hash)) {
        skipped++;
        continue;
      }

      yield KnowledgeProgress(
        message: '抽取：${chunk.title}',
        processed: processed,
        total: chunks.length,
        skipped: skipped,
        itemsFound: collected.length,
      );

      try {
        final items = await _extract(model, chunk, bookId);
        for (final item in items) {
          // 同名主题以新的为准（章节变化往往意味着设定被修正过）
          if (seenTopics.contains(item.topic)) {
            collected.removeWhere((e) => e.topic == item.topic);
          }
          seenTopics.add(item.topic);
          collected.add(item);
        }
        hashes.add(hash);
        await DistillSnapshotStore.save(
          bookId,
          DistillSnapshot(
            hashes: hashes,
            updatedAt: DateTime.now(),
            chunkCount: chunks.length,
          ),
          scope: _scope,
        );
      } catch (e, st) {
        failedChunks++;
        SjLog.warning('Knowledge: chunk ${chunk.index} 失败: $e\n$st');
      }
      processed++;
    }

    if (processed == 0 && skipped > 0) {
      yield KnowledgeProgress(
        message: '全书 $skipped 段都抽过了，没有新增内容',
        total: chunks.length,
        skipped: skipped,
        itemsFound: collected.length,
        done: true,
      );
      return;
    }

    if (collected.isEmpty && failedChunks > 0) {
      yield KnowledgeProgress(
        message: '全部 $failedChunks 个切片失败，多为密钥无效或模型返回无法解析为 JSON',
        total: chunks.length,
        failed: true,
      );
      return;
    }

    yield KnowledgeProgress(
      message: '写入数据库…',
      itemsFound: collected.length,
    );
    await characterExtrasDao.replaceKnowledge(bookId, collected);

    final note = skipped > 0 ? '（跳过 $skipped 段未变内容）' : '';
    yield KnowledgeProgress(
      message: '完成：共 ${collected.length} 条知识$note',
      processed: processed,
      total: chunks.length,
      skipped: skipped,
      itemsFound: collected.length,
      done: true,
    );
  }

  Future<List<KnowledgeItem>> _extract(
    BaseChatModel model,
    DistillChunk chunk,
    int bookId,
  ) async {
    final prompt = PromptValue.chat([
      ChatMessage.system(buildKnowledgeSystemPrompt()),
      ChatMessage.humanText(buildKnowledgeUserPrompt(chunk.title, chunk.text)),
    ]);
    final buffer = StringBuffer();
    await for (final event in model.stream(prompt)) {
      buffer.write(event.output.content);
    }
    return _parseItems(buffer.toString(), bookId, chunk.title);
  }

  /// 解析模型返回的 JSON；容忍代码围栏与前后杂字。
  List<KnowledgeItem> _parseItems(String raw, int bookId, String fallbackTitle) {
    final jsonText = _extractJson(raw);
    if (jsonText == null) return const [];

    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      SjLog.warning('Knowledge: JSON 解析失败: $e');
      return const [];
    }

    final list = decoded is Map
        ? (decoded['items'] ?? decoded['knowledge'] ?? decoded['data'])
        : decoded;
    if (list is! List) return const [];

    final now = DateTime.now();
    final out = <KnowledgeItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final topic = (e['topic'] ?? e['title'] ?? '').toString().trim();
      final summary =
          (e['summary'] ?? e['content'] ?? e['detail'] ?? '').toString().trim();
      if (topic.isEmpty || summary.isEmpty) continue;
      final chapter =
          (e['chapter'] ?? e['source'] ?? '').toString().trim();
      out.add(KnowledgeItem(
        bookId: bookId,
        topic: topic,
        summary: summary,
        chapter: chapter.isEmpty ? fallbackTitle : chapter,
        createdAt: now,
        updatedAt: now,
      ));
    }
    return out;
  }

  /// 从可能带 Markdown 围栏的文本里挑出 JSON 主体。
  String? _extractJson(String raw) {
    var s = raw.trim();
    if (s.contains('```')) {
      final m = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
      if (m != null) s = m.group(1)!.trim();
    }
    final start = s.indexOf('{');
    final arrStart = s.indexOf('[');
    var begin = start;
    if (begin < 0 || (arrStart >= 0 && arrStart < begin)) begin = arrStart;
    if (begin < 0) return null;
    final endCurly = s.lastIndexOf('}');
    final endSquare = s.lastIndexOf(']');
    var end = endCurly > endSquare ? endCurly : endSquare;
    if (end <= begin) return null;
    return s.substring(begin, end + 1);
  }
}
