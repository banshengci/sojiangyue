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
  String get displayTitle =>
      (title == null || title!.trim().isEmpty)
          ? characterName
          : title!.trim();

  /// 群聊 / 单人：按逗号拆分姓名。
  List<String> get characterNames => characterName
      .split(RegExp(r'[,，]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

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
({String speaker, String text}) splitSpokenLine(
  String reply,
  List<String> onStage,
) {
  final trimmed = reply.trim();
  for (final name in onStage) {
    for (final sep in const [':', '：']) {
      final prefix = '$name$sep';
      if (trimmed.startsWith(prefix)) {
        return (
          speaker: name,
          text: trimmed.substring(prefix.length).trim(),
        );
      }
    }
  }
  return (speaker: '', text: trimmed);
}