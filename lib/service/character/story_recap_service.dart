// lib/service/character/story_recap_service.dart
//
// 剧情回顾（前情提要）：读到某处，把前面发生了什么讲清楚。
//
// 造梦 feature/storyrecap 的对应能力。token 策略上分三档，优先用便宜的：
//   1) 蒸馏过 → 直接用本地时间线事件（零额外读取，最省）
//   2) 有世界观/人物 → 事件 + 主要人物，补一层上下文
//   3) 都没有 → 用目标章之前的章节标题 + 每章开头一小段（截断，避免整本塞进去）
//
// 结果按 (bookId, chapterIndex) 缓存进 tb_story_recaps，重复查看不再调用模型。

import 'package:langchain/langchain.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';

class StoryRecapService {
  StoryRecapService({required this.repository, CharacterDao? cardDao})
      : _cardDao = cardDao ?? characterDao;

  final CharacterDistillRepository repository;
  final CharacterDao _cardDao;

  /// 生成「读到第 [chapterIndex] 章之前」的前情提要。
  ///
  /// [chapterIndex] 为 0 表示开篇（没有前情），调用方应避免发起。
  Future<String> generate({
    required int bookId,
    required int chapterIndex,
    required BaseChatModel model,
  }) async {
    final chapters = await repository.getChapters(bookId);
    if (chapters.isEmpty) {
      throw StateError('未从书中提取到正文（当前仅支持 EPUB / TXT）');
    }
    final target = chapterIndex.clamp(0, chapters.length);
    if (target <= 0) return '这是全书开头，还没有前情可言。';
    final before = chapters.sublist(0, target);

    final events = await _cardDao.getTimeline(bookId);
    final cards = await _cardDao.getCharacters(bookId);

    final material = _buildMaterial(
      before: before,
      events: events,
      cards: cards,
      targetTitle: target < chapters.length
          ? chapters[target].title
          : '全书之后',
    );

    final prompt = PromptValue.chat([
      ChatMessage.system(_systemPrompt),
      ChatMessage.humanText(material),
    ]);

    final buffer = StringBuffer();
    await for (final event in model.stream(prompt)) {
      buffer.write(event.output.content);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw StateError('模型没有返回内容，请检查 AI 服务配置');
    }
    return text;
  }

  static const String _systemPrompt = '''
你是一个帮读者回忆剧情的中文小说助读。

用户会给你这本书到某一处为止的全部已知信息（可能是时间线事件，也可能是章节标题与片段）。
请写一段「前情提要」，让读者快速想起：

1. 谁牵涉其中、他们各自想干什么；
2. 事情是怎么一步步发展到现在的（按因果，不要简单罗列）；
3. 有哪些尚未解决的悬念或伏笔。

要求：
- 只写材料里有的内容，不要臆造情节，也不要预测后面的发展；
- 用平实的叙述，不要用"综上所述"这种总结腔，也不要加标题和序号；
- 控制在 250 字以内；材料不足以支撑时，就写你知道的那部分。''';

  /// 组装喂给模型的材料（按可用信息便宜到贵排序）。
  String _buildMaterial({
    required List<BookChapter> before,
    required List<TimelineEvent> events,
    required List<CharacterCard> cards,
    required String targetTitle,
  }) {
    final buf = StringBuffer();
    buf.writeln('读者已经读到：$targetTitle');
    buf.writeln('在此之前共 ${before.length} 章。');
    buf.writeln();

    // 1) 蒸馏过的时间线：最省且结构化
    final relevantEvents = events
        .where((e) => _isBefore(e.chapter, targetTitle, before))
        .toList();
    if (relevantEvents.isNotEmpty) {
      buf.writeln('## 已知事件时间线');
      for (final e in relevantEvents.take(40)) {
        final note = (e.timeNote != null && e.timeNote!.isNotEmpty)
            ? '（${e.timeNote}）'
            : '';
        final desc = (e.description != null && e.description!.isNotEmpty)
            ? '：${e.description}'
            : '';
        buf.writeln('- ${e.title}$note$desc');
      }
      buf.writeln();
    }

    // 2) 主要人物：帮助模型分清谁是谁
    if (cards.isNotEmpty) {
      buf.writeln('## 主要人物');
      for (final c in cards.take(12)) {
        final role = (c.role != null && c.role!.isNotEmpty) ? '（${c.role}）' : '';
        final want =
            (c.motivation != null && c.motivation!.isNotEmpty) ? '，所求：${c.motivation}' : '';
        buf.writeln('- ${c.name}$role$want');
      }
      buf.writeln();
    }

    // 3) 兜底：章节标题 + 每章开头一小段
    if (relevantEvents.isEmpty && cards.isEmpty) {
      buf.writeln('## 各章开头');
      for (final ch in before.take(60)) {
        final snippet = ch.text.length > 200 ? ch.text.substring(0, 200) : ch.text;
        buf.writeln('### ${ch.title}');
        buf.writeln(snippet.replaceAll(RegExp(r'\s+'), ' '));
        buf.writeln();
      }
    }

    return buf.toString().trim();
  }

  /// 判断某事件是否发生在目标章之前。
  ///
  /// 事件里存的是章节标题（蒸馏时由模型标注），这里做宽松匹配：
  /// 标题出现在「目标章之前那些章」的标题集合里就算。
  bool _isBefore(
    String? eventChapter,
    String targetTitle,
    List<BookChapter> before,
  ) {
    if (eventChapter == null || eventChapter.trim().isEmpty) return true;
    final ec = eventChapter.trim();
    if (ec == targetTitle) return false;
    return before.any((c) => c.title.trim() == ec || c.title.contains(ec));
  }
}
