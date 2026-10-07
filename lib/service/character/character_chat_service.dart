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
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_persona.dart';
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

  /// 跨书成员引用格式：`bookId:人物名`，多个以逗号分隔。
  ///
  /// 穿越联动场景用这种写法把一个会话的主角挂到多本书上——
  /// 会话表不必额外加字段，解析时按 bookId 分别取卡即可。
  static String encodeMemberRefs(
    List<({int bookId, String name})> refs,
  ) =>
      refs.map((r) => '${r.bookId}:${r.name}').join(',');

  /// 解析会话里的成员引用；不是 `bookId:name` 形式时按 [defaultBookId] 兜底。
  static List<({int bookId, String name})> parseMemberRefs(
    String raw,
    int defaultBookId,
  ) {
    final out = <({int bookId, String name})>[];
    for (final token in raw.split(RegExp(r'[,，]'))) {
      final t = token.trim();
      if (t.isEmpty) continue;
      final m = RegExp(r'^(\d+)\s*[:：]\s*(.+)$').firstMatch(t);
      if (m != null) {
        out.add((bookId: int.parse(m.group(1)!), name: m.group(2)!.trim()));
      } else {
        out.add((bookId: defaultBookId, name: t));
      }
    }
    return out;
  }

  /// 读心：让角色把「没说出口的念头」写出来。
  ///
  /// 与正常回复共用同一份人物设定，但指令要求它写内心活动而非台词，
  /// 结果以旁白（narrator）落库，既不给角色看，也不进后续上下文。
  Future<String> readMind({
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
    final messages = <ChatMessage>[
      ChatMessage.system(system),
      ..._historyToMessages(history),
      ChatMessage.humanText(
        '（现在不要说出口：写下你此刻心里真正翻腾的念头。'
        '可以是没说出口的判断、顾虑、算计或情绪，口气跟平时一样不加修饰。'
        '只写心里想的，80 字以内。）',
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
    return text;
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
          '没有找到「${session.characterName}」的人物数据，请先对全书做一次人物蒸馏。');
    }

    final system = session.mode == CharacterChatMode.group
        ? buildGroupSystemPrompt(
            characters: ctx.onStage,
            relations: ctx.relations,
          )
        : buildCharacterSystemPrompt(
            character: ctx.main!,
            relations: ctx.relations,
            world: ctx.world,
            extraDirective: extraDirective,
          );

    final messages = <ChatMessage>[
      ChatMessage.system(system),
      ..._historyToMessages(history),
      ChatMessage.humanText(input),
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
        characterName: session.characterName,
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
