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

  /// 并发抽取数。串行等待是蒸馏慢的主因，4 路并发实测能把总耗时压到 1/3 左右。
  /// 再高容易触发服务端 RPM 限流，得不偿失。
  static const int defaultConcurrency = 4;

  Stream<DistillProgress> distill({
    required int bookId,
    required BaseChatModel model,
    int chapterCharBudget = 12000,
    bool incremental = defaultIncremental,
    int concurrency = defaultConcurrency,
    int minImportance = 0,
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

    // 先挑出真正要跑的切片（增量时内容没变过的直接跳）
    final pending = <int>[];
    for (var i = 0; i < chunks.length; i++) {
      if (doIncremental && snapshot.hashes.contains(fingerprints[i])) {
        skipped++;
        continue;
      }
      pending.add(i);
    }

    if (pending.isEmpty) {
      await store.upsert(manifest.copyWith(
        status: LongTaskStatus.done,
        processed: skipped,
        total: chunks.length,
      ));
      yield DistillProgress(
        phase: DistillPhase.done,
        totalChunks: chunks.length,
        skippedChunks: skipped,
        charactersFound: allCharacters.length,
        message: '全书 $skipped 段内容都蒸馏过了，没有新增内容',
      );
      return;
    }

    yield DistillProgress(
      phase: DistillPhase.extracting,
      processedChunks: skipped,
      totalChunks: chunks.length,
      skippedChunks: skipped,
      charactersFound: allCharacters.length,
      message: '开始抽取 ${pending.length} 段（$concurrency 路并发）',
    );

    /// 抽取一批（并发），返回结果与失败的切片下标。
    Future<(List<(int, String?)>, List<int>)> runBatch(
        List<int> batch) async {
      final results = await Future.wait(batch.map((idx) async {
        try {
          return (idx, await _extract(model, chunks[idx]));
        } catch (e, st) {
          SjLog.warning(
              'CharacterDistill: chunk ${chunks[idx].index} 失败: $e\n$st');
          return (idx, null);
        }
      }));
      final failed =
          results.where((r) => r.$2 == null).map((r) => r.$1).toList();
      return (results, failed);
    }

    var failedIndexes = <int>[];

    for (var start = 0; start < pending.length; start += concurrency) {
      final stop =
          (start + concurrency) > pending.length ? pending.length : start + concurrency;
      final (results, failed) = await runBatch(pending.sublist(start, stop));

      for (final r in results) {
        final raw = r.$2;
        if (raw == null) {
          failedChunks++;
          failedIndexes.add(r.$1);
          continue;
        }
        _mergeInto(
            allCharacters, allRelations, allWorld, allTimeline, raw, bookId);
        processedHashes.add(fingerprints[r.$1]);
        processed++;
      }

      // 每批落一次库：中途「停止」时已抽到的人物会留着，
      // 人物页也能边跑边看到结果（不再是跑完才一次性出现）。
      await _persist(
        bookId: bookId,
        characters: allCharacters,
        relations: allRelations,
        world: allWorld,
        timeline: allTimeline,
        minImportance: minImportance,
      );
      await DistillSnapshotStore.save(
        bookId,
        DistillSnapshot(
          hashes: processedHashes,
          updatedAt: DateTime.now(),
          chunkCount: chunks.length,
        ),
      );
      manifest = await store.upsert(manifest.copyWith(
        processed: skipped + processed,
        total: chunks.length,
      ));

      yield DistillProgress(
        phase: DistillPhase.extracting,
        processedChunks: skipped + processed,
        totalChunks: chunks.length,
        skippedChunks: skipped,
        charactersFound: allCharacters.length,
        message: '已抽取 ${allCharacters.length} 个人物',
      );
    }

    // 并发下偶发限流/超时很常见，失败的再补跑一轮，避免白白丢内容。
    if (failedIndexes.isNotEmpty) {
      yield DistillProgress(
        phase: DistillPhase.extracting,
        processedChunks: skipped + processed,
        totalChunks: chunks.length,
        skippedChunks: skipped,
        charactersFound: allCharacters.length,
        message: '重试 ${failedIndexes.length} 段失败的切片…',
      );
      final retryFailed = <int>[];
      for (var start = 0; start < failedIndexes.length; start += concurrency) {
        final stop =
            (start + concurrency) > failedIndexes.length ? failedIndexes.length : start + concurrency;
        final (results, failed) =
            await runBatch(failedIndexes.sublist(start, stop));
        for (final r in results) {
          final raw = r.$2;
          if (raw == null) {
            retryFailed.add(r.$1);
            continue;
          }
          _mergeInto(
              allCharacters, allRelations, allWorld, allTimeline, raw, bookId);
          processedHashes.add(fingerprints[r.$1]);
          failedChunks--;
          processed++;
        }
      }
      failedIndexes = retryFailed;
      if (processed > 0) {
        await _persist(
          bookId: bookId,
          characters: allCharacters,
          relations: allRelations,
          world: allWorld,
          timeline: allTimeline,
          minImportance: minImportance,
        );
      }
    }

    yield DistillProgress(
      phase: DistillPhase.merging,
      processedChunks: skipped + processed,
      totalChunks: chunks.length,
      skippedChunks: skipped,
      charactersFound: allCharacters.length,
      message: '归并关系…',
    );

    // 一个人物都没抽到且全失败：保持库里已有数据不动，直接报失败说明原因
    if (allCharacters.isEmpty && failedChunks > 0) {
      await store.upsert(manifest.copyWith(
        status: LongTaskStatus.failed,
        processed: skipped + processed,
        total: chunks.length,
      ));
      yield DistillProgress(
        phase: DistillPhase.failed,
        processedChunks: skipped + processed,
        totalChunks: chunks.length,
        message: '全部 $failedChunks 个切片调用失败：多为密钥无效、'
            '模型不支持该请求或返回内容无法解析为 JSON，请检查 AI 服务配置。',
      );
      return;
    }

    yield DistillProgress(
      phase: DistillPhase.saving,
      charactersFound: allCharacters.length,
      message: '写入数据库…',
    );
    final savedCount = await _persist(
      bookId: bookId,
      characters: allCharacters,
      relations: allRelations,
      world: allWorld,
      timeline: allTimeline,
      minImportance: minImportance,
    );
    await DistillResumeState.clearLegacy(bookId);

    await store.upsert(manifest.copyWith(
      status: LongTaskStatus.done,
      processed: chunks.length,
      total: chunks.length,
    ));

    final skippedNote = skipped > 0 ? '，跳过 $skipped 段未变内容' : '';
    final filterNote = minImportance > 0
        ? '（已按重要度 ≥ $minImportance 收录 $savedCount 人）'
        : '';
    final failedNote = failedIndexes.isEmpty ? '' : '，${failedIndexes.length} 段仍失败';
    yield DistillProgress(
      phase: DistillPhase.done,
      processedChunks: chunks.length,
      totalChunks: chunks.length,
      skippedChunks: skipped,
      charactersFound: allCharacters.length,
      message: '完成：识别 ${allCharacters.length} 个人物 / '
          '${allRelations.length} 条关系$filterNote$skippedNote$failedNote',
    );
  }

  /// 把当前合并结果写入数据库。
  ///
  /// [minImportance] > 0 时只收录重要度达标的人物，并顺带丢掉指向被过滤者
  /// 的关系——否则关系图里会留下连不上人物的孤立连线。
  Future<int> _persist({
    required int bookId,
    required Map<String, CharacterCard> characters,
    required List<CharacterRelation> relations,
    required List<WorldSetting> world,
    required List<TimelineEvent> timeline,
    required int minImportance,
  }) async {
    final now = DateTime.now();
    final all = characters.values.map((c) => c.copyWith(updatedAt: now)).toList();
    final kept = minImportance <= 0
        ? all
        : all.where((c) => c.importance >= minImportance).toList();

    var keptRelations = relations;
    if (minImportance > 0) {
      final names = kept.map((c) => c.name).toSet();
      keptRelations = relations
          .where((r) =>
              names.contains(r.sourceName) && names.contains(r.targetName))
          .toList();
    }

    await dao.replaceBookGraph(
      bookId: bookId,
      characters: kept,
      relations: keptRelations,
      settings: world,
      events: timeline,
    );
    return kept.length;
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
      final prev = characters[c.name];
      characters[c.name] = prev == null ? c : _mergeCard(prev, c);
    }
    relations.addAll(parsed.relations);
    world.addAll(parsed.world);
    timeline.addAll(parsed.timeline);
  }

  /// 同一人物的多段画像做**字段级**合并。
  ///
  /// 蒸馏是按切片逐段跑的，同一个人在不同段里往往各有侧重——一段写了性格，
  /// 另一段写了出身。原先的实现是「整条替换（保留重要度更高者）」，
  /// 会把另一段独有的字段整块丢掉，人物档案因此偏薄。
  ///
  /// 这里的策略（对齐造梦「局部草稿 → 汇总合并」的做法）：
  ///   - 重要度取两者更大；
  ///   - 文本字段取非空的那份；都非空时取信息更全的（更长）那份，
  ///     长度接近则保留先出现的，避免来回抖动；
  ///   - 别名求并集。
  CharacterCard _mergeCard(CharacterCard prev, CharacterCard next) {
    String? pick(String? a, String? b) {
      final x = a?.trim() ?? '';
      final y = b?.trim() ?? '';
      if (x.isEmpty) return y.isEmpty ? null : y;
      if (y.isEmpty) return x;
      return y.length > x.length + 4 ? y : x;
    }

    final aliases = <String>{
      ...?prev.aliases,
      ...?next.aliases,
    }.where((e) => e.isNotEmpty && e != prev.name).toList();

    return prev.copyWith(
      aliases: aliases,
      gender: pick(prev.gender, next.gender),
      role: pick(prev.role, next.role),
      importance: prev.importance >= next.importance
          ? prev.importance
          : next.importance,
      personality: pick(prev.personality, next.personality),
      background: pick(prev.background, next.background),
      motivation: pick(prev.motivation, next.motivation),
      appearance: pick(prev.appearance, next.appearance),
      firstAppearanceChapter:
          pick(prev.firstAppearanceChapter, next.firstAppearanceChapter),
      description: pick(prev.description, next.description),
      updatedAt: DateTime.now(),
    );
  }
}
