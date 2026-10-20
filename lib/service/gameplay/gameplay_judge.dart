// lib/service/gameplay/gameplay_judge.dart
//
// 判官：把「玩家有没有违规」「指认对不对」交给一次独立的小调用，
// 由程序读结论、自己结算。
//
// 为什么必须独立一次调用：规则怪谈的规则、剧本杀的真相都只有模型知道，
// 而正在演戏的那个模型顺便自评，等于让演员自己判犯规——它要么忘了，
// 要么永远说「没违规」，要么顺着玩家的意思说「你猜对了」。
// 判官只做判定、只输出 JSON，不参与表演，也不会被剧情带跑。

import 'dart:convert';

import 'package:langchain/langchain.dart';

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_setup.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 违规判定结论。
class GameplayJudgement {
  const GameplayJudgement({
    this.violatedRule,
    this.fatal = false,
    this.reason = '',
  });

  /// 违反了第几条规则（1 基）；null 表示没违规。
  final int? violatedRule;

  /// 这条是不是致命规则。
  final bool fatal;

  /// 一句话说明（进日志，不直接给玩家看）。
  final String reason;

  bool get violated => violatedRule != null;
}

/// 指认结论。
class GameplayAccusationResult {
  const GameplayAccusationResult({
    required this.correct,
    this.feedback = '',
  });

  final bool correct;

  /// 给玩家的反馈（对错之外不能剧透真相）。
  final String feedback;
}

class GameplayJudge {
  GameplayJudge._();

  /// 判断玩家这句话有没有违反规则。
  ///
  /// 没规则、没输入、没配 AI 时一律返回「没违规」——判官失败不能阻断对话。
  static Future<GameplayJudgement> checkViolation({
    required GameplayMode mode,
    required GameplaySetup setup,
    required String playerAction,
  }) async {
    if (setup.rules.isEmpty || playerAction.trim().isEmpty) {
      return const GameplayJudgement();
    }
    if (resolveCurrentModel() == null) return const GameplayJudgement();

    final raw = await _ask(
      system: '你是规则判定器。只输出 JSON，不要解释，不要写别的字。',
      human: buildViolationPrompt(setup: setup, playerAction: playerAction),
    );
    final json = _jsonOf(raw);
    if (json == null) return const GameplayJudgement();

    final n = (json['violated'] as num?)?.toInt() ?? 0;
    if (n <= 0 || n > setup.rules.length) return const GameplayJudgement();
    return GameplayJudgement(
      violatedRule: n,
      fatal: json['fatal'] == true,
      reason: (json['reason'] ?? '').toString().trim(),
    );
  }

  /// 指认凶手与手法：对/错由暗牌判定。
  static Future<GameplayAccusationResult> accuse({
    required GameplaySetup setup,
    required String suspect,
    required String method,
  }) async {
    if (setup.secret.trim().isEmpty) {
      return const GameplayAccusationResult(
        correct: false,
        feedback: '这一局没有可以对照的真相。',
      );
    }
    if (resolveCurrentModel() == null) {
      return const GameplayAccusationResult(
        correct: false,
        feedback: '还没配置 AI，无法判定。',
      );
    }
    final raw = await _ask(
      system: '你是推理判定器。只输出 JSON，不要解释，不要写别的字。',
      human: buildAccusationPrompt(setup: setup, suspect: suspect, method: method),
    );
    final json = _jsonOf(raw);
    if (json == null) {
      return const GameplayAccusationResult(
        correct: false,
        feedback: '判定没有返回结果，再试一次。',
      );
    }
    return GameplayAccusationResult(
      correct: json['correct'] == true,
      feedback: (json['feedback'] ?? '').toString().trim(),
    );
  }

  /// 违规后该扣哪些状态量。
  ///
  /// 以前这段写死在页面里（`violations +1`、`sanity -25 / -8`），那是「规则怪谈」
  /// 的词表。可剧本杀和海龟汤也开着 `judged`，它们没有这两个键——
  /// 结算结果落进一个不显示的键里，判官判了，玩家一点感觉都没有，
  /// 结局更不会因此触发。
  ///
  /// 现在的规则：有专用词表就按专用词表扣；没有就扣这一档玩法的主计分量。
  ///
  /// 「主计分量」优先取**不按人记**的那一项：按人记的值（好感/信任）存在
  /// `memberStats` 里，往 `stats` 里写一个同名键是看不见的，
  /// 又会掉进同一个坑——扣了，但玩家不知道。
  static Map<String, int> penaltyFor(
    GameplayMode mode, {
    required bool fatal,
  }) {
    final keys = <String>{for (final d in mode.stats) d.key};
    final deltas = <String, int>{};
    if (keys.contains('violations')) deltas['violations'] = 1;
    if (keys.contains('sanity')) deltas['sanity'] = fatal ? -25 : -8;
    if (deltas.isNotEmpty) return deltas;

    GameplayStatDef? target;
    // 先找不按人记的计分项，再退到不按人记的任意项
    for (final d in mode.stats) {
      if (d.isScore && !d.perMember) {
        target = d;
        break;
      }
    }
    if (target == null) {
      for (final d in mode.stats) {
        if (!d.perMember) {
          target = d;
          break;
        }
      }
    }
    if (target == null && mode.stats.isNotEmpty) target = mode.stats.first;
    if (target != null) deltas[target.key] = fatal ? -15 : -5;
    return deltas;
  }

  /// 违规判定的提示词（公开出来便于测试与排查）。
  static String buildViolationPrompt({
    required GameplaySetup setup,
    required String playerAction,
  }) {
    final buf = StringBuffer();
    buf.writeln('本场规则（玩家必须遵守）：');
    for (var i = 0; i < setup.rules.length; i++) {
      buf.writeln('${i + 1}. ${setup.rules[i]}');
    }
    buf.writeln();
    if (setup.secret.trim().isNotEmpty) {
      buf.writeln('真相（判 fatal 用，不要输出它）：');
      buf.writeln(setup.secret.trim());
      buf.writeln();
    }
    buf.writeln('玩家刚才做/说了：');
    buf.writeln('「${playerAction.trim()}」');
    buf.writeln();
    buf.writeln('判断玩家这句话是否**直接违反**了某条规则。');
    buf.writeln('- 从严：只有明确违背规则的行为才算；含糊、试探、回忆、提问都不算');
    buf.writeln('- 指代不明时按没违规处理');
    buf.writeln('- fatal 表示这条规则是不是真相里那条致命的');
    buf.writeln('只输出 JSON，二选一：');
    buf.writeln('{"violated": 0}');
    buf.writeln('{"violated": 2, "fatal": false, "reason": "一句话"}');
    return buf.toString().trim();
  }

  /// 指认的提示词。
  static String buildAccusationPrompt({
    required GameplaySetup setup,
    required String suspect,
    required String method,
  }) {
    final buf = StringBuffer();
    buf.writeln('真相：');
    buf.writeln(setup.secret.trim());
    buf.writeln();
    buf.writeln('玩家的指认：');
    buf.writeln('凶手：${suspect.trim()}');
    buf.writeln('手法：${method.trim().isEmpty ? '（未说明）' : method.trim()}');
    buf.writeln();
    buf.writeln('判定标准：凶手必须说对；手法只要大体说得通就算对，'
        '细节不必完全一致。只说对凶手、手法完全不对，算错。');
    buf.writeln('只输出 JSON：');
    buf.writeln('{"correct": true, "feedback": "对玩家的一句话，不许剧透真相"}');
    return buf.toString().trim();
  }

  static Future<String> _ask({
    required String system,
    required String human,
  }) async {
    final model = resolveCurrentModel();
    if (model == null) return '';
    final buffer = StringBuffer();
    try {
      await for (final event in model.stream(PromptValue.chat([
        ChatMessage.system(system),
        ChatMessage.humanText(human),
      ]))) {
        buffer.write(event.output.content);
      }
    } catch (e) {
      SjLog.warning('GameplayJudge: 判定调用失败: $e');
      return '';
    }
    return buffer.toString();
  }

  /// 从可能带前后缀的回复里抠出 JSON。
  static Map<String, dynamic>? _jsonOf(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
