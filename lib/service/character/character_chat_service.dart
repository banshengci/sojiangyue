// lib/service/character/character_chat_service.dart
//
// 角色对话运行时：把「读者说的话」连同蒸馏出来的人物设定一起交给模型，
// 让书中人以自己的口吻回答。这是造梦 chat 能力在松江阅的对应实现。
//
// 设计取舍：
// - 不新建 AI 栈：复用 resolveCurrentModel()（新 provider 体系 / 旧 aiConfig 体系
//   统一解析），与项目其余 AI 链路共用同一份配置。
// - 设定只从本地库读（人物卡 / 关系 / 世界观），对话过程不再消耗蒸馏额度。
// - 历史按轮数截断，避免长会话把上下文撑爆。

import 'package:langchain/langchain.dart';

import 'package:songjiang_reader/dao/character_chat_dao.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_persona.dart';
import 'package:songjiang_reader/service/character/dialogue_review.dart';
import 'package:songjiang_reader/service/character/dialogue_suggestions.dart';
import 'package:songjiang_reader/service/character/world_timeline.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// AI 未配置时抛出的错误（调用方据此提示用户去配置）。
class CharacterChatException implements Exception {
  CharacterChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CharacterChatService {
  CharacterChatService({CharacterChatDao? chatDao, CharacterDao? cardDao})
      : _chatDao = chatDao ?? characterChatDao,
        _cardDao = cardDao ?? characterDao;

  final CharacterChatDao _chatDao;
  final CharacterDao _cardDao;

  /// 单轮上下文最多带多少条历史消息（超出取最近的）。
  static const int maxHistoryMessages = 24;

  /// 生成玩法开局需要的「暗牌」（剧本杀的真相 / 海龟汤的汤底）。
  ///
  /// 只交给模型，不展示给玩家——玩家要靠对话把它问出来。
  Future<String> generateGameplaySecret({
    required GameplayMode mode,
    required String characterName,
    String? bookTitle,
    String? scene,
  }) async {
    final model = resolveCurrentModel();
    if (model == null) {
      throw CharacterChatException('尚未配置 AI 服务，无法开始这个玩法。');
    }
    final prompt = GameplayRuntime.buildSetupPrompt(
      mode: mode,
      characterName: characterName,
      bookTitle: bookTitle,
      scene: scene,
    );
    final buffer = StringBuffer();
    await for (final event
        in model.stream(PromptValue.chat([ChatMessage.humanText(prompt)]))) {
      buffer.write(event.output.content);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw CharacterChatException('模型没有返回开局设定，请检查 AI 服务。');
    }
    SjLog.info('CharacterChat: 玩法暗牌已生成（${mode.id}，${text.length} 字）');
    return text;
  }

  /// 一致性审校：检查「最后一条角色发言」有没有跑偏。
  ///
  /// 一次额外调用，只在用户主动点「检查这一轮」时发生，不自动跑——
  /// 自动审校等于每轮对话多花一倍 token，多数时候并不需要。
  Future<List<ReviewIssue>> reviewLastTurn({
    required CharacterChatSession session,
    required List<CharacterChatMessage> history,
  }) async {
    final model = resolveCurrentModel();
    if (model == null) {
      throw CharacterChatException('尚未配置 AI 服务，无法检查。');
    }
    final last = history.isEmpty ? null : history.last;
    if (last == null || last.role != CharacterChatRole.character) {
      return const [];
    }
    final ctx = await _buildContext(session);
    final card = ctx.main;

    final persona = <String>[
      if (card != null) '姓名：${card.name}',
      if (card?.role != null && card!.role!.isNotEmpty) '身份：${card.role}',
      if (card?.personality != null && card!.personality!.isNotEmpty)
        '性格：${card.personality}',
      if (card?.motivation != null && card!.motivation!.isNotEmpty)
        '所求：${card.motivation}',
      if (card?.background != null && card!.background!.isNotEmpty)
        '背景：${card.background}',
      if (session.userPersona != null && session.userPersona!.isNotEmpty)
        '读者的位置：${participationLabel(session.participation, session.userPersona)}',
    ].join('\n');

    final prompt = buildReviewPrompt(
      characterName: last.speaker ??
          card?.name ??
          displayCastNames(session.characterName),
      replies: last.content,
      personaSummary: persona,
    );

    final messages = <ChatMessage>[
      ChatMessage.system('你是中文小说对话的一致性审校器，只输出 JSON。'),
      ..._historyToMessages(history.take(8).toList()),
      ChatMessage.humanText(prompt),
    ];

    final buffer = StringBuffer();
    await for (final event in model.stream(PromptValue.chat(messages))) {
      buffer.write(event.output.content);
    }
    return parseReviewIssues(buffer.toString());
  }

  /// 「帮我写下一句」：代拟几条可以直接发出去的台词。
  ///
  /// 与 [readMind] 相反——读心是角色心里的话，这里是**读者**要说的话。
  /// 一次调用拿 3 条，失败返回空列表（UI 侧提示"没写出来"，不阻塞对话）。
  Future<List<ChatSuggestion>> suggestNextLine({
    required CharacterChatSession session,
    required List<CharacterChatMessage> history,
    int count = 3,
  }) async {
    final model = resolveCurrentModel();
    if (model == null) {
      throw CharacterChatException('尚未配置 AI 服务，无法代笔。');
    }
    final latest = history.isEmpty ? '' : history.last.content.trim();
    if (latest.isEmpty) return const [];

    final speaker = onStageNames(session.characterName).join('、');
    final prompt = buildSuggestionPrompt(
      characterName: speaker.isEmpty ? session.characterName : speaker,
      latestReply: latest,
      userPersona: session.userPersona,
      participationCode: session.participation.code,
      count: count,
    );

    final messages = <ChatMessage>[
      ChatMessage.system(
        [
          '你在为一款中文互动小说代笔，读者要发出去的下一句话由你拟。',
          buildMemorySection(session.memorySummary),
        ].where((s) => s.trim().isNotEmpty).join('\n'),
      ),
      ..._historyToMessages(history.take(8).toList()),
      ChatMessage.humanText(prompt),
    ];

    final buffer = StringBuffer();
    await for (final event in model.stream(PromptValue.chat(messages))) {
      buffer.write(event.output.content);
    }
    return parseSuggestions(buffer.toString(), max: count);
  }

  /// 读心：让角色把「没说出口的念头」写出来。
  ///
  /// 与正常回复共用同一份人物设定，但指令要求它写内心活动而非台词，
  /// 结果以旁白（narrator）落库，既不给角色看，也不进后续上下文。
  ///
  /// 返回里带上「这是谁的心里话」：群聊会话的 `characterName` 是
  /// `bookId:姓名,...` 的内部编码，由界面自己拼标签就会印出
  /// `（1:姬动,1:烈焰,... 心里）`——所以标签统一在这里定。
  Future<({String name, String text})> readMind({
    required CharacterChatSession session,
    required List<CharacterChatMessage> history,
  }) async {
    final model = resolveCurrentModel();
    if (model == null) {
      throw CharacterChatException('尚未配置 AI 服务，无法读心。');
    }
    final ctx = await _buildContext(session);
    if (ctx.main == null) {
      throw CharacterChatException('没有人物数据，请先做一次人物蒸馏。');
    }

    final system = buildCharacterSystemPrompt(
      character: ctx.main!,
      relations: ctx.relations,
      world: ctx.world,
    );
    final timelineSection = await _timelineSection(session.bookId);

    final messages = <ChatMessage>[
      // 更早对话的折叠记忆接在 system 末尾：
      // 历史窗口只有 maxHistoryMessages 条，超出会被静默丢弃，
      // 不补这段的话长对话里角色会"忘事"。
      ChatMessage.system(
        [
          system,
          buildMemorySection(session.memorySummary),
          timelineSection,
        ].where((s) => s.trim().isNotEmpty).join('\n'),
      ),
      ..._historyToMessages(history),
      ChatMessage.humanText(
        '（现在不要说出口：写下你此刻心里真正翻腾的念头。）\n'
        '只写你心里的话，用第一人称，说话的味道和你平时一样，不修饰、不端着。\n'
        '必须是「你刚才那番话」里没有说出来的新东西——'
        '真实的判断、欲望、戒备、害怕、嫉妒、犹豫，或者瞒着对方的打算。\n'
        '不要写：环境与天气、动作与神态、物件与光线；'
        '不要用第三人称分析自己；不要复述或改写你刚说过的话；'
        '不要用括号或星号演动作。\n'
        '如果此刻心里确实没有什么值得说的，就只回四个字「（无）」，不要用景物描写凑数。\n'
        '80 字以内。',
      ),
    ];

    final buffer = StringBuffer();
    await for (final event in model.stream(PromptValue.chat(messages))) {
      buffer.write(event.output.content);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw CharacterChatException('模型没有返回内容，请检查 AI 服务配置。');
    }
    // 模型按指令回「（无）」时给一句人话，而不是把括号原样显示出来
    if (text.replaceAll(RegExp(r'[（）()\s]'), '').isEmpty ||
        text.replaceAll(RegExp(r'[（）()\s]'), '') == '无') {
      throw CharacterChatException('TA 此刻没有特别在想什么。');
    }
    return (
      name: displayCharacterName(session.characterName, primary: ctx.main?.name),
      text: text,
    );
  }

  /// 历史消息 → langchain 消息（跳过旁白）。
  List<ChatMessage> _historyToMessages(List<CharacterChatMessage> history) {
    final recent = history.length > maxHistoryMessages
        ? history.sublist(history.length - maxHistoryMessages)
        : history;
    final out = <ChatMessage>[];
    for (final m in recent) {
      if (m.content.trim().isEmpty) continue;
      if (m.role == CharacterChatRole.narrator) continue;
      out.add(m.role == CharacterChatRole.user
          ? ChatMessage.humanText(m.content)
          : ChatMessage.ai(_withSpeaker(m)));
    }
    return out;
  }

  /// 组装一次对话所需的全部上下文（人物卡 / 关系 / 世界观）。
  Future<_ChatContext> _buildContext(
    CharacterChatSession session, {
    String? extraDirective,
  }) async {
    final refs = parseMemberRefs(session.characterName, session.bookId);

    // 同一本书的卡只查一次（穿越场景可能涉及多本书）
    final byBook = <int, Map<String, CharacterCard>>{};
    Future<Map<String, CharacterCard>> cardsOf(int bookId) async {
      if (byBook.containsKey(bookId)) return byBook[bookId]!;
      final cards = await _cardDao.getCharacters(bookId);
      final map = {for (final c in cards) c.name: c};
      byBook[bookId] = map;
      return map;
    }

    final onStage = <CharacterCard>[];
    for (final r in refs) {
      final card = (await cardsOf(r.bookId))[r.name];
      if (card != null) onStage.add(card);
    }
    final main = onStage.isEmpty ? null : onStage.first;

    // 关系与世界观只取主角所在的那本书：跨书人物之间本来就没有蒸馏出的关系。
    final mainBookId = main == null
        ? session.bookId
        : refs.isNotEmpty
            ? refs.first.bookId
            : session.bookId;
    final relations = main == null
        ? <CharacterRelation>[]
        : await _cardDao.getRelationsForCharacter(mainBookId, main.name);
    final world = await _cardDao.getWorldSettings(mainBookId);

    return _ChatContext(
      main: main,
      onStage: onStage,
      relations: relations,
      world: world,
      extraDirective: extraDirective,
    );
  }

  /// 流式生成角色的回复。
  ///
  /// [history] 为已落库的完整历史（按时间正序）；本方法内部按
  /// [maxHistoryMessages] 截断。yield 的是**累积后的完整文本**，
  /// 便于 UI 直接整体替换气泡内容。
  Stream<String> reply({
    required CharacterChatSession session,
    required List<CharacterChatMessage> history,
    required String input,
    bool continueScene = false,
    /// 「继续演出」用的舞台指令；为空时用默认的 continueNudge。
    String? continueInstruction,
    /// 重写指令：附在用户发言之后，用于「按问题重写这一轮」。
    String? rewriteInstruction,
    String? extraDirective,
  }) async* {
    final model = resolveCurrentModel();
    if (model == null) {
      throw CharacterChatException(
        '尚未配置 AI 服务，无法与角色对话。请到「设置 → AI」中配置服务与密钥。',
      );
    }

    final ctx = await _buildContext(session, extraDirective: extraDirective);
    if (ctx.main == null && session.mode == CharacterChatMode.single) {
      throw CharacterChatException(
          '没有找到「${displayCastNames(session.characterName)}」的人物数据，请先对全书做一次人物蒸馏。');
    }

    final system = session.mode == CharacterChatMode.group
        ? buildGroupSystemPrompt(
            characters: ctx.onStage,
            relations: ctx.relations,
            // 群聊也要吃世界观，否则「锁定事实」只在单人对话里生效
            world: ctx.world,
            // 读者姿态（旁观/扮演/入场）决定模型怎么对待读者的发言
            participation: session.participation,
            userPersona: session.userPersona,
          )
        : buildCharacterSystemPrompt(
            character: ctx.main!,
            relations: ctx.relations,
            world: ctx.world,
            extraDirective: extraDirective,
            participation: session.participation,
            userPersona: session.userPersona,
          );

    final timelineSection = await _timelineSection(session.bookId);

    final messages = <ChatMessage>[
      // 更早对话的折叠记忆接在 system 末尾：
      // 历史窗口只有 maxHistoryMessages 条，超出会被静默丢弃，
      // 不补这段的话长对话里角色会"忘事"。
      ChatMessage.system(
        [
          system,
          buildMemorySection(session.memorySummary),
          timelineSection,
        ].where((s) => s.trim().isNotEmpty).join('\n'),
      ),
      ..._historyToMessages(history),
      ChatMessage.humanText(
        continueScene
            ? (continueInstruction ?? continueNudge)
            : [input, if (rewriteInstruction != null) rewriteInstruction]
                .where((s) => s.trim().isNotEmpty)
                .join('\\n\\n'),
      ),
    ];

    final buffer = StringBuffer();
    try {
      await for (final event in model.stream(PromptValue.chat(messages))) {
        final delta = event.output.content;
        if (delta.isEmpty) continue;
        buffer.write(delta);
        yield buffer.toString();
      }
    } catch (e, st) {
      SjLog.warning('CharacterChat: 生成回复失败: $e\n$st');
      rethrow;
    }

    if (buffer.isEmpty) {
      throw CharacterChatException('模型没有返回任何内容，请检查 AI 服务配置。');
    }
  }

  /// 让角色先开口（新会话的开场白）。
  Future<String> greeting(CharacterChatSession session) async {
    final model = resolveCurrentModel();
    if (model == null) {
      throw CharacterChatException('尚未配置 AI 服务，无法与角色对话。');
    }
    final ctx = await _buildContext(session);
    if (ctx.main == null) {
      throw CharacterChatException('没有人物数据，请先做一次人物蒸馏。');
    }
    final system = buildCharacterSystemPrompt(
      character: ctx.main!,
      relations: ctx.relations,
      world: ctx.world,
    );
    final prompt = PromptValue.chat([
      ChatMessage.system(system),
      ChatMessage.humanText(
        '（这是你们第一次见面。用你自己的口吻说一句话开场：或自我介绍，'
        '或就你眼下正在发愁的事起个话头。不要写动作描写，只说你要说的话，'
        '控制在 80 字以内。）',
      ),
    ]);

    final buffer = StringBuffer();
    await for (final event in model.stream(prompt)) {
      buffer.write(event.output.content);
    }
    return buffer.toString().trim();
  }

  /// 取本书的时间线段落。失败时返回空串——时间线缺失不该让对话报错。
  Future<String> _timelineSection(int bookId) async {
    try {
      final events = await _cardDao.getTimeline(bookId);
      return buildTimelineSection(events);
    } catch (_) {
      return '';
    }
  }
  /// 待折叠消息达到这个数量才触发一次压缩（避免每轮都多烧一次调用）。
  static const int memoryTriggerMessages = 40;

  /// 每次压缩多少条（压完记下压到哪条，下次从它之后继续）。
  static const int memoryChunkMessages = 20;

  /// 把更早的对话折叠进记忆。
  ///
  /// 为什么需要：`maxHistoryMessages = 24`，超出窗口的消息会被直接丢弃，
  /// 于是长对话里角色会忘记刚发生过的约定与秘密。这里把超出部分压成一段
  /// 第一人称备忘存进会话，以后每轮都带上（见 [buildMemorySection]）。
  ///
  /// 设计约束：
  /// * **失败绝不抛出**——记忆是增强，不能因为它断了对话
  /// * 增量折叠：`memory_upto_message_id` 记录已压到哪，不重复压同一段
  /// * 在后台跑（调用方不 await），用户不该等它
  Future<void> refreshMemory(int sessionId) async {
    try {
      final model = resolveCurrentModel();
      if (model == null) return;

      final session = await characterChatDao.getSession(sessionId);
      if (session == null) return;

      final pending = await characterChatDao.listMessagesAfter(
        sessionId,
        afterId: session.memoryUptoMessageId ?? 0,
      );
      if (pending.length < memoryTriggerMessages) return;

      final chunk = pending.take(memoryChunkMessages).toList();
      final lastId = chunk.last.id;
      if (lastId == null) return;

      final dialogue = buildMemoryDialogue(
        chunk
            .map((m) => (speaker: m.speaker ?? '', content: m.content))
            .toList(),
      );
      if (dialogue.trim().isEmpty) return;

      final prompt = buildMemorySummaryPrompt(
        characterName: displayCastNames(session.characterName),
        previousSummary: session.memorySummary ?? '',
        dialogue: dialogue,
      );

      final buffer = StringBuffer();
      await for (final event
          in model.stream(PromptValue.chat([ChatMessage.humanText(prompt)]))) {
        buffer.write(event.output.content);
      }
      final summary = buffer.toString().trim();
      if (summary.isEmpty) return;

      await characterChatDao.updateMemory(
        sessionId,
        summary: summary,
        uptoMessageId: lastId,
      );
    } catch (e) {
      SjLog.warning('CharacterChat: 记忆折叠失败（已忽略）: $e');
    }
  }

  /// 为首轮对话自动生成标题；失败时返回 null（调用方保持原样，不打断主流程）。
  Future<String?> generateTitle({
    required CharacterChatSession session,
    required String firstUserMessage,
    required String firstReply,
  }) async {
    final model = resolveCurrentModel();
    if (model == null) return null;
    try {
      final prompt = buildTitlePrompt(
        characterName: displayCastNames(session.characterName),
        firstUserMessage: firstUserMessage,
        firstReply: firstReply,
      );
      final buffer = StringBuffer();
      await for (final event
          in model.stream(PromptValue.chat([ChatMessage.humanText(prompt)]))) {
        buffer.write(event.output.content);
      }
      return _cleanTitle(buffer.toString());
    } catch (e) {
      SjLog.warning('CharacterChat: 生成会话标题失败: $e');
      return null;
    }
  }

  // ---- 持久化便捷方法 ----

  Future<int> saveUserMessage(int sessionId, String content) =>
      _chatDao.appendMessage(
        sessionId: sessionId,
        role: CharacterChatRole.user,
        content: content,
      );

  Future<int> saveCharacterMessage(
    int sessionId,
    String speaker,
    String content,
  ) =>
      _chatDao.appendMessage(
        sessionId: sessionId,
        role: CharacterChatRole.character,
        speaker: speaker,
        content: content,
      );

  Future<void> touch(int sessionId) => _chatDao.touchSession(sessionId);

  String _withSpeaker(CharacterChatMessage m) =>
      (m.speaker == null || m.speaker!.isEmpty)
          ? m.content
          : '${m.speaker}：${m.content}';

  /// 清洗标题：去引号、去「标题：」前缀、限长。
  String? _cleanTitle(String raw) {
    var t = raw.trim().replaceAll(RegExp(r'[\n\r]+'), ' ');
    t = t.replaceAll(RegExp(r'^["“”「」『』\s]*'), '');
    t = t.replaceAll(RegExp(r'["“”「」『』\s]*$'), '');
    t = t.replaceFirst(RegExp(r'^标题[：:]\s*'), '');
    if (t.isEmpty) return null;
    if (t.length > 24) t = t.substring(0, 24);
    return t;
  }
}

/// 一次对话所需的上下文快照。
class _ChatContext {
  _ChatContext({
    required this.main,
    required this.onStage,
    required this.relations,
    required this.world,
    this.extraDirective,
  });

  final CharacterCard? main;

  /// 在场人物（群聊时为全部，单人时为 [main]）。
  final List<CharacterCard> onStage;
  final List<CharacterRelation> relations;
  final List<WorldSetting> world;
  final String? extraDirective;
}
/// 「继续演出」时代替用户发言的推进信号。
///
/// 旁观模式下用户不发言，但每轮请求仍需要一条 human 消息来驱动
/// （详见 chat 页 `_advance` 的注释）。这条不发用户气泡、不落库，
/// 只作为本轮的舞台指令存在。
const String continueNudge =
    '【继续演出】接着往下推进这一幕：让人物继续各自的行动与对话，'
    '不要停下来等读者发言，也不要复述已经写过的内容。';
