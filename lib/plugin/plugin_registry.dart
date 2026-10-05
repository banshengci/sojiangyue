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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/service/ai/tools/base_tool.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/utils/log/common.dart';

import 'builtin/character_distill_plugin.dart';
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
}

class PluginRegistry {
  PluginRegistry._() {
    // 注册内置能力型插件（首个：人物蒸馏）。
    _builtin.add(const CharacterDistillPlugin());
    // 异步加载持久化状态与预置第三方插件（fire-and-forget）。
    // 若 main 中显式 await ensureLoaded()，可确保进入设置页前已就绪。
    unawaited(ensureLoaded());
  }

  static final PluginRegistry instance = PluginRegistry._();

  final List<SongjiangPlugin> _builtin = [];
  final List<SongjiangPlugin> _dynamic = [];
  final Set<String> _disabledPluginIds = {};
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
