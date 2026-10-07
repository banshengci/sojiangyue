// lib/models/gameplay_session.dart
//
// 一局玩法的运行时状态。
//
// 与「对话会话」是一对一：每个游戏会话挂在一条角色对话上，
// 记录这局的状态量、推进到第几幕、暗牌是什么、是否已揭晓/结束。

import 'dart:convert';

/// 状态变更记录（用于展示「刚才发生了什么」）。
class GameplayEvent {
  const GameplayEvent({required this.turn, required this.text});

  final int turn;
  final String text;

  Map<String, dynamic> toJson() => {'turn': turn, 'text': text};

  factory GameplayEvent.fromJson(Map<String, dynamic> j) => GameplayEvent(
        turn: (j['turn'] as num?)?.toInt() ?? 0,
        text: j['text'] as String? ?? '',
      );
}

class GameplaySession {
  const GameplaySession({
    this.id,
    required this.chatSessionId,
    required this.modeId,
    this.stats = const {},
    this.turn = 0,
    this.phaseIndex = 0,
    this.secret,
    this.revealed = false,
    this.ended = false,
    this.log = const [],
    this.createdAt,
    this.updatedAt,
  });

  final int? id;

  /// 关联的角色对话会话 id（tb_character_chat_sessions.id）。
  final int chatSessionId;
  final String modeId;

  /// 状态量当前值：key → 数值。
  final Map<String, int> stats;

  /// 已进行的回合数。
  final int turn;

  /// 当前幕下标（0 基）；无分幕时恒为 0。
  final int phaseIndex;

  /// 暗牌：剧本杀的真相 / 海龟汤的汤底。只注入给模型，不展示给用户。
  final String? secret;

  /// 暗牌是否已揭晓。
  final bool revealed;

  /// 本局是否已结束。
  final bool ended;
  final List<GameplayEvent> log;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  GameplaySession copyWith({
    int? id,
    Map<String, int>? stats,
    int? turn,
    int? phaseIndex,
    String? secret,
    bool? revealed,
    bool? ended,
    List<GameplayEvent>? log,
    DateTime? updatedAt,
  }) =>
      GameplaySession(
        id: id ?? this.id,
        chatSessionId: chatSessionId,
        modeId: modeId,
        stats: stats ?? this.stats,
        turn: turn ?? this.turn,
        phaseIndex: phaseIndex ?? this.phaseIndex,
        secret: secret ?? this.secret,
        revealed: revealed ?? this.revealed,
        ended: ended ?? this.ended,
        log: log ?? this.log,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  factory GameplaySession.fromMap(Map<String, dynamic> map) {
    Map<String, int> stats = const {};
    try {
      final raw = jsonDecode(map['stats'] as String? ?? '{}');
      if (raw is Map) {
        stats = raw.map((k, v) =>
            MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
      }
    } catch (_) {}

    List<GameplayEvent> log = const [];
    try {
      final raw = jsonDecode(map['log'] as String? ?? '[]');
      if (raw is List) {
        log = raw
            .map((e) => GameplayEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return GameplaySession(
      id: map['id'] as int?,
      chatSessionId: (map['chat_session_id'] as num?)?.toInt() ?? 0,
      modeId: map['mode_id'] as String? ?? '',
      stats: stats,
      turn: (map['turn'] as num?)?.toInt() ?? 0,
      phaseIndex: (map['phase_index'] as num?)?.toInt() ?? 0,
      secret: map['secret'] as String?,
      revealed: ((map['revealed'] as num?)?.toInt() ?? 0) == 1,
      ended: ((map['ended'] as num?)?.toInt() ?? 0) == 1,
      log: log,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'chat_session_id': chatSessionId,
        'mode_id': modeId,
        'stats': jsonEncode(stats),
        'turn': turn,
        'phase_index': phaseIndex,
        'secret': secret,
        'revealed': revealed ? 1 : 0,
        'ended': ended ? 1 : 0,
        'log': jsonEncode(log.map((e) => e.toJson()).toList()),
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      };
}
