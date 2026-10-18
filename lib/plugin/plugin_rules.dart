// lib/plugin/plugin_rules.dart
//
// 插件规则引擎（对标造梦的 execution.rules）。
//
// 与「增强器」的区别：
// * 增强器：用户手动打开，长期生效，每轮都注入同一段规则
// * 规则引擎：由**事件 + 条件**触发，可以在第 5 轮、按 30% 概率、
//   或用户说出某个关键词时才生效
//
// 设计上刻意把求值做成**纯函数**：给定规则、状态、回合、输入，
// 算出「这轮要注入什么指令」与「状态怎么变」。这样概率、去重、
// 关键词这些容易出错的逻辑可以脱离 UI 与数据库单独验证。

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/utils/log/common.dart';

/// 规则触发时机。
enum RuleEvent {
  /// 生成之前：可以把指令注入本轮的设定。
  beforeGeneration('before_generation'),

  /// 回合结束之后：可以累计状态。
  afterTurn('after_turn');

  const RuleEvent(this.code);
  final String code;

  static RuleEvent? parse(String? s) {
    if (s == null) return null;
    final n = s.replaceAll('_', '').toLowerCase();
    return RuleEvent.values
        .where((e) => e.name.toLowerCase() == n)
        .firstOrNull;
  }
}

/// 触发条件。多个条件同时存在时取**交集**（都要满足）。
class RuleMatch {
  const RuleMatch({
    this.everyTurns,
    this.chancePercent,
    this.keywords = const [],
  });

  /// 每 N 轮触发一次（N ≤ 0 视为不限制）。
  final int? everyTurns;

  /// 触发概率（0~100）。
  final int? chancePercent;

  /// 用户输入里出现任一关键词即满足。
  final List<String> keywords;

  bool get isEmpty =>
      (everyTurns == null || everyTurns! <= 0) &&
      chancePercent == null &&
      keywords.isEmpty;

  /// 数字字段可能是数字或字符串（清单由第三方维护），统一在这里收口。
  static int? _intOf(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  factory RuleMatch.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const RuleMatch();
    return RuleMatch(
      everyTurns: _intOf(j['everyTurns'] ?? j['every_turns']),
      chancePercent: _intOf(j['chancePercent'] ?? j['chance_percent']),
      keywords: ((j['keywords'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

/// 动作类型。
enum RuleActionType {
  /// 往本轮设定里追加一句指令。
  addInstruction('add_instruction'),

  /// 给会话内的规则状态累计一个数值。
  incrementState('increment_state');

  const RuleActionType(this.code);
  final String code;

  static RuleActionType? parse(String? s) {
    if (s == null) return null;
    final n = s.replaceAll('_', '').toLowerCase();
    return RuleActionType.values
        .where((a) => a.name.toLowerCase() == n)
        .firstOrNull;
  }
}

/// 一个动作。
class RuleAction {
  const RuleAction({
    required this.type,
    this.instruction,
    this.key,
    this.amount = 1,
  });

  final RuleActionType type;
  final String? instruction;
  final String? key;
  final int amount;

  static RuleAction? fromJson(Map<String, dynamic> j) {
    final type = RuleActionType.parse(j['type'] as String?);
    if (type == null) return null;
    switch (type) {
      case RuleActionType.addInstruction:
        final text = (j['instruction'] ?? '').toString().trim();
        if (text.isEmpty) return null;
        return RuleAction(type: type, instruction: text);
      case RuleActionType.incrementState:
        final key = (j['key'] ?? '').toString().trim();
        if (key.isEmpty) return null;
        final amount = (j['amount'] as num?)?.toInt() ?? 1;
        return RuleAction(type: type, key: key, amount: amount);
    }
  }
}

/// 一条规则。
class PluginRule {
  const PluginRule({
    required this.id,
    required this.title,
    required this.event,
    this.match = const RuleMatch(),
    this.actions = const [],
  });

  final String id;
  final String title;
  final RuleEvent event;
  final RuleMatch match;
  final List<RuleAction> actions;

  static PluginRule? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString().trim();
    final event = RuleEvent.parse(j['event'] as String?);
    if (id.isEmpty || event == null) return null;
    final actions = ((j['actions'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => RuleAction.fromJson(e.cast<String, dynamic>()))
        .whereType<RuleAction>()
        .toList();
    if (actions.isEmpty) return null;
    return PluginRule(
      id: id,
      title: (j['title'] ?? id).toString(),
      event: event,
      match: RuleMatch.fromJson((j['match'] as Map?)?.cast<String, dynamic>()),
      actions: actions,
    );
  }
}

/// 求值结果。
class RuleEvaluation {
  const RuleEvaluation({
    this.instructions = const [],
    this.stateDelta = const {},
    this.appliedKeys = const {},
  });

  /// 本轮要追加到设定里的指令。
  final List<String> instructions;

  /// 状态变化量。
  final Map<String, int> stateDelta;

  /// 本次被「消费」的去重键（调用方应并入已应用集合）。
  final Set<String> appliedKeys;

  bool get isEmpty => instructions.isEmpty && stateDelta.isEmpty;
}

/// 去重键：同一条规则在同一个回合只结算一次（重试不重复累计）。
String ruleTurnKey(String pluginId, String ruleId, RuleEvent event, int turn) =>
    '$pluginId#$ruleId#${event.code}#$turn';

/// 纯函数求值。
///
/// 语义细节（都写成测试）：
/// * 多个条件取交集：`everyTurns` + `chancePercent` + `keywords` 都要满足
/// * `everyTurns` 用 `turn % n == 0`，所以第 n、2n… 轮触发
/// * 概率用 `nextInt(100) < chance`，0 表示永不触发，100 表示必触发
/// * **指令总是重新注入**（重试时仍需要它），但**状态只在首次结算**
RuleEvaluation evaluateRules({
  required List<({String pluginId, PluginRule rule})> rules,
  required RuleEvent event,
  required int turn,
  required String userInput,
  Map<String, int> state = const {},
  Set<String> appliedKeys = const {},
  Random? random,
}) {
  final rng = random ?? Random();
  final instructions = <String>[];
  final delta = <String, int>{};
  final applied = <String>{};

  for (final entry in rules) {
    final rule = entry.rule;
    if (rule.event != event) continue;
    if (!_matches(rule.match, turn, userInput, rng)) continue;

    for (final action in rule.actions) {
      switch (action.type) {
        case RuleActionType.addInstruction:
          instructions.add(action.instruction!);
        case RuleActionType.incrementState:
          final key = action.key!;
          final turnKey =
              ruleTurnKey(entry.pluginId, rule.id, event, turn);
          // 同回合重复结算会虚增状态（重试、重新生成都会走到这里）
          if (appliedKeys.contains(turnKey)) continue;
          delta[key] = (delta[key] ?? 0) + action.amount;
          applied.add(turnKey);
      }
    }
  }

  return RuleEvaluation(
    instructions: instructions,
    stateDelta: delta,
    appliedKeys: applied,
  );
}

bool _matches(RuleMatch m, int turn, String input, Random rng) {
  if (m.isEmpty) return true; // 无条件规则：每轮都触发
  if (m.everyTurns != null && m.everyTurns! > 0) {
    if (turn <= 0 || turn % m.everyTurns! != 0) return false;
  }
  if (m.chancePercent != null) {
    final p = m.chancePercent!.clamp(0, 100);
    if (rng.nextInt(100) >= p) return false;
  }
  if (m.keywords.isNotEmpty) {
    if (!m.keywords.any((k) => input.contains(k))) return false;
  }
  return true;
}

/// 规则状态（按插件 × 会话隔离）。
class RuleState {
  const RuleState({this.state = const {}, this.appliedKeys = const {}});
  final Map<String, int> state;
  final Set<String> appliedKeys;
}

/// 规则状态的持久化。
///
/// 键：`plugin.<pluginId>.rules.<sessionId>`；值：`{state:{}, applied:[]}`。
/// `applied` 只保留最近 200 个键，避免长会话把 SharedPreferences 撑大。
class PluginRuleStateStore {
  static const int maxAppliedKeys = 200;

  static String _key(String pluginId, int sessionId) =>
      'plugin.$pluginId.rules.$sessionId';

  static Future<RuleState> load(String pluginId, int sessionId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key(pluginId, sessionId));
      if (raw == null || raw.isEmpty) return const RuleState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const RuleState();
      final state = <String, int>{};
      final s = decoded['state'];
      if (s is Map) {
        s.forEach((k, v) {
          final n = v is num ? v.toInt() : int.tryParse(v.toString());
          if (n != null) state[k.toString()] = n;
        });
      }
      final applied = <String>{
        for (final e in (decoded['applied'] as List? ?? const []))
          e.toString(),
      };
      return RuleState(state: state, appliedKeys: applied);
    } catch (e) {
      SjLog.warning('Plugin: 读取规则状态失败 $pluginId/$sessionId: $e');
      return const RuleState();
    }
  }

  static Future<void> save(
    String pluginId,
    int sessionId, {
    required Map<String, int> state,
    required Set<String> appliedKeys,
  }) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = appliedKeys.toList();
      final trimmed = keys.length <= maxAppliedKeys
          ? keys
          : keys.sublist(keys.length - maxAppliedKeys);
      await sp.setString(
        _key(pluginId, sessionId),
        jsonEncode({'state': state, 'applied': trimmed}),
      );
    } catch (e) {
      SjLog.warning('Plugin: 保存规则状态失败 $pluginId/$sessionId: $e');
    }
  }

  static Future<void> clear(String pluginId, int sessionId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_key(pluginId, sessionId));
    } catch (e) {
      SjLog.warning('Plugin: 清理规则状态失败 $pluginId/$sessionId: $e');
    }
  }
}
/// 把触发条件说成人话（界面上展示用）。
String describeRuleMatch(RuleMatch m) {
  if (m.isEmpty) return '每轮';
  final parts = <String>[];
  if (m.everyTurns != null && m.everyTurns! > 0) parts.add('每 ${m.everyTurns} 轮');
  if (m.chancePercent != null) {
    parts.add('${m.chancePercent!.clamp(0, 100)}% 概率');
  }
  if (m.keywords.isNotEmpty) parts.add('提到「${m.keywords.join('、')}」');
  return parts.join(' + ');
}

/// 把事件说成人话。
String describeRuleEvent(RuleEvent e) =>
    e == RuleEvent.beforeGeneration ? '生成前' : '回合后';