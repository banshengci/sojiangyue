// lib/models/gameplay_result.dart
//
// 一局玩法结束后的「复盘卡」数据（不落库，由 GameplayResultService 从
// GameplaySession + GameplayMode + CharacterProfile 组装）。
//
// 它是纯展示模型：最终状态量、关键事件回放、羁绊增量与等级、暗牌揭晓入口，
// 以及可分享的纯文本 [toShareText]。

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';

/// 一局玩法的复盘结果。
class GameplayResult {
  const GameplayResult({
    required this.modeId,
    required this.modeName,
    this.bookTitle,
    required this.characterName,
    this.turn = 0,
    this.phaseIndex = 0,
    this.phaseCount = 0,
    this.finalStats = const {},
    this.scoreStats = const [],
    this.events = const [],
    this.secret,
    this.revealed = false,
    this.affectionDelta = 0,
    this.bondLevel = 1,
  });

  final String modeId;
  final String modeName;

  /// 本局所在的书（可空：跨书茶馆 / 未关联书时为空）。
  final String? bookTitle;

  final String characterName;

  /// 本局总回合数（UI 文案「总回合」，禁止写「对话数」）。
  final int turn;

  /// 当前幕下标（0 基）。
  final int phaseIndex;

  /// 总幕数；0 表示不分幕。
  final int phaseCount;

  /// 最终状态量：key → 数值。
  final Map<String, int> finalStats;

  /// 需要作为「胜负分」突出的状态量定义（[GameplayStatDef.isScore] 为 true 的那些）。
  final List<GameplayStatDef> scoreStats;

  /// 关键事件回放（条数 = 对局 log 的条数）。
  final List<GameplayEvent> events;

  /// 暗牌（剧本杀真相 / 海龟汤汤底）；只注入模型、默认不展示给用户。
  final String? secret;

  /// 暗牌是否已揭晓。
  final bool revealed;

  /// 本局贡献的好感增量（≥ 0）。
  final int affectionDelta;

  /// 结算后的羁绊等级。
  final int bondLevel;

  /// 是否持有可揭晓的暗牌。
  bool get hasSecret => secret != null && secret!.trim().isNotEmpty;

  /// 产出可分享的纯文本复盘卡。
  String toShareText() {
    final sb = StringBuffer();
    sb.writeln('【$modeName · $characterName】');
    if (bookTitle != null && bookTitle!.trim().isNotEmpty) {
      sb.writeln('《$bookTitle》');
    }
    sb.writeln('总回合：$turn');
    if (phaseCount > 0) {
      sb.writeln('进度：第 ${phaseIndex + 1} / $phaseCount 幕');
    }
    if (scoreStats.isNotEmpty) {
      sb.writeln('本局结果：');
      for (final stat in scoreStats) {
        final value = finalStats[stat.key] ?? stat.initial;
        sb.writeln('  ${stat.name} $value');
      }
    }
    sb.writeln('羁绊 +$affectionDelta → Lv.$bondLevel');
    if (hasSecret) {
      sb.writeln(revealed ? '暗牌：已揭晓' : '暗牌：未揭晓');
    }
    return sb.toString().trimRight();
  }
}
