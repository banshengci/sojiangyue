import 'dart:async';

import 'package:langchain/langchain.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/distill_prompt.dart';
import 'package:songjiang_reader/service/character/distill_snapshot.dart';
import 'package:songjiang_reader/service/long_task/task_manifest.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 蒸馏切片：一个章节可能按字数切成多段，每段一次模型调用。
class DistillChunk {
  DistillChunk({required this.index, required this.title, required this.text});

  final int index;
  final String title;
  final String text;
}

enum DistillPhase { preparing, extracting, merging, saving, done, failed }

class DistillProgress {
  const DistillProgress({
    required this.phase,
    this.processedChunks = 0,
    this.totalChunks = 0,
    this.skippedChunks = 0,
    this.charactersFound = 0,
    this.message = '',
  });

  final DistillPhase phase;
  final int processedChunks;
  final int totalChunks;

  /// 增量蒸馏时因内容未变化而跳过的切片数。
  final int skippedChunks;
  final int charactersFound;
  final String message;
}

/// 把长章节切成 ≤ chapterCharBudget 的切片，保留 overlap 避免截断人物台词。
class DistillChunkPlanner {
  DistillChunkPlanner({this.chapterCharBudget = 12000, this.overlap = 800});

  final int chapterCharBudget;
  final int overlap;

  List<DistillChunk> plan(List<BookChapter> chapters) {
    final chunks = <DistillChunk>[];
    var idx = 0;
    for (final ch in chapters) {
      if (ch.text.length <= chapterCharBudget) {
        chunks.add(DistillChunk(index: idx++, title: ch.title, text: ch.text));
        continue;
      }
      var start = 0;
      while (start < ch.text.length) {
        var end = (start + chapterCharBudget).clamp(0, ch.text.length);
        // 尽量在句末断开，避免截断人物台词
        if (end < ch.text.length) {
          final cut = ch.text.lastIndexOf(RegExp(r'[。！？\n]'), end);
          if (cut > start + (chapterCharBudget * 0.5)) end = cut + 1;
        }
        final title = chunks.isEmpty ? ch.title : '${ch.title}（续）';
        chunks.add(DistillChunk(
          index: idx++,
          title: title,
          text: ch.text.substring(start, end),
        ));
        start = end - overlap > start ? end - overlap : end;
      }
    }
    return chunks;
  }
}

/// 断点续传状态（已废弃）。
///
/// 原实现按「切片下标」记录已完成，章节增删会让下标整体错位，反而跳过
/// 真正没蒸馏过的内容。现由 [DistillSnapshotStore] 的**内容指纹快照**接管——
/// 指纹相同即跳过，与切片位置无关，且同一份快照天然覆盖「续跑」与「增量」
/// 两种需求（每完成一段就落一次，中断后重跑自动跳过已完成的）。
///
/// 这里保留一个清理入口，供老版本残留数据回收。
class DistillResumeState {
  static const String _prefix = 'distillResume_';

  /// 清掉历史版本留下的下标快照。
  static Future<void> clearLegacy(int bookId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('$_prefix$bookId');
  }
}

/// 角色蒸馏服务：切片 → 逐切片流式抽取 → 多切片归并 → 整图落库。
/// 流式产出 DistillProgress 供 UI 展示进度；单切片失败仅跳过，不中断整书。
class CharacterDistillService {
  CharacterDistillService({required this.dao, required this.repository});

  final CharacterDao dao;
  final CharacterDistillRepository repository;

  /// 增量蒸馏：只处理「内容指纹」不在上次快照里的切片。
  ///
  /// false 时行为同以前——全书重跑（会整图覆盖）。
  static const bool defaultIncremental = true;

  Stream<DistillProgress> distill({
    required int bookId,
    required BaseChatModel model,
    int chapterCharBudget = 12000,
    bool incremental = defaultIncremental,
  }) async* {
    yield const DistillProgress(
        phase: DistillPhase.preparing, message: '读取章节…');

    // 任务 manifest：记录长任务状态，供任务中心断点续跑。
    final store = TaskManifestStore.instance;
    var manifest = await store.upsert(store.create(kind: 'distill', bookId: bookId));

    final chapters = await repository.getChapters(bookId);
    final planner = DistillChunkPlanner(chapterCharBudget: chapterCharBudget);
    final chunks = planner.plan(chapters);

    // 空文本直接失败：否则会一路走到「完成：0 个人物」，用户完全不知道原因。
    if (chunks.isEmpty) {
      await store.upsert(
        manifest.copyWith(status: LongTaskStatus.failed, total: 0),
      );
      yield const DistillProgress(
        phase: DistillPhase.failed,
        message: '未从书中提取到任何正文（当前蒸馏仅支持 EPUB / TXT）',
      );
      return;
    }

    yield DistillProgress(
      phase: DistillPhase.preparing,
      totalChunks: chunks.length,
      message: '共 ${chunks.length} 个切片',
    );

    // 增量：先算出每个切片的指纹，与上次快照比对。
    // 注意不能只按「下标」判断——章节增删会让下标整体错位。
    final fingerprints = chunks.map((c) => chunkFingerprint(c.text)).toList();
    final snapshot = incremental
        ? await DistillSnapshotStore.load(bookId)
        : DistillSnapshot.empty;
    // 快照为空时退化为全量（首次蒸馏 / 用户清过缓存）。
    final doIncremental = incremental && !snapshot.isEmpty;

    if (doIncremental) {
      yield DistillProgress(
        phase: DistillPhase.preparing,
        totalChunks: chunks.length,
        message: '增量模式：上次已处理 ${snapshot.hashes.length} 段',
      );
    }

    final allCharacters = <String, CharacterCard>{};
    final allRelations = <CharacterRelation>[];
    final allWorld = <WorldSetting>[];
    final allTimeline = <TimelineEvent>[];

    // 增量模式下，先把库里已有的图读出来作为基础，
    // 新抽取的内容与之合并；否则整图会被新结果覆盖掉未变动的部分。
    if (doIncremental) {
      for (final c in await dao.getCharacters(bookId)) {
        allCharacters[c.name] = c;
      }
      allRelations.addAll(await dao.getRelations(bookId));
      allWorld.addAll(await dao.getWorldSettings(bookId));
      allTimeline.addAll(await dao.getTimeline(bookId));
    }

    var processed = 0;
    var skipped = 0;
    var failedChunks = 0;
    final processedHashes = <String>{...snapshot.hashes};

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final hash = fingerprints[i];

      // 增量：内容没变过就直接跳过（不消耗 token）
      if (doIncremental && snapshot.hashes.contains(hash)) {
        skipped++;
        continue;
      }
      yield DistillProgress(
        phase: DistillPhase.extracting,
        processedChunks: processed,
        totalChunks: chunks.length,
        skippedChunks: skipped,
        charactersFound: allCharacters.length,
        message: '抽取：${chunk.title}',
      );
      try {
        final raw = await _extract(model, chunk);
        _mergeInto(allCharacters, allRelations, allWorld, allTimeline, raw,
            bookId);
        processedHashes.add(hash);
        await DistillSnapshotStore.save(
          bookId,
          DistillSnapshot(
            hashes: processedHashes,
            updatedAt: DateTime.now(),
            chunkCount: chunks.length,
          ),
        );
      } catch (e, st) {
        failedChunks++;
        SjLog.warning('CharacterDistill: chunk ${chunk.index} 失败: $e\n$st');
      }
      processed++;
      yield DistillProgress(
        phase: DistillPhase.extracting,
        processedChunks: processed,
        totalChunks: chunks.length,
        skippedChunks: skipped,
        charactersFound: allCharacters.length,
        message: '已抽取 ${allCharacters.length} 个人物',
      );
      manifest = await store.upsert(
        manifest.copyWith(processed: processed, total: chunks.length),
      );
    }

    // 全是旧内容：一个切片都没重跑，直接结束，不落库也不算失败。
    if (processed == 0 && skipped > 0) {
      await store.upsert(manifest.copyWith(
        status: LongTaskStatus.done,
        processed: skipped,
        total: chunks.length,
      ));
      yield DistillProgress(
        phase: DistillPhase.done,
        processedChunks: 0,
        totalChunks: chunks.length,
        skippedChunks: skipped,
        charactersFound: allCharacters.length,
        message: '全书 $skipped 段内容都蒸馏过了，没有新增内容',
      );
      return;
    }

    yield DistillProgress(
      phase: DistillPhase.merging,
      processedChunks: processed,
      totalChunks: chunks.length,
      skippedChunks: skipped,
      charactersFound: allCharacters.length,
      message: '归并关系…',
    );

    final now = DateTime.now();
    final characters =
        allCharacters.values.map((c) => c.copyWith(updatedAt: now)).toList();

    // 所有切片都失败：不要落库覆盖已有数据，直接报失败并说明最可能的原因，
    // 避免用户看到「完成：0 个人物」却无从下手。
    if (characters.isEmpty && failedChunks > 0) {
      await store.upsert(manifest.copyWith(
        status: LongTaskStatus.failed,
        processed: processed,
        total: chunks.length,
      ));
      yield DistillProgress(
        phase: DistillPhase.failed,
        processedChunks: processed,
        totalChunks: chunks.length,
        message: '全部 $failedChunks 个切片调用失败：多为密钥无效、'
            '模型不支持该请求或返回内容无法解析为 JSON，请检查 AI 服务配置。',
      );
      return;
    }

    yield DistillProgress(
      phase: DistillPhase.saving,
      charactersFound: characters.length,
      message: '写入数据库…',
    );
    await dao.replaceBookGraph(
      bookId: bookId,
      characters: characters,
      relations: allRelations,
      settings: allWorld,
      events: allTimeline,
    );
    await DistillResumeState.clearLegacy(bookId);

    // 落库成功后再写快照：中途失败下次仍会重跑这些切片。
    await DistillSnapshotStore.save(
      bookId,
      DistillSnapshot(
        hashes: processedHashes,
        updatedAt: DateTime.now(),
        chunkCount: chunks.length,
      ),
    );

    await store.upsert(manifest.copyWith(
      status: LongTaskStatus.done,
      processed: chunks.length,
      total: chunks.length,
    ));

    final skippedNote = skipped > 0 ? '（跳过 $skipped 段未变内容）' : '';
    yield DistillProgress(
      phase: DistillPhase.done,
      processedChunks: processed,
      totalChunks: chunks.length,
      skippedChunks: skipped,
      charactersFound: characters.length,
      message:
          '完成：${characters.length} 个人物 / ${allRelations.length} 条关系$skippedNote',
    );
  }

  Future<String> _extract(BaseChatModel model, DistillChunk chunk) async {
    final system = ChatMessage.system(buildDistillSystemPrompt());
    final user = ChatMessage.humanText(buildDistillUserPrompt(chunk.title, chunk.text));
    final prompt = PromptValue.chat([system, user]);
    final buffer = StringBuffer();
    await for (final event in model.stream(prompt)) {
      buffer.write(event.output.content);
    }
    return buffer.toString();
  }

  void _mergeInto(
    Map<String, CharacterCard> characters,
    List<CharacterRelation> relations,
    List<WorldSetting> world,
    List<TimelineEvent> timeline,
    String raw,
    int bookId,
  ) {
    final parsed = parseDistillJson(raw, bookId: bookId);
    for (final c in parsed.characters) {
      // 同名多切片出现：保留重要度更高者，其余字段以更高者为准
      final prev = characters[c.name];
      if (prev == null || c.importance > prev.importance) {
        characters[c.name] = c;
      }
    }
    relations.addAll(parsed.relations);
    world.addAll(parsed.world);
    timeline.addAll(parsed.timeline);
  }
}
