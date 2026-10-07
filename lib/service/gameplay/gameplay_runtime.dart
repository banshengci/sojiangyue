// lib/service/gameplay/gameplay_runtime.dart
//
// 玩法运行时：让玩法真的有「状态」和「推进」。
//
// 工作方式：
//   1. 每轮对话前，把玩法规则 + 当前状态 + 暗牌 + 分幕进度拼进角色的 system 侧设定；
//   2. 要求模型在回复末尾附一个状态块 `<sj-state>{...}</sj-state>`，声明本回合
//      哪些状态量变了、变了多少；
//   3. 运行时把状态块**从正文里剥掉**（读者看不到），把数值结算进状态，
//      并推进回合/分幕、记录事件。
//
// 这样「好感 +8」「线索 +1」是真实累计的，而不是嘴上说说。

import 'dart:convert';
import 'dart:math';

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/utils/log/common.dart';

const String kStateOpen = '<sj-state>';
const String kStateClose = '</sj-state>';

/// 每一幕大致占几个回合。
const int kTurnsPerPhase = 3;

/// 一轮的解析结果。
class GameplayTurn {
  const GameplayTurn({
    required this.displayText,
    this.deltas = const {},
    this.note,
    this.ended = false,
  });

  /// 剥掉状态块之后的正文（用于展示与落库）。
  final String displayText;

  /// 本回合的状态变化量。
  final Map<String, int> deltas;

  /// 本回合做了什么（一句话）。
  final String? note;

  /// 模型是否声明本局结束。
  final bool ended;

  bool get hasChanges => deltas.isNotEmpty;
}

class GameplayRuntime {
  GameplayRuntime._();

  /// 组装注入给模型的玩法设定。
  static String buildDirective({
    required GameplayMode mode,
    required GameplaySession session,
  }) {
    final buf = StringBuffer();

    buf.writeln('## 本场玩法：${mode.name}');
    buf.writeln(mode.directive.trim());
    buf.writeln();

    if (mode.stats.isNotEmpty) {
      buf.writeln('## 可追踪状态（会随剧情变化）');
      for (final def in mode.stats) {
        final cur = session.stats[def.key] ?? def.initial;
        buf.writeln(
            '- ${def.name}（${def.key}）：当前 $cur，范围 ${def.min}~${def.max}。${def.hint}');
      }
      buf.writeln();
    }

    if (mode.phases.isNotEmpty) {
      final idx = session.phaseIndex.clamp(0, mode.phases.length - 1);
      buf.writeln('## 当前进度');
      buf.writeln(
          '第 ${idx + 1} 幕 / 共 ${mode.phases.length} 幕：${mode.phases[idx]}'
          '（已进行 ${session.turn} 轮）');
      if (idx + 1 < mode.phases.length) {
        buf.writeln('剧情推进到合适的时候，可以自然过渡到下一幕：${mode.phases[idx + 1]}');
      }
      buf.writeln();
    }

    final secret = session.secret;
    if (secret != null && secret.trim().isNotEmpty) {
      buf.writeln('## 暗牌（只有你知道，绝对不能直接说出来）');
      buf.writeln(secret.trim());
      buf.writeln('对方必须靠提问与推理把它问出来。你只能在对话中给线索，'
          '不能主动交底，也不能因为对方反复追问就提前说出来。');
      buf.writeln();
    }

    if (session.log.isNotEmpty) {
      buf.writeln('## 前情（最近的推进）');
      for (final e in session.log.reversed.take(5).toList().reversed) {
        buf.writeln('- 第 ${e.turn} 轮：${e.text}');
      }
      buf.writeln();
    }

    buf.writeln('## 输出要求（必须遵守）');
    if (mode.stats.isNotEmpty) {
      buf.writeln('每次回复的**最后另起一行**输出本回合的状态变化，格式：');
      buf.writeln(
          '$kStateOpen{"好感": 5, "note": "一句话说明这轮为什么变"}$kStateClose');
      buf.writeln('规则：');
      buf.writeln('- 键用上面列出的状态名，只写发生变化的那几项；全都变就都写，没变就写 `$kStateOpen{}$kStateClose`');
      buf.writeln('- 变化幅度：普通互动 ±3~8，重要转折 ±10~25');
      buf.writeln('- 这个块会被程序读取并从正文中删掉，读者看不到，所以不要解释它、不要把它写进剧情');
      buf.writeln('- 除最后这一行外，正文里不要再出现任何 `$kStateOpen` 字样');
    }
    if (mode.endingHint != null && mode.endingHint!.trim().isNotEmpty) {
      buf.writeln(mode.endingHint!.trim());
      buf.writeln(
          '当结局条件达成时，在本回合状态块里加上 `"ended": true`，并在正文里把这局收尾。');
    }

    return buf.toString().trim();
  }

  /// 从模型回复中剥离状态块并解析。
  ///
  /// [streaming] 为真表示这是流式过程中的中间文本：状态块往往只写了一半
  /// （只有 `<sj-state>` 没有闭合标签），此时**不解析、也不记日志**，
  /// 只把状态块之前的部分作为正文展示，避免每帧刷一条解析失败日志。
  static GameplayTurn parse(String raw, {bool streaming = false}) {
    final start = raw.indexOf(kStateOpen);
    if (start < 0) {
      return GameplayTurn(displayText: raw.trim());
    }
    final end = raw.indexOf(kStateClose, start);
    if (end < 0) {
      // 状态块还没写完（或模型格式不完整）：截掉它，正文照常显示
      if (!streaming) {
        SjLog.warning('GameplayRuntime: 状态块未闭合，本回合按无变化处理');
      }
      return GameplayTurn(displayText: raw.substring(0, start).trim());
    }

    final jsonText = raw.substring(start + kStateOpen.length, end);
    // 正文 = 状态块之前 + 状态块之后
    final before = raw.substring(0, start);
    final after = raw.substring(end + kStateClose.length);
    final display = (before + after).trim();

    final deltas = <String, int>{};
    String? note;
    var ended = false;
    try {
      final decoded = jsonDecode(jsonText.trim());
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final key = k.toString();
          if (key == 'note') {
            final t = v?.toString().trim() ?? '';
            if (t.isNotEmpty) note = t;
            return;
          }
          if (key == 'ended') {
            ended = v == true || v?.toString() == 'true';
            return;
          }
          final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
          if (n != null && n != 0) deltas[key] = n;
        });
      }
    } catch (e) {
      SjLog.warning('GameplayRuntime: 状态块解析失败: $jsonText ($e)');
    }

    return GameplayTurn(
      displayText: display,
      deltas: deltas,
      note: note,
      ended: ended,
    );
  }

  /// 把本回合的变化结算进会话状态并推进。
  static GameplaySession apply({
    required GameplayMode mode,
    required GameplaySession session,
    required GameplayTurn turn,
  }) {
    final stats = Map<String, int>.from(session.stats);
    for (final def in mode.stats) {
      stats.putIfAbsent(def.key, () => def.initial);
    }

    // 状态名 → key（模型可能用中文名）
    final nameToKey = {
      for (final d in mode.stats) d.name: d.key,
      for (final d in mode.stats) d.key: d.key,
    };

    turn.deltas.forEach((rawKey, delta) {
      final key = nameToKey[rawKey] ?? rawKey;
      final def = mode.stats.where((d) => d.key == key).firstOrNull;
      final current = stats[key] ?? def?.initial ?? 0;
      final next = current + delta;
      stats[key] = def == null ? next : next.clamp(def.min, def.max);
    });

    final newTurn = session.turn + 1;
    // 分幕按回合推进（有分幕时才动）
    var phase = session.phaseIndex;
    if (mode.phases.isNotEmpty) {
      phase = (newTurn ~/ kTurnsPerPhase).clamp(0, mode.phases.length - 1);
    }

    final log = List<GameplayEvent>.from(session.log);
    if (turn.note != null && turn.note!.isNotEmpty) {
      log.add(GameplayEvent(turn: newTurn, text: turn.note!));
      // 只留最近 20 条，避免无限膨胀
      while (log.length > 20) {
        log.removeAt(0);
      }
    }

    return session.copyWith(
      stats: stats,
      turn: newTurn,
      phaseIndex: phase,
      log: log,
      ended: session.ended || turn.ended,
      updatedAt: DateTime.now(),
    );
  }

  /// 生成开局用的暗牌（剧本杀的真相 / 海龟汤的汤底）。
  ///
  /// 返回给模型的提示词；调用方拿到文本后请求模型补全。
  static String buildSetupPrompt({
    required GameplayMode mode,
    required String characterName,
    String? bookTitle,
    String? scene,
  }) {
    final buf = StringBuffer();
    buf.writeln(mode.setupPrompt!.trim());
    buf.writeln();
    buf.writeln('出场人物：$characterName'
        '${bookTitle == null || bookTitle.isEmpty ? '' : '（出自《$bookTitle》）'}');
    if (scene != null && scene.isNotEmpty) {
      buf.writeln('场景：$scene');
    }
    buf.writeln();
    buf.writeln('要求：');
    buf.writeln('- 只输出这份设定本身，不要解释、不要写对话、不要加标题以外的多余内容');
    buf.writeln('- 内容要具体到可以支撑一场追问（有人名、有细节、有可被追问的破绽）');
    buf.writeln('- 控制在 200 字以内');
    return buf.toString().trim();
  }
}
