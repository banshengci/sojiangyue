// lib/plugin/declarative_plugin_tool.dart
//
// 把声明式 ai_prompt 配方编译为真实可执行的 AiToolDefinition。
// 安全边界：插件永不引入新 Dart 代码，只能拼 prompt 调 LLM。

import 'dart:convert';

import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/service/ai/langchain_ai_config.dart';
import 'package:songjiang_reader/service/ai/langchain_registry.dart';
import 'package:songjiang_reader/service/ai/tools/base_tool.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

/// 把 {{input}}（整体 JSON）与 {{key}}（逐字段）替换为变量内容。
/// 声明式工具与多步链共用同一套模板渲染规则。
String _renderTemplate(String template, Map<String, dynamic> vars) {
  var out = template.replaceAll('{{input}}', jsonEncode(vars));
  for (final entry in vars.entries) {
    out = out.replaceAll('{{${entry.key}}}', entry.value?.toString() ?? '');
  }
  return out;
}

/// 把 ai_prompt 型配方编译成一个 RepositoryTool。
class DeclarativePluginTool
    extends RepositoryTool<Map<String, dynamic>, String> {
  DeclarativePluginTool({
    required this.qualifiedId,
    required this.spec,
    required this.manifest,
  }) : super(
          name: qualifiedId,
          description: spec.description,
          inputJsonSchema: spec.inputSchema,
          timeout: const Duration(seconds: 60),
        );

  final String qualifiedId;
  final PluginToolSpec spec;
  final PluginManifest manifest;

  @override
  Map<String, dynamic> parseInput(Map<String, dynamic> json) => json;

  @override
  Future<String> run(Map<String, dynamic> input) async {
    final id = AiPrefs.selectedServiceId;
    final raw = AiPrefs.getConfig(id);
    if (raw.isEmpty) {
      return jsonEncode({'status': 'error', 'message': '尚未配置 AI 服务，无法运行插件。'});
    }
    final config = LangchainAiConfig.fromPrefs(id, raw);
    final model = LangchainAiRegistry(null).resolve(config).model;
    final prompt = _renderTemplate(spec.prompt ?? '', input);
    final res = await model.invoke(prompt);
    final text = _extractText(res);
    return jsonEncode({
      'status': 'ok',
      'plugin': manifest.id,
      'tool': spec.id,
      'result': text,
    });
  }
}

/// 多步提示链工具（PluginToolBehavior.llmChain）。
///
/// 按 spec.steps 顺序逐步渲染→调 LLM→把输出存入步骤变量（step.as），
/// 后续步骤通过 {{as}} 引用前序结果；最终步输出作为工具结果返回。
/// 与 ai_prompt 同样完全零代码：插件只能拼模板调 LLM，无法引入 Dart。
class DeclarativeChainTool
    extends RepositoryTool<Map<String, dynamic>, String> {
  DeclarativeChainTool({
    required this.qualifiedId,
    required this.spec,
    required this.manifest,
  }) : super(
          name: qualifiedId,
          description: spec.description,
          inputJsonSchema: spec.inputSchema,
          timeout: const Duration(seconds: 120),
        );

  final String qualifiedId;
  final PluginToolSpec spec;
  final PluginManifest manifest;

  @override
  Map<String, dynamic> parseInput(Map<String, dynamic> json) => json;

  @override
  Future<String> run(Map<String, dynamic> input) async {
    final id = AiPrefs.selectedServiceId;
    final raw = AiPrefs.getConfig(id);
    if (raw.isEmpty) {
      return jsonEncode({'status': 'error', 'message': '尚未配置 AI 服务，无法运行插件。'});
    }
    final config = LangchainAiConfig.fromPrefs(id, raw);
    final model = LangchainAiRegistry(null).resolve(config).model;
    final vars = <String, dynamic>{...input};
    final stepsOut = <String, String>{};
    var last = '';
    for (final step in spec.steps) {
      final rendered = _renderTemplate(step.prompt, vars);
      final res = await model.invoke(rendered);
      final text = _extractText(res);
      vars[step.as] = text;
      stepsOut[step.as] = text;
      last = text;
    }
    return jsonEncode({
      'status': 'ok',
      'plugin': manifest.id,
      'tool': spec.id,
      'result': last,
      'steps': stepsOut,
    });
  }
}

/// 防御性提取 LLM 返回文本（不同 langchain 版本字段名略有差异）。
String _extractText(dynamic res) {
  // langchain ChatResult: res.output 为 ChatMessage，content 为内容。
  try {
    final out = (res as dynamic).output;
    final c = (out as dynamic).content;
    return c is String ? c : c.toString();
  } catch (_) {
    return res.toString();
  }
}

/// 由 PluginManifest 的一个 ai_prompt 工具规格编译为 AiToolDefinition。
AiToolDefinition toDefinition(PluginManifest m, PluginToolSpec spec) {
  final qid = '${m.id}.${spec.id}';
  return AiToolDefinition(
    id: qid,
    displayNameBuilder: (_) => '${m.name}·${spec.displayName}',
    descriptionBuilder: (_) => spec.description,
    build: (_) =>
        DeclarativePluginTool(qualifiedId: qid, spec: spec, manifest: m).tool,
  );
}

/// 由 PluginManifest 的一个 llmChain 工具规格编译为 AiToolDefinition。
AiToolDefinition toChainDefinition(PluginManifest m, PluginToolSpec spec) {
  final qid = '${m.id}.${spec.id}';
  return AiToolDefinition(
    id: qid,
    displayNameBuilder: (_) => '${m.name}·${spec.displayName}',
    descriptionBuilder: (_) => spec.description,
    build: (_) =>
        DeclarativeChainTool(qualifiedId: qid, spec: spec, manifest: m).tool,
  );
}

/// 按配方直接运行声明式工具（供事件钩子触发，绕过 langchain Tool.invoke）。
///
/// 返回值为工具内部序列化后的 JSON 字符串（含 status/result 等）。
/// builtin 引用型不支持钩子触发，会抛出 StateError。
Future<String> runDeclarativeToolBySpec(
  PluginManifest m,
  PluginToolSpec spec,
  Map<String, dynamic> input,
) async {
  final qid = '${m.id}.${spec.id}';
  switch (spec.behavior) {
    case PluginToolBehavior.aiPrompt:
      return DeclarativePluginTool(qualifiedId: qid, spec: spec, manifest: m)
          .run(input);
    case PluginToolBehavior.llmChain:
      return DeclarativeChainTool(qualifiedId: qid, spec: spec, manifest: m)
          .run(input);
    case PluginToolBehavior.builtin:
      throw StateError('builtin 工具不支持钩子触发：${spec.id}');
  }
}
