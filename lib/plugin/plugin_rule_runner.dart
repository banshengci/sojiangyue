// lib/plugin/plugin_rule_runner.dart
//
// 把规则引擎接到实际对话上的那一层：按插件分别载入状态、求值、回写。
//
// 为什么要按插件分组：状态是按 `插件 × 会话` 隔离存储的，
// 混在一起求值会让 A 插件的状态键和 B 插件的撞车。

import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/plugin_rules.dart';
import 'package:songjiang_reader/plugin/plugin_storage.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 规则运行器。
class PluginRuleRunner {
  /// 生成前：算出本轮要注入的指令。
  ///
  /// 失败一律返回空列表——规则是增强，不能因为插件写错就让对话发不出去。
  static Future<List<String>> instructionsFor({
    required int sessionId,
    required int turn,
    required String userInput,
  }) async {
    final rules = PluginRegistry.instance.activeRules;
    if (rules.isEmpty) return const [];

    final out = <String>[];
    for (final group in _byPlugin(rules)) {
      try {
        final state =
            await PluginRuleStateStore.load(group.pluginId, sessionId);
        final eval = evaluateRules(
          rules: group.rules,
          event: RuleEvent.beforeGeneration,
          turn: turn,
          userInput: userInput,
          state: state.state,
          appliedKeys: state.appliedKeys,
        );
        out.addAll(eval.instructions);
        // beforeGeneration 也可能带 increment_state，这里一并落盘
        if (eval.stateDelta.isNotEmpty) {
          await _mergeSave(group.pluginId, sessionId, state, eval);
          await _applyStorageWrites(
            group.pluginId,
            eval,
            turn: turn,
            state: {...state.state, ...eval.stateDelta},
          );
        }
      } catch (e) {
        SjLog.warning('PluginRule: 求值失败 ${group.pluginId}: $e');
      }
    }
    return out;
  }

  /// 回合结束后：结算 afterTurn 规则。
  static Future<void> settleTurn({
    required int sessionId,
    required int turn,
    required String userInput,
  }) async {
    final rules = PluginRegistry.instance.activeRules;
    if (rules.isEmpty) return;

    for (final group in _byPlugin(rules)) {
      try {
        final state =
            await PluginRuleStateStore.load(group.pluginId, sessionId);
        final eval = evaluateRules(
          rules: group.rules,
          event: RuleEvent.afterTurn,
          turn: turn,
          userInput: userInput,
          state: state.state,
          appliedKeys: state.appliedKeys,
        );
        if (eval.isEmpty && eval.appliedKeys.isEmpty) continue;
        await _mergeSave(group.pluginId, sessionId, state, eval);
        await _applyStorageWrites(
          group.pluginId,
          eval,
          turn: turn,
          state: {...state.state, ...eval.stateDelta},
        );
      } catch (e) {
        SjLog.warning('PluginRule: 结算失败 ${group.pluginId}: $e');
      }
    }
  }


  /// 规则要求写入插件存储时，先查权限再写。
  ///
  /// 没有 storage.write 权限就整条丢弃并记一条 warning——
  /// 不静默成功，否则插件作者会以为写进去了。
  static Future<void> _applyStorageWrites(
    String pluginId,
    RuleEvaluation eval, {
    required int turn,
    required Map<String, int> state,
  }) async {
    if (eval.storageWrites.isEmpty) return;
    final plugin = PluginRegistry.instance.plugins
        .where((p) => p.id == pluginId)
        .firstOrNull;
    final allowed = plugin?.permissions.contains(
          PluginPermission.storageWrite,
        ) ??
        false;
    if (!allowed) {
      SjLog.warning('PluginRule: $pluginId 未声明 storage.write，忽略写入');
      return;
    }
    for (final e in eval.storageWrites.entries) {
      try {
        await PluginStorage.write(
          pluginId,
          e.key,
          renderRuleValue(e.value, turn: turn, state: state),
        );
      } catch (err) {
        SjLog.warning('PluginRule: 写入存储失败 ${e.key}: $err');
      }
    }
  }
  static Future<void> _mergeSave(
    String pluginId,
    int sessionId,
    RuleState previous,
    RuleEvaluation eval,
  ) async {
    final mergedState = Map<String, int>.from(previous.state);
    eval.stateDelta.forEach((k, v) => mergedState[k] = (mergedState[k] ?? 0) + v);
    final mergedApplied = {...previous.appliedKeys, ...eval.appliedKeys};
    await PluginRuleStateStore.save(
      pluginId,
      sessionId,
      state: mergedState,
      appliedKeys: mergedApplied,
    );
  }

  static List<({String pluginId, List<({String pluginId, PluginRule rule})> rules})>
      _byPlugin(List<({String pluginId, PluginRule rule})> rules) {
    final map = <String, List<({String pluginId, PluginRule rule})>>{};
    for (final r in rules) {
      map.putIfAbsent(r.pluginId, () => []).add(r);
    }
    return [
      for (final e in map.entries) (pluginId: e.key, rules: e.value),
    ];
  }
}