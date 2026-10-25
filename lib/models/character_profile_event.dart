// lib/models/character_profile_event.dart
//
// 贡献账本的一行（对应 `tb_character_profile_events`）：每结算一局玩法记一条。
//
// 这是档案值的**真源**。账本刻意不对 `gameplay_session_id` 建外键——删对话会连带
// 删 `tb_gameplay_sessions` 行，若账本跟着被级联删掉，产品裁定「羁绊一经获得即保留」
// 就守不住。账本必须能活得比对局行更久。
//
// 一局一条：`gameplay_session_id` 上有 UNIQUE 索引，重复结算只覆盖不追加，
// 这是整套结算幂等的根基。

class CharacterProfileEvent {
  const CharacterProfileEvent({
    this.id,
    required this.gameplaySessionId,
    required this.characterName,
    this.bookId,
    this.bookTitle,
    this.modeId,
    this.affectionDelta = 0,
    this.turnCount = 0,
    required this.settledAt,
    required this.createdAt,
  });

  final int? id;

  /// 关联的玩法对局 id（`tb_gameplay_sessions.id`）。UNIQUE，但不建外键。
  final int gameplaySessionId;

  final String characterName;

  /// 结算时所在的书（展示用，可空）。
  final int? bookId;
  final String? bookTitle;

  /// 本局玩的玩法 id（留档，便于复盘「这局玩的什么」）。
  final String? modeId;

  /// 本局贡献的好感增量，恒 ≥ 0 → `affection_total` 单调不减（决策 #2）。
  final int affectionDelta;

  /// 本局总回合数。
  final int turnCount;

  /// 结算时间（ISO8601）。
  final DateTime settledAt;

  /// 入库时间（ISO8601）。upsert 冲突时不覆盖，保留首次写入值。
  final DateTime createdAt;

  factory CharacterProfileEvent.fromMap(Map<String, dynamic> map) =>
      CharacterProfileEvent(
        id: map['id'] as int?,
        gameplaySessionId: (map['gameplay_session_id'] as num?)?.toInt() ?? 0,
        characterName: map['character_name'] as String? ?? '',
        bookId: (map['book_id'] as num?)?.toInt(),
        bookTitle: map['book_title'] as String?,
        modeId: map['mode_id'] as String?,
        affectionDelta: (map['affection_delta'] as num?)?.toInt() ?? 0,
        turnCount: (map['turn_count'] as num?)?.toInt() ?? 0,
        settledAt: DateTime.tryParse(map['settled_at'] as String? ?? '') ??
            DateTime.now(),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'gameplay_session_id': gameplaySessionId,
        'character_name': characterName,
        'book_id': bookId,
        'book_title': bookTitle,
        'mode_id': modeId,
        'affection_delta': affectionDelta,
        'turn_count': turnCount,
        'settled_at': settledAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
