// lib/service/ai/current_ai_pipeline.dart
//
// 统一解析「当前可用的 AI 会话」。
//
// 背景：项目已迁移到新的 provider 体系（AiPrefs.aiProviders，见
// providers/ai_providers.dart），AI 设置页只写 aiProviders，不再写旧的
// aiConfig_<id> 键。但蒸馏、声明式插件、事件钩子、长任务中心等链路仍直接读
// AiPrefs.getConfig(selectedServiceId)，在新体系下恒为空，于是这些功能全部
// 「点了没反应 / 提示未配置 AI」。
//
// 这里统一成一处：优先新 provider 体系，取不到再回退旧 aiConfig_* 体系，
// 与 service/ai/index.dart 中 aiGenerateStream 的策略保持一致。

import 'package:langchain_core/chat_models.dart';
import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/models/ai_provider.dart';
import 'package:songjiang_reader/service/ai/ai_key_rotator.dart';
import 'package:songjiang_reader/service/ai/langchain_ai_config.dart';
import 'package:songjiang_reader/service/ai/langchain_registry.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 当前选中的、且带可用密钥的 provider（新体系）；取不到返回 null。
///
/// [identifier] 为空时用 AiPrefs.selectedServiceId；该 id 找不到或无可用密钥时，
/// 退而取第一个「已启用且有密钥」的 provider，避免切换/删除 provider 后失效。
AiProvider? findSelectedAiProvider({String? identifier}) {
  try {
    final raw = AiPrefs.getProviders();
    if (raw.isEmpty) return null;

    final providers = raw
        .map((e) => AiProvider.fromJson(e as Map<String, dynamic>))
        .toList();

    final id = identifier ?? AiPrefs.selectedServiceId;
    AiProvider? picked;
    for (final p in providers) {
      if (p.id == id) {
        picked = p;
        break;
      }
    }
    picked ??= providers
        .where((p) => p.enabled && AiKeyRotator.hasValidKey(p))
        .firstOrNull;

    if (picked == null || !picked.enabled) return null;
    if (!AiKeyRotator.hasValidKey(picked)) return null;
    return picked;
  } catch (e) {
    SjLog.warning('AI: 读取 provider 配置失败：$e');
    return null;
  }
}

/// 当前可用的 LangChain 会话；两种体系都不可用时返回 null（调用方应提示用户
/// 先到「设置 → AI」里配置服务）。
LangchainPipeline? resolveCurrentPipeline({
  String? identifier,
  bool useAgent = false,
}) {
  final registry = LangchainAiRegistry(null);

  // 1) 新 provider 体系
  final provider = findSelectedAiProvider(identifier: identifier);
  if (provider != null) {
    final apiKey = AiKeyRotator.getNextKey(provider);
    if (apiKey != null && apiKey.isNotEmpty) {
      final config = LangchainAiConfig.fromProvider(
        providerId: provider.id,
        model: provider.model,
        apiKey: apiKey,
        url: provider.url,
        reasoningEffort: provider.reasoningEffort,
      );
      SjLog.info(
          'AI: 使用 provider ${provider.id} / ${config.model} / ${config.baseUrl}');
      return registry.resolveByProtocol(
        provider.protocol,
        config,
        useAgent: useAgent,
      );
    }
  }

  // 2) 旧 aiConfig_* 体系回退
  final id = identifier ?? AiPrefs.selectedServiceId;
  final raw = AiPrefs.getConfig(id);
  if (raw.isEmpty) {
    SjLog.warning('AI: 未找到可用的 AI 配置（新 provider 与旧 aiConfig 均为空）');
    return null;
  }
  final legacy = LangchainAiConfig.fromPrefs(id, raw);
  SjLog.info('AI: 回退旧配置体系 $id / ${legacy.model}');
  return registry.resolve(legacy, useAgent: useAgent);
}

/// 便捷方法：只要模型实例（蒸馏 / 声明式插件 / 事件钩子用）。
BaseChatModel? resolveCurrentModel({String? identifier}) =>
    resolveCurrentPipeline(identifier: identifier)?.model;

/// 当前是否已经配置了可用的 AI 服务。
bool get hasUsableAiConfig => resolveCurrentPipeline() != null;
