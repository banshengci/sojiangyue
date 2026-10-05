// lib/plugin/songjiang_plugin_contract.dart
//
// 松江阅 · 声明式插件契约（P0 落地版）
//
// 借鉴造梦(Zaomeng)的「声明式配方 + 安全沙箱 + 收敛事件」思想；
// 全部基于松江阅自有 AiToolRegistry 内核全新实现，不复制造梦源码(AGPL-3.0)。
// 完整设计稿见 /workspace/songjiang_plugin_contract.md。

import 'dart:convert';

import 'package:songjiang_reader/service/ai/tools/base_tool.dart';

/// 插件可声明的运行时权限（能力白名单）。未声明即不可用。
enum PluginPermission {
  readBookText('read.book.text'), // 读取当前阅读上下文 / 正文书
  networkHttps('network.https'), // 仅 https 出网（禁私有网段 / localhost）
  aiQuery('ai.query'), // 调用已配置的 AI 模型
  writeNotes('write.notes'); // 写入笔记 / 批注

  const PluginPermission(this.value);
  final String value;

  static PluginPermission? parse(String s) =>
      PluginPermission.values.where((p) => p.value == s).firstOrNull;
}

/// 插件可挂载的触发事件（收敛而明确，对齐造梦的收敛钩子哲学）。
enum PluginEventType {
  onBookOpen,
  onBookImport,
  onChapterEnter,
  onSelectText,
  onPageTurn,
  onAiQuery;

  static PluginEventType? fromJson(String? s) =>
      PluginEventType.values.where((e) => e.name == s).firstOrNull;
}

/// 工具行为三型：声明式插件能做什么。
enum PluginToolBehavior {
  aiPrompt, // 拼 prompt 直接调 LLM
  llmChain, // 多步提示链（steps 顺序执行，后步可引用前步输出）
  builtin, // 引用已注册的原生 AiToolDefinition
}

/// UI / 事件钩子声明（来自 plugin.json 的 hooks[]）。
class PluginHook {
  const PluginHook({required this.event, required this.toolId, this.ui});
  final PluginEventType event;
  final String toolId;
  final Map<String, dynamic>? ui;

  factory PluginHook.fromJson(Map<String, dynamic> j) => PluginHook(
        event:
            PluginEventType.fromJson(j['event']) ?? PluginEventType.onSelectText,
        toolId: j['tool'] as String,
        ui: j['ui'] as Map<String, dynamic>?,
      );
}

/// 多步链的单步定义（仅 llmChain 行为使用）。
///
/// 每步把 [prompt] 模板渲染后调用一次 LLM，输出存入变量 [as]，
/// 供后续步骤以 {{as}} 引用（首步之前可用 {{text}} 等来自工具入参的变量）。
class PluginChainStep {
  const PluginChainStep({required this.prompt, this.as = 'step'});

  final String prompt;
  final String as;

  factory PluginChainStep.fromJson(Map<String, dynamic> j) => PluginChainStep(
        prompt: j['prompt'] as String? ?? '',
        as: j['as'] as String? ?? 'step',
      );
}

/// 工具配方（plugin.json 的 tools[]）。
class PluginToolSpec {
  const PluginToolSpec({
    required this.id,
    required this.displayName,
    required this.description,
    required this.inputSchema,
    required this.behavior,
    this.prompt,
    this.model,
    this.steps = const [],
  });
  final String id;
  final String displayName;
  final String description;
  final Map<String, dynamic> inputSchema;
  final PluginToolBehavior behavior;
  final String? prompt;
  final String? model;

  /// 多步链步骤（仅 [PluginToolBehavior.llmChain] 使用）。
  final List<PluginChainStep> steps;

  static PluginToolBehavior _behaviorOf(String? s) {
    if (s == null) return PluginToolBehavior.aiPrompt;
    // 兼容蛇形写法（ai_prompt / llm_chain）与枚举原名（aiPrompt / llmChain）。
    final normalized = s.replaceAll('_', '').toLowerCase();
    return PluginToolBehavior.values
            .where((b) => b.name.toLowerCase() == normalized)
            .firstOrNull ??
        PluginToolBehavior.aiPrompt;
  }

  factory PluginToolSpec.fromJson(Map<String, dynamic> j) => PluginToolSpec(
        id: j['id'] as String,
        displayName: j['displayName'] as String? ?? (j['id'] as String),
        description: j['description'] as String? ?? '',
        inputSchema: (j['inputSchema'] as Map?)?.cast<String, dynamic>() ??
            const {},
        behavior: _behaviorOf(j['behavior'] as String?),
        prompt: j['prompt'] as String?,
        model: j['model'] as String?,
        steps: (j['steps'] as List? ?? [])
            .map((e) => PluginChainStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 第三方插件清单（plugin.json 解析结果）。
class PluginManifest {
  PluginManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.permissions,
    required this.hooks,
    required this.tools,
    this.minAppVersion,
  });

  final String schemaVersion;
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final List<PluginPermission> permissions;
  final List<PluginHook> hooks;
  final List<PluginToolSpec> tools;
  final String? minAppVersion;

  factory PluginManifest.fromJson(Map<String, dynamic> j) => PluginManifest(
        schemaVersion: j['schemaVersion'] as String? ?? '1.0',
        id: j['id'] as String,
        name: j['name'] as String,
        version: j['version'] as String,
        description: j['description'] as String? ?? '',
        author: j['author'] as String? ?? '',
        permissions: (j['permissions'] as List? ?? [])
            .map((e) => PluginPermission.parse(e as String))
            .whereType<PluginPermission>()
            .toList(),
        hooks: (j['hooks'] as List? ?? [])
            .map((e) => PluginHook.fromJson(e as Map<String, dynamic>))
            .toList(),
        tools: (j['tools'] as List? ?? [])
            .map((e) => PluginToolSpec.fromJson(e as Map<String, dynamic>))
            .toList(),
        minAppVersion: j['minAppVersion'] as String?,
      );

  factory PluginManifest.parse(String jsonText) =>
      PluginManifest.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);
}

/// 插件宿主契约：一个插件 = 一组元数据 + 暴露给 agent 的工具 + 可选事件钩子。
///
/// 内置能力型插件（如人物蒸馏）与第三方声明式插件共用此契约，
/// 从而统一经 [PluginRegistry] 注册，零侵入接入现有 AiToolRegistry。
abstract class SongjiangPlugin {
  String get id;
  String get name;
  String get version;
  String get description;
  String get author;

  /// 该插件实际用到的权限（用于 UI 展示与安全审计）。
  List<PluginPermission> get permissions;

  /// 暴露给 AI agent 的工具定义（builtin 型直接引用原生定义，
  /// ai_prompt 型由 PluginRegistry 编译生成）。
  List<AiToolDefinition> get tools;

  /// 事件钩子（P0c 起用于 on_book_import 触发蒸馏等）。
  List<PluginHook> get hooks => const [];
}
