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
    DateTime? updatedAt,
  }) =>
      CharacterChatSession(
        id: id ?? this.id,
        bookId: bookId,
        characterName: characterName,
        title: title ?? this.title,
        mode: mode ?? this.mode,
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
