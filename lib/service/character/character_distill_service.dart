import 'dart:async';
import 'dart:convert';

import 'package:langchain/langchain.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/distill_prompt.dart';
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
    this.charactersFound = 0,
    this.message = '',
  });

  final DistillPhase phase;
  final int processedChunks;
  final int totalChunks;
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

/// 断点续传状态：记录已成功处理的切片下标，存于 SharedPreferences（bookId 维度）。
class DistillResumeState {
  static const String _prefix = 'distillResume_';

  static Future<Set<int>> load(int bookId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('$_prefix$bookId');
    if (raw == null) return {};
    try {
      final list = (jsonDecode(raw) as List).cast<int>();
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(int bookId, Set<int> done) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('$_prefix$bookId', jsonEncode(done.toList()));
  }

  static Future<void> clear(int bookId) async {
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

  Stream<DistillProgress> distill({
    required int bookId,
    required BaseChatModel model,
    int chapterCharBudget = 12000,
    bool resume = true,
  }) async* {
    yield const DistillProgress(
        phase: DistillPhase.preparing, message: '读取章节…');

    // 任务 manifest：记录长任务状态，供任务中心断点续跑。
    final store = TaskManifestStore.instance;
    var manifest = await store.upsert(store.create(kind: 'distill', bookId: bookId));

    final chapters = await repository.getChapters(bookId);
    final planner = DistillChunkPlanner(chapterCharBudget: chapterCharBudget);
    final chunks = planner.plan(chapters);
    yield DistillProgress(
      phase: DistillPhase.preparing,
      totalChunks: chunks.length,
      message: '共 ${chunks.length} 个切片',
    );

    final resumeDone = resume ? await DistillResumeState.load(bookId) : <int>{};
    final allCharacters = <String, CharacterCard>{};
    final allRelations = <CharacterRelation>[];
    final allWorld = <WorldSetting>[];
    final allTimeline = <TimelineEvent>[];
    var processed = 0;

    for (final chunk in chunks) {
      if (resumeDone.contains(chunk.index)) {
        processed++;
        continue;
      }
      yield DistillProgress(
        phase: DistillPhase.extracting,
        processedChunks: processed,
        totalChunks: chunks.length,
        charactersFound: allCharacters.length,
        message: '抽取：${chunk.title}',
      );
      try {
        final raw = await _extract(model, chunk);
        _mergeInto(allCharacters, allRelations, allWorld, allTimeline, raw,
            bookId);
        resumeDone.add(chunk.index);
        await DistillResumeState.save(bookId, resumeDone);
      } catch (e, st) {
        SjLog.warning('CharacterDistill: chunk ${chunk.index} 失败: $e\n$st');
      }
      processed++;
      yield DistillProgress(
        phase: DistillPhase.extracting,
        processedChunks: processed,
        totalChunks: chunks.length,
        charactersFound: allCharacters.length,
        message: '已抽取 ${allCharacters.length} 个人物',
      );
      manifest = await store.upsert(
        manifest.copyWith(processed: processed, total: chunks.length),
      );
    }

    yield DistillProgress(
      phase: DistillPhase.merging,
      processedChunks: processed,
      totalChunks: chunks.length,
      charactersFound: allCharacters.length,
      message: '归并关系…',
    );

    final now = DateTime.now();
    final characters =
        allCharacters.values.map((c) => c.copyWith(updatedAt: now)).toList();

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
    await DistillResumeState.clear(bookId);

    await store.upsert(manifest.copyWith(
      status: LongTaskStatus.done,
      processed: chunks.length,
      total: chunks.length,
    ));

    yield DistillProgress(
      phase: DistillPhase.done,
      processedChunks: processed,
      totalChunks: chunks.length,
      charactersFound: characters.length,
      message:
          '完成：${characters.length} 个人物 / ${allRelations.length} 条关系',
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
