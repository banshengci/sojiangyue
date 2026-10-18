import 'dart:convert';
// lib/plugin/plugin_registry.dart
//
// 插件注册表：聚合「内置能力型插件」与「第三方声明式插件」，
// 统一向 AiToolRegistry 暴露工具定义。零侵入接入现有 AI 内核。
//
// 平台化闭环（本切片补全）：
// - 启用/禁用：第三方插件可在设置页开关（内置插件恒启用、不可卸载）；
//   禁用状态持久化到 SharedPreferences，不依赖 AiPrefs，避免 import 环。
// - 预置插件：随包分发的第三方 plugin.json 在启动时自动加载（assets/plugins/）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/service/ai/tools/base_tool.dart';
import 'package:songjiang_reader/plugin/plugin_rules.dart';
import 'package:songjiang_reader/plugin/plugin_settings.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/utils/log/common.dart';

import 'builtin/character_distill_plugin.dart';
import 'builtin/reading_assistant_plugins.dart';
import 'declarative_plugin_tool.dart';

/// 预置随包分发的第三方插件清单（assets 目录，需在 pubspec 的 flutter.assets 声明）。
/// 注意：Flutter 不支持 assets 目录遍历，必须显式列出已知资源。
const List<String> _bundledPluginAssets = [
  'assets/plugins/translator.plugin.json',
];

const String _disabledPluginsKey = 'plugin.disabledIds';

/// 第三方声明式插件编译后的运行时形态。
class DeclarativePlugin implements SongjiangPlugin {
  const DeclarativePlugin({
    required this.manifest,
    required this.definitions,
  });

  final PluginManifest manifest;
  final List<AiToolDefinition> definitions;

  @override
  String get id => manifest.id;
  @override
  String get name => manifest.name;
  @override
  String get version => manifest.version;
  @override
  String get description => manifest.description;
  @override
  String get author => manifest.author;
  @override
  List<PluginPermission> get permissions => manifest.permissions;
  @override
  List<AiToolDefinition> get tools => definitions;
  @override
  List<PluginHook> get hooks => manifest.hooks;

  @override
  List<PluginEnhancer> get enhancers => manifest.enhancers;

  @override
  List<PluginSettingDef> get settings => manifest.settings;

  @override
  List<PluginRule> get rules => manifest.rules;

  @override
  List<PluginNpcGenerator> get npcGenerators => const [];
}

class PluginRegistry {
  PluginRegistry._() {
    // 注册内置能力型插件（首个：人物蒸馏）。
    _builtin.add(const CharacterDistillPlugin());
    // 读书助手三件套：摘句卡 / 章节回顾 / 共读提问。
    // 它们把配方交给声明式引擎编译，与第三方插件走同一条执行路径。
    _builtin.add(const QuoteCardPlugin());
    _builtin.add(const ChapterRecapPlugin());
    _builtin.add(const DiscussionQuestionsPlugin());
    // 异步加载持久化状态与预置第三方插件（fire-and-forget）。
    // 若 main 中显式 await ensureLoaded()，可确保进入设置页前已就绪。
    unawaited(ensureLoaded());
  }

  static final PluginRegistry instance = PluginRegistry._();

  final List<SongjiangPlugin> _builtin = [];
  final List<SongjiangPlugin> _dynamic = [];
  final Set<String> _disabledPluginIds = {};
  final Set<String> _enabledEnhancerIds = {};
  final Set<String> _enabledRuleIds = {};
  final Map<String, Set<String>> _sessionEnhancers = {};
  bool _initialized = false;

  /// 全部已注册插件（内置 + 动态）。
  List<SongjiangPlugin> get plugins => [..._builtin, ..._dynamic];

  /// 内置插件暴露的工具（供 AiToolRegistry 聚合）。
  List<AiToolDefinition> get builtinToolDefinitions =>
      _builtin.expand((p) => p.tools).toList(growable: false);

  /// 已启用的动态插件暴露的工具（供 AiToolRegistry 聚合，受禁用状态过滤）。
  List<AiToolDefinition> get enabledDynamicToolDefinitions =>
      _dynamic.where((p) => isEnabled(p.id)).expand((p) => p.tools).toList();

  /// 全部插件暴露的工具定义（内置 + 动态，含被禁用的）。
  List<AiToolDefinition> get allToolDefinitions =>
      plugins.expand((p) => p.tools).toList(growable: false);

  AiToolDefinition? byId(String id) {
    for (final p in plugins) {
      for (final t in p.tools) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  /// 插件启用状态：内置插件恒为启用；动态插件受禁用集合控制。
  bool isEnabled(String pluginId) =>
      _builtin.any((p) => p.id == pluginId) ||
      !_disabledPluginIds.contains(pluginId);

  /// 设置插件启用/禁用（内置插件忽略禁用请求，保持系统能力可用）。
  void setEnabled(String pluginId, bool enabled) {
    if (_builtin.any((p) => p.id == pluginId)) return; // 内置不可禁用
    if (enabled) {
      _disabledPluginIds.remove(pluginId);
    } else {
      _disabledPluginIds.add(pluginId);
    }
    _saveDisabled();
  }

  List<String> defaultEnabledIds() =>
      allToolDefinitions.map((t) => t.id).toList(growable: false);

  /// 加载第三方 plugin.json 清单：校验 → 编译工具 → 注册。
  /// 返回新注册的插件（已合并进 allToolDefinitions）。
  /// 全部可用的临时角色生成器（只取已启用插件的）。
  List<({String pluginId, PluginNpcGenerator generator})>
      get availableNpcGenerators {
    final out = <({String pluginId, PluginNpcGenerator generator})>[];
    for (final p in _dynamic) {
      if (!isEnabled(p.id)) continue;
      for (final g in p.npcGenerators) {
        out.add((pluginId: p.id, generator: g));
      }
    }
    return out;
  }

  // ---- 按会话的增强器 ----
  //
  // 全局开关（上面那套）给阅读页 AI 用——它没有会话概念。
  // 角色对话是「一个会话一个世界」，所以每个会话各记一份。

  static const String _sessionEnhancersKey = 'plugin.sessionEnhancers';

  bool isEnhancerEnabledIn(
    int sessionId,
    String pluginId,
    String enhancerId,
  ) =>
      _sessionEnhancers['$sessionId']
          ?.contains(enhancerKey(pluginId, enhancerId)) ??
      false;

  void setEnhancerEnabledIn(
    int sessionId,
    String pluginId,
    String enhancerId,
    bool enabled,
  ) {
    final bucket = _sessionEnhancers.putIfAbsent('$sessionId', () => {});
    final key = enhancerKey(pluginId, enhancerId);
    if (enabled) {
      bucket.add(key);
    } else {
      bucket.remove(key);
    }
    if (bucket.isEmpty) _sessionEnhancers.remove('$sessionId');
    unawaited(_saveSessionEnhancers());
  }

  /// 某个会话当前生效的增强规则。
  List<String> enhancerRulesForSession(int sessionId) {
    final bucket = _sessionEnhancers['$sessionId'] ?? const <String>{};
    if (bucket.isEmpty) return const [];
    final rules = <String>[];
    for (final entry in availableEnhancers) {
      if (!bucket.contains(
        enhancerKey(entry.pluginId, entry.enhancer.id),
      )) {
        continue;
      }
      final rule = entry.enhancer.rule.trim();
      if (rule.isNotEmpty) rules.add(rule);
    }
    return rules;
  }

  /// 清掉某个会话的增强器状态（会话删除时调用）。
  void clearSessionEnhancers(int sessionId) {
    _sessionEnhancers.remove('$sessionId');
    unawaited(_saveSessionEnhancers());
  }

  Future<void> _loadSessionEnhancers() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_sessionEnhancersKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        if (v is List) {
          _sessionEnhancers[k.toString()] = {
            for (final e in v) e.toString(),
          };
        }
      });
    } catch (e) {
      SjLog.warning('Plugin: 读取会话增强器失败: $e');
    }
  }

  Future<void> _saveSessionEnhancers() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _sessionEnhancersKey,
        jsonEncode({
          for (final e in _sessionEnhancers.entries)
            e.key: e.value.toList(),
        }),
      );
    } catch (e) {
      SjLog.warning('Plugin: 保存会话增强器失败: $e');
    }
  }

  // ---- 生成增强器 ----

  /// 全部可用增强器（只取已启用插件的）。
  List<({String pluginId, PluginEnhancer enhancer})> get availableEnhancers {
    final out = <({String pluginId, PluginEnhancer enhancer})>[];
    for (final p in _dynamic) {
      if (!isEnabled(p.id)) continue;
      for (final e in p.enhancers) {
        out.add((pluginId: p.id, enhancer: e));
      }
    }
    return out;
  }

  static String enhancerKey(String pluginId, String enhancerId) =>
      '$pluginId#$enhancerId';

  bool isEnhancerEnabled(String pluginId, String enhancerId) =>
      _enabledEnhancerIds.contains(enhancerKey(pluginId, enhancerId));

  void setEnhancerEnabled(
    String pluginId,
    String enhancerId,
    bool enabled,
  ) {
    final key = enhancerKey(pluginId, enhancerId);
    if (enabled) {
      _enabledEnhancerIds.add(key);
    } else {
      _enabledEnhancerIds.remove(key);
    }
    unawaited(_saveEnhancers());
  }

  /// 当前生效的增强规则文本（供主对话 system prompt 拼接）。
  ///
  /// 只返回**插件已启用 + 增强器已开启**的规则：
  /// 禁用插件时必须立刻失效，不能等重启。
  List<String> get enabledEnhancerRules {
    final rules = <String>[];
    for (final entry in availableEnhancers) {
      if (!isEnhancerEnabled(entry.pluginId, entry.enhancer.id)) continue;
      final rule = entry.enhancer.rule.trim();
      if (rule.isNotEmpty) rules.add(rule);
    }
    return rules;
  }

  static const String _enabledEnhancersKey = 'plugin.enabledEnhancers';

  // ---- 规则引擎 ----

  /// 全部可用规则（只取已启用插件的）。
  List<({String pluginId, PluginRule rule})> get availableRules {
    final out = <({String pluginId, PluginRule rule})>[];
    for (final p in _dynamic) {
      if (!isEnabled(p.id)) continue;
      for (final r in p.rules) {
        out.add((pluginId: p.id, rule: r));
      }
    }
    return out;
  }

  static String ruleKey(String pluginId, String ruleId) => '$pluginId>$ruleId';

  /// 规则默认**关闭**：能凭概率改变对话的规则，必须用户明确开启。
  bool isRuleEnabled(String pluginId, String ruleId) =>
      _enabledRuleIds.contains(ruleKey(pluginId, ruleId));

  void setRuleEnabled(String pluginId, String ruleId, bool enabled) {
    final key = ruleKey(pluginId, ruleId);
    if (enabled) {
      _enabledRuleIds.add(key);
    } else {
      _enabledRuleIds.remove(key);
    }
    unawaited(_saveRules());
  }

  /// 当前真正生效的规则（插件已启用 + 用户已开启）。
  List<({String pluginId, PluginRule rule})> get activeRules => availableRules
      .where((e) => isRuleEnabled(e.pluginId, e.rule.id))
      .toList();

  static const String _enabledRulesKey = 'plugin.enabledRules';

  Future<void> _loadRules() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _enabledRuleIds.addAll(sp.getStringList(_enabledRulesKey) ?? []);
    } catch (e) {
      SjLog.warning('Plugin: 读取规则开关失败: $e');
    }
  }

  Future<void> _saveRules() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_enabledRulesKey, _enabledRuleIds.toList());
    } catch (e) {
      SjLog.warning('Plugin: 保存规则开关失败: $e');
    }
  }

  Future<void> _loadEnhancers() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _enabledEnhancerIds.addAll(sp.getStringList(_enabledEnhancersKey) ?? []);
    } catch (e) {
      SjLog.warning('Plugin: 读取增强器状态失败: $e');
    }
  }

  Future<void> _saveEnhancers() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(
        _enabledEnhancersKey,
        _enabledEnhancerIds.toList(),
      );
    } catch (e) {
      SjLog.warning('Plugin: 保存增强器状态失败: $e');
    }
  }

  SongjiangPlugin loadManifest(PluginManifest manifest) {
    // 同 id 已存在则替换（支持重装 / 升级）。
    _dynamic.removeWhere((p) => p.id == manifest.id);
    final definitions = <AiToolDefinition>[];
    for (final spec in manifest.tools) {
      switch (spec.behavior) {
        case PluginToolBehavior.builtin:
          // 引用已注册的原生工具（qualifiedId 优先）。
          final qid = '${manifest.id}.${spec.id}';
          final existing = byId(qid) ?? byId(spec.id);
          if (existing == null) {
            throw StateError('builtin 工具未找到：${spec.id}');
          }
          definitions.add(existing);
        case PluginToolBehavior.aiPrompt:
          definitions.add(toDefinition(manifest, spec));
        case PluginToolBehavior.llmChain:
          definitions.add(toChainDefinition(manifest, spec));
      }
    }
    final plugin = DeclarativePlugin(manifest: manifest, definitions: definitions);
    _dynamic.add(plugin);
    return plugin;
  }

  /// 卸载动态插件（按 id）。
  void unload(String id) {
    _dynamic.removeWhere((p) => p.id == id);
    _disabledPluginIds.remove(id);
    _saveDisabled();
  }

  /// 按插件 id + 工具本地 id 直接运行声明式工具（供事件钩子触发，
  /// 绕过 langchain Tool.invoke）。仅支持 ai_prompt / llmChain。
  Future<String> runDeclarativeTool(
    String pluginId,
    String toolLocalId,
    Map<String, dynamic> input,
  ) async {
    final plugin = _dynamic
        .whereType<DeclarativePlugin>()
        .where((p) => p.id == pluginId)
        .firstOrNull;
    if (plugin == null) throw StateError('未找到声明式插件：$pluginId');
    final spec = plugin.manifest.tools
        .where((t) => t.id == toolLocalId)
        .firstOrNull;
    if (spec == null) {
      throw StateError('插件 $pluginId 未声明工具：$toolLocalId');
    }
    return runDeclarativeToolBySpec(plugin.manifest, spec, input);
  }

  /// 卸载并删除持久化文件（用户从市场移除插件时调用）。
  Future<void> uninstall(String id) async {
    unload(id);
    try {
      final base = await getApplicationSupportDirectory();
      final file = File('${base.path}/plugins/$id.plugin.json');
      if (await file.exists()) await file.delete();
    } catch (e) {
      SjLog.warning('Plugin: 删除持久化插件文件失败 $id: $e');
    }
  }

  /// 加载持久化的禁用状态 + 预置随包插件 + 已安装插件。幂等，可重复调用。
  Future<void> ensureLoaded() async {
    if (_initialized) return;
    _initialized = true;
    await _loadDisabled();
    await _loadEnhancers();
    await _loadRules();
    await _loadSessionEnhancers();
    await _loadBundled();
    await _loadInstalled();
  }

  Future<void> _loadDisabled() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_disabledPluginsKey) ?? [];
      _disabledPluginIds.addAll(list);
    } catch (e) {
      SjLog.warning('Plugin: 读取禁用插件状态失败: $e');
    }
  }

  Future<void> _saveDisabled() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_disabledPluginsKey, _disabledPluginIds.toList());
    } catch (e) {
      SjLog.warning('Plugin: 保存禁用插件状态失败: $e');
    }
  }

  /// 加载随包预置的第三方插件清单（assets/plugins/*.plugin.json）。
  Future<void> _loadBundled() async {
    for (final asset in _bundledPluginAssets) {
      try {
        final json = await rootBundle.loadString(asset);
        final manifest = PluginManifest.parse(json);
        if (_dynamic.any((p) => p.id == manifest.id)) continue;
        loadManifest(manifest);
        SjLog.info('Plugin: 已加载预置插件 ${manifest.id}');
      } catch (e, st) {
        SjLog.warning('Plugin: 加载预置插件失败 $asset: $e\n$st');
      }
    }
  }

  /// 读回应用支持目录下持久化的插件（经市场安装，重启后仍生效）。
  Future<void> _loadInstalled() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/plugins');
      if (!await dir.exists()) return;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.plugin.json'));
      for (final f in files) {
        try {
          final text = await f.readAsString();
          final manifest = PluginManifest.parse(text);
          if (_dynamic.any((p) => p.id == manifest.id)) continue;
          loadManifest(manifest);
          SjLog.info('Plugin: 已读回持久化插件 ${manifest.id}');
        } catch (e, st) {
          SjLog.warning('Plugin: 读回持久化插件失败 ${f.path}: $e\n$st');
        }
      }
    } catch (e) {
      SjLog.warning('Plugin: 扫描持久化插件目录失败: $e');
    }
  }
}
