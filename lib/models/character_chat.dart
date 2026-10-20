// lib/models/character_chat.dart
//
// 角色对话（造梦 chat / sessions 对应能力）的持久化模型。
//
// 一个会话 = 一位书中人物 + 一段对话；消息按角色分侧存储，
// 便于日后扩展「群聊 / @提及」：群聊会话的 characterName 存逗号分隔的多人，
// 每条消息用 speaker 记录这句话是谁说的。

/// 会话模式。
enum CharacterChatMode {
  /// 与单个人物对话。
  single('single'),

  /// 多人同场（群聊旁观 / @提及）。
  group('group');

  const CharacterChatMode(this.code);

  final String code;

  static CharacterChatMode fromCode(String? code) =>
      CharacterChatMode.values.firstWhere(
        (m) => m.code == code,
        orElse: () => CharacterChatMode.single,
      );
}

/// 读者在会话中的参与方式（造梦的三种开局姿态）。
///
/// 它决定 system prompt 里「你是谁、你能不能说话」：
///  - spectator 旁观：人物自行推进，读者不发言
///  - roleplay 扮演：读者就是书中某个人物（见 userPersona）
///  - join 入场：读者以自己的身份出现，人物知道"有个外来者"
enum CharacterParticipation {
  /// 旁观。
  spectator('spectator', '旁观'),

  /// 扮演（代入书中人物）。
  roleplay('roleplay', '扮演'),

  /// 入场（以自己的身份加入）。
  join('join', '入场');

  const CharacterParticipation(this.code, this.label);

  final String code;

  /// 中文展示名。
  final String label;

  static CharacterParticipation fromCode(String? code) =>
      CharacterParticipation.values.firstWhere(
        (p) => p.code == code,
        orElse: () => CharacterParticipation.spectator,
      );
}

/// 分支时能否沿用源会话的记忆。
///
/// 记忆是「压到某条消息为止」的摘要。若分叉点**早于**已压范围，
/// 新分支就会"记得"它其实还没经历过的后续——必须丢掉，让它重新累积。
/// 返回 null 表示这条分支不该带记忆。
String? memoryForFork({
  required String? summary,
  required int? upto,
  required int? atMessageId,
}) {
  final text = summary?.trim() ?? '';
  if (text.isEmpty) return null;
  // 从头分叉（或不指定位置）：记忆覆盖的就是已发生的一切，可以沿用
  if (atMessageId == null) return text;
  // 不知道压到哪，无法判断，保守丢弃
  if (upto == null) return null;
  return upto <= atMessageId ? text : null;
}

/// 一条对话消息的发言方。
enum CharacterChatRole {
  /// 读者。
  user('user'),

  /// 书中人物。
  character('character'),

  /// 旁白 / 系统提示（不入模型上下文的展示用文本）。
  narrator('narrator');

  const CharacterChatRole(this.code);

  final String code;

  static CharacterChatRole fromCode(String? code) =>
      CharacterChatRole.values.firstWhere(
        (r) => r.code == code,
        orElse: () => CharacterChatRole.character,
      );
}

/// 角色对话会话。
class CharacterChatSession {
  const CharacterChatSession({
    this.id,
    required this.bookId,
    required this.characterName,
    this.title,
    this.mode = CharacterChatMode.single,
    this.participation = CharacterParticipation.spectator,
    this.userPersona,
    this.memorySummary,
    this.memoryUptoMessageId,
    this.parentSessionId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;

  /// 主角姓名；群聊为逗号分隔的多个姓名。
  final String characterName;

  /// 会话标题，首轮对话后由 AI 自动生成。
  final String? title;
  final CharacterChatMode mode;

  /// 读者姿态：旁观 / 扮演 / 入场。
  final CharacterParticipation participation;

  /// 读者身份。
  ///  - 扮演时为所代入的**书中人物名**
  ///  - 入场时为读者自定义的名字
  ///  - 旁观时为 null
  final String? userPersona;

  /// 更早对话的折叠记忆（由 CharacterChatService.refreshMemory 生成）。
  final String? memorySummary;

  /// 记忆已覆盖到哪条消息（含）；更早的消息不必再压。
  final int? memoryUptoMessageId;

  /// 这条时间线从哪个会话分出来的（null = 主线）。
  /// 有了它才能回答「回到主线」「还有哪些同源分支」。
  final int? parentSessionId;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 展示名：没有标题时回退为人物名。
  ///
  /// 群聊会话的 `characterName` 是 `bookId:姓名,...` 的内部编码，
  /// 直接当标题用会显示成「1:姬动,1:烈焰,…」，而且长得把标题栏撑爆。
  String get displayTitle {
    final t = title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final names = onStageNames(characterName);
    if (names.isEmpty) return characterName.trim();
    if (names.length <= 3) return names.join('、');
    return '${names.take(3).join('、')} 等 ${names.length} 人';
  }

  /// 群聊 / 单人：按逗号拆分姓名（剥掉 `bookId:` 前缀）。
  List<String> get characterNames => onStageNames(characterName);

  CharacterChatSession copyWith({
    int? id,
    String? title,
    CharacterChatMode? mode,
    CharacterParticipation? participation,
    String? userPersona,
    String? memorySummary,
    int? memoryUptoMessageId,
    int? parentSessionId,
    DateTime? updatedAt,
  }) =>
      CharacterChatSession(
        id: id ?? this.id,
        bookId: bookId,
        characterName: characterName,
        title: title ?? this.title,
        mode: mode ?? this.mode,
        participation: participation ?? this.participation,
        userPersona: userPersona ?? this.userPersona,
        memorySummary: memorySummary ?? this.memorySummary,
        memoryUptoMessageId: memoryUptoMessageId ?? this.memoryUptoMessageId,
        parentSessionId: parentSessionId ?? this.parentSessionId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory CharacterChatSession.fromMap(Map<String, dynamic> map) =>
      CharacterChatSession(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        characterName: map['character_name'] as String,
        title: map['title'] as String?,
        mode: CharacterChatMode.fromCode(map['mode'] as String?),
        participation:
            CharacterParticipation.fromCode(map['participation'] as String?),
        userPersona: map['user_persona'] as String?,
        memorySummary: map['memory_summary'] as String?,
        memoryUptoMessageId: map['memory_upto_message_id'] as int?,
        parentSessionId: map['parent_session_id'] as int?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'character_name': characterName,
        'title': title,
        'mode': mode.code,
        'participation': participation.code,
        'user_persona': userPersona,
        'memory_summary': memorySummary,
        'memory_upto_message_id': memoryUptoMessageId,
        'parent_session_id': parentSessionId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 会话中的一条消息。
class CharacterChatMessage {
  const CharacterChatMessage({
    this.id,
    required this.sessionId,
    required this.role,
    this.speaker,
    required this.content,
    required this.createdAt,
  });

  final int? id;
  final int sessionId;
  final CharacterChatRole role;

  /// 发言者姓名（role 为 character / narrator 时有意义）。
  final String? speaker;
  final String content;
  final DateTime createdAt;

  factory CharacterChatMessage.fromMap(Map<String, dynamic> map) =>
      CharacterChatMessage(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        role: CharacterChatRole.fromCode(map['role'] as String?),
        speaker: map['speaker'] as String?,
        content: map['content'] as String? ?? '',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'role': role.code,
        'speaker': speaker,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };
}
/// 姿态的展示文案（会话页标题下方那一行）。
///
/// 扮演/入场要带上身份，否则用户只看到"扮演"两个字，
/// 想不起来自己这局演的是谁。
String participationLabel(
  CharacterParticipation participation,
  String? userPersona,
) {
  final who = userPersona?.trim() ?? '';
  switch (participation) {
    case CharacterParticipation.spectator:
      return '旁观';
    case CharacterParticipation.roleplay:
      return who.isEmpty ? '扮演' : '扮演 · $who';
    case CharacterParticipation.join:
      return who.isEmpty ? '入场' : '入场 · $who';
  }
}
/// 从会话的 `characterName` 取出可读的在场人物名。
///
/// 群聊会话存的是 `bookId:姓名` 的逗号串（见
/// `CharacterChatService.encodeMemberRefs`），直接拿去展示或塞进 prompt
/// 会露出 `1:` 这种内部编码。
List<String> onStageNames(String characterName) => characterName
    .split(RegExp(r'[,，]'))
    .map((e) {
      final i = e.indexOf(':');
      return i >= 0 ? e.substring(i + 1) : e;
    })
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// 群聊回复形如「林黛玉：内容」，把说话人和正文拆开。
///
/// 只在回复**以在场某个名字开头**时才认；认不出来就返回空 speaker，
/// 由调用方回退——猜错说话人比不猜更糟，会把台词安到别人头上。
///
/// 「开头」允许被一层引号包着：模型很爱把整句台词写成
/// `「弗瑞：黑暗天机，三日内……」`，直接按字符串开头匹配会认不出，
/// 于是整段落到"第一个在场者"头上（群聊里就是满屏张冠李戴）。
/// 跳过开引号再认一次，但正文里仍保留那对引号——这是它的文体，不是噪音。
({String speaker, String text}) splitSpokenLine(
  String reply,
  List<String> onStage,
) {
  final trimmed = reply.trim();
  final direct = _matchSpeakerPrefix(trimmed, onStage);
  if (direct != null) return direct;

  final quote = _leadingQuote(trimmed);
  if (quote.isNotEmpty) {
    final hit = _matchSpeakerPrefix(trimmed.substring(quote.length), onStage);
    if (hit != null) {
      return (
        speaker: hit.speaker,
        text: quote + hit.text,
      );
    }
  }
  return (speaker: '', text: trimmed);
}

/// 一段发言：说话人 + 正文。
///
/// [speaker] 为空表示这是旁白（没有人在说），界面上不该给它挂名字。
class ChatSegment {
  const ChatSegment({required this.speaker, required this.text});

  final String speaker;
  final String text;

  bool get isNarration => speaker.isEmpty;

  @override
  String toString() => isNarration ? '旁白($text)' : '$speaker($text)';
}

/// 把一整段回复按「姓名：」切成若干段发言。
///
/// 为什么需要：[splitSpokenLine] 只认开头的第一个说话人，于是一个回合里
/// 弗瑞、姬动、陈思璇、阿金轮着说话时，整段会堆进「弗瑞」那一张卡片，
/// 看起来像他一个人替全场说了话。这里按行切，让每张卡片只放一个人。
///
/// 规则：
/// * 每行开头若是「在场者姓名 + 冒号」，就另起一段；认不出的行并入上一段
/// * [firstSpeaker] 是调用方已经剥掉的那层前缀（落库时被 strip 掉了），
///   喂给第一段，否则开头那句旁白会没有归属
/// * 整段就是一对括注「（……）」的，判成旁白——那是场景描写，不是谁在说话；
///   但「（动作）台词」不算，括号只开了个头，后面还有台词
///
/// 切分只发生在渲染层，落库仍然是一回合一条：回合数、上下文窗口、
/// 记忆折叠、分支回滚都按「一条 = 一回合」算，这里不动它们。
List<ChatSegment> splitSpokenBlock(
  String content, {
  String? firstSpeaker,
  List<String> onStage = const [],
}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const [];

  final segments = <ChatSegment>[];
  final buffer = <String>[];
  var speaker = (firstSpeaker ?? '').trim();

  void flush() {
    final text = buffer.join('\n').trim();
    buffer.clear();
    if (text.isNotEmpty) {
      segments.add(ChatSegment(speaker: speaker, text: text));
    }
  }

  for (final line in trimmed.split('\n')) {
    final hit = _matchSpeakerLine(line, onStage);
    if (hit != null) {
      flush();
      speaker = hit.speaker;
      buffer.add(hit.text);
      continue;
    }
    // 独立成段的纯括注是旁白：前后台词都要断开，不能并进上一个人的嘴里
    final t = line.trim();
    if (t.isNotEmpty && _isPureAside(t)) {
      flush();
      segments.add(ChatSegment(speaker: '', text: t));
      continue;
    }
    buffer.add(line);
  }
  flush();

  return [
    for (final s in segments)
      // 有名字但整段是括注：那是旁白，别挂在人头上
      if (!s.isNarration && _isPureAside(s.text))
        ChatSegment(speaker: '', text: s.text)
      else
        s,
  ];
}

/// 单行开头的说话人：直接认，认不出再跳过一层开引号认。
({String speaker, String text})? _matchSpeakerLine(
  String line,
  List<String> onStage,
) {
  final t = line.trim();
  if (t.isEmpty) return null;
  final direct = _matchSpeakerPrefix(t, onStage);
  if (direct != null) return direct;

  final quote = _leadingQuote(t);
  if (quote.isEmpty) return null;
  final hit = _matchSpeakerPrefix(t.substring(quote.length), onStage);
  if (hit == null) return null;
  // 引号是它的文体，留在正文里
  return (speaker: hit.speaker, text: quote + hit.text);
}

/// 整段是否只是一对括注（场景描写）。
bool _isPureAside(String text) {
  final t = text.trim();
  if (t.length < 2) return false;
  final opens = t.startsWith('（') || t.startsWith('(');
  final closes = t.endsWith('）') || t.endsWith(')');
  return opens && closes;
}

/// 开头若是开引号，返回它；否则空串。
String _leadingQuote(String text) {
  const opens = ['「', '『', '“', '‘', '"', '（', '《'];
  for (final q in opens) {
    if (text.startsWith(q)) return q;
  }
  return '';
}

/// `名字 + 冒号` 开头时拆开；否则返回 null。
({String speaker, String text})? _matchSpeakerPrefix(
  String text,
  List<String> onStage,
) {
  for (final name in onStage) {
    for (final sep in const [':', '：']) {
      final prefix = '$name$sep';
      if (text.startsWith(prefix)) {
        return (
          speaker: name,
          text: text.substring(prefix.length).trim(),
        );
      }
    }
  }
  return null;
}

/// 旁白/读心这类块要显示的「这是谁」。
///
/// 群聊会话的 `characterName` 是 `bookId:姓名,...` 的内部编码，
/// 直接印到界面上就是 `（1:姬动,1:烈焰,... 心里）`。优先用主人物名，
/// 没有主人物时退回在场第一位——总比露出一串编码强。
String displayCharacterName(String characterName, {String? primary}) {
  final p = (primary ?? '').trim();
  if (p.isNotEmpty) return p;
  final names = onStageNames(characterName);
  if (names.isNotEmpty) return names.first;
  return characterName.trim();
}

/// 给提示词用的在场名单：「姬动、烈焰、黑暗天机」。
///
/// 提示词里塞 `1:姬动,1:烈焰` 会让模型跟着学这个格式，
/// 有时它就把 `1:` 原样写进正文。
String displayCastNames(String characterName) {
  final names = onStageNames(characterName);
  if (names.isEmpty) return characterName.trim();
  return names.join('、');
}
/// 跨书成员引用格式：`bookId:人物名`，多个以逗号分隔。
///
/// 放在 model 层是因为它同时被 dao（写会话成员）与 service（组 prompt）使用；
/// 留在 service 里会让 dao 反向依赖 service，触发分层门禁 R5。
String encodeMemberRefs(List<({int bookId, String name})> refs) =>
    refs.map((r) => '${r.bookId}:${r.name}').join(',');

/// 解析会话里的成员引用；不是 `bookId:name` 形式时按 [defaultBookId] 兜底。
List<({int bookId, String name})> parseMemberRefs(
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