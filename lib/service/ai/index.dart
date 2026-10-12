import 'dart:async';
import 'dart:io';

import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/models/ai_provider.dart';
import 'package:songjiang_reader/providers/ai_providers.dart';
import 'package:songjiang_reader/service/ai/ai_cache.dart';
import 'package:songjiang_reader/service/ai/ai_key_rotator.dart';
import 'package:songjiang_reader/service/ai/langchain_ai_config.dart';
import 'package:songjiang_reader/service/ai/langchain_registry.dart';
import 'package:songjiang_reader/service/ai/langchain_runner.dart';
import 'package:songjiang_reader/utils/ai_reasoning_parser.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

final CancelableLangchainRunner _runner = CancelableLangchainRunner();

// Global request timestamps list for RPM throttling
final List<DateTime> _aiRequestTimestamps = [];

/// Throttle AI requests if RPM limit is configured (sliding 1-minute window).
Future<void> _throttleIfNeeded() async {
  final rpm = AiPrefs.rpm;
  if (rpm <= 0) return;
  final now = DateTime.now();
  final windowStart = now.subtract(const Duration(minutes: 1));
  _aiRequestTimestamps.removeWhere((ts) => ts.isBefore(windowStart));
  if (_aiRequestTimestamps.length >= rpm) {
    final oldest = _aiRequestTimestamps.first;
    final waitUntil = oldest.add(const Duration(minutes: 1));
    final waitDuration = waitUntil.difference(DateTime.now());
    if (waitDuration > Duration.zero) {
      await Future.delayed(waitDuration);
    }
    final newNow = DateTime.now();
    _aiRequestTimestamps.removeWhere(
        (ts) => ts.isBefore(newNow.subtract(const Duration(minutes: 1))));
  }
  _aiRequestTimestamps.add(DateTime.now());
}

Stream<String> aiGenerateStream(
  List<ChatMessage> messages, {
  String? identifier,
  Map<String, String>? config,
  bool regenerate = false,
  bool useAgent = false,
  WidgetRef? ref,
}) {
  if (useAgent) {
    assert(ref != null, 'ref must be provided when useAgent is true');
  }
  LangchainAiRegistry registry = LangchainAiRegistry(ref);

  return _generateStream(
      messages: messages,
      identifier: identifier,
      overrideConfig: config,
      regenerate: regenerate,
      useAgent: useAgent,
      registry: registry);
}

void cancelActiveAiRequest() {
  _runner.cancel();
}

Stream<String> _generateStream({
  required List<ChatMessage> messages,
  String? identifier,
  Map<String, String>? overrideConfig,
  required bool regenerate,
  required bool useAgent,
  required LangchainAiRegistry registry,
}) async* {
  SjLog.info('aiGenerateStream called identifier: $identifier');
  final sanitizedMessages = _sanitizeMessagesForPrompt(messages);

  // 缓存只读一次：provider 解析可能失败并落到后面的分支，
  // 若每个分支都尝试读缓存，同一句话会被反复读文件。
  // regenerate=true 表示用户主动要新的（「重新生成」），跳过读缓存但不影响写。
  var cacheReadAttempted = regenerate;

  /// 本轮是否应跳过「读缓存」。调用后即标记为已读，保证每轮只读一次。
  bool takeSkipRead() {
    final skip = cacheReadAttempted;
    cacheReadAttempted = true;
    return skip;
  }

  LangchainAiConfig config;

  // Try to use new provider system first if ref is available
  if (registry.ref != null && overrideConfig == null) {
    try {
      final notifier = registry.ref!.read(aiProvidersProvider.notifier);
      // If a specific provider id was passed, use it; otherwise use the default
      final AiProvider? provider = identifier != null
          ? notifier.getProviderById(identifier)
          : notifier.getSelectedProvider();
      if (provider != null &&
          provider.enabled &&
          AiKeyRotator.hasValidKey(provider)) {
        final apiKey = AiKeyRotator.getNextKey(provider);
        if (apiKey != null) {
          config = LangchainAiConfig.fromProvider(
            providerId: provider.id,
            model: provider.model,
            apiKey: apiKey,
            url: provider.url,
            reasoningEffort: provider.reasoningEffort,
          );

          SjLog.info(
              'aiGenerateStream (new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

          final pipeline = registry.resolveByProtocol(provider.protocol, config,
              useAgent: useAgent);
          final model = pipeline.model;

          await _throttleIfNeeded();
          final cacheIdentity = '${provider.id}|${config.model}';
          yield* _cachedExecuteStream(
            model: model,
            pipeline: pipeline,
            sanitizedMessages: sanitizedMessages,
            useAgent: useAgent,
            cacheIdentity: cacheIdentity,
            cacheIdentifier: provider.id,
            skipRead: takeSkipRead(),
          );

          // Advance key index for round-robin rotation after successful call
          registry.ref!
              .read(aiProvidersProvider.notifier)
              .advanceKeyIndex(provider.id);
          return;
        }
      }
    } catch (e) {
      SjLog.warning(
          'Failed to use new provider system, falling back to legacy: $e');
    }
  }

  // Try new provider system without ref (reads directly from Prefs storage)
  if (overrideConfig == null) {
    try {
      final rawProviders = AiPrefs.getProviders();
      if (rawProviders.isNotEmpty) {
        final providers = rawProviders
            .map((json) => AiProvider.fromJson(json as Map<String, dynamic>))
            .toList();

        AiProvider? provider;
        if (identifier != null) {
          try {
            provider = providers.firstWhere((p) => p.id == identifier);
          } catch (_) {
            provider = null;
          }
        } else {
          final selectedId = AiPrefs.selectedServiceId;
          try {
            provider = providers.firstWhere((p) => p.id == selectedId);
          } catch (_) {}
          provider ??= providers.where((p) => p.enabled).firstOrNull;
        }

        if (provider != null &&
            provider.enabled &&
            AiKeyRotator.hasValidKey(provider)) {
          final apiKey = AiKeyRotator.getNextKey(provider);
          if (apiKey != null) {
            config = LangchainAiConfig.fromProvider(
              providerId: provider.id,
              model: provider.model,
              apiKey: apiKey,
              url: provider.url,
              reasoningEffort: provider.reasoningEffort,
            );

            SjLog.info(
                'aiGenerateStream (no-ref new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

            final pipeline = registry.resolveByProtocol(
                provider.protocol, config,
                useAgent: useAgent);
            final model = pipeline.model;

            await _throttleIfNeeded();
            final cacheIdentity = '${provider.id}|${config.model}';
            yield* _cachedExecuteStream(
              model: model,
              pipeline: pipeline,
              sanitizedMessages: sanitizedMessages,
              useAgent: useAgent,
              cacheIdentity: cacheIdentity,
              cacheIdentifier: provider.id,
              skipRead: takeSkipRead(),
            );

            // Advance key index in persistent storage for round-robin rotation
            final updatedProviders = providers.map((p) {
              if (p.id == provider!.id) {
                return p.copyWith(
                    keyIndex: p.keyIndex + 1, updatedAt: DateTime.now());
              }
              return p;
            }).toList();
            AiPrefs.saveProviders(updatedProviders);
            return;
          }
        }
      }
    } catch (e) {
      SjLog.warning(
          'Failed to use no-ref new provider system, falling back to legacy: $e');
    }
  }

  // Fall back to legacy system
  final selectedIdentifier = identifier ?? AiPrefs.selectedServiceId;
  final savedConfig = AiPrefs.getConfig(selectedIdentifier);
  if (savedConfig.isEmpty &&
      (overrideConfig == null || overrideConfig.isEmpty)) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      yield L10n.of(context).aiServiceNotConfigured;
    } else {
      yield 'AI service not configured';
    }
    return;
  }

  config = LangchainAiConfig.fromPrefs(selectedIdentifier, savedConfig);
  if (overrideConfig != null && overrideConfig.isNotEmpty) {
    final override =
        LangchainAiConfig.fromPrefs(selectedIdentifier, overrideConfig);
    config = mergeConfigs(config, override);
  }

  SjLog.info(
      'aiGenerateStream (legacy): $selectedIdentifier, model: ${config.model}, baseUrl: ${config.baseUrl}');

  final pipeline = registry.resolve(config, useAgent: useAgent);
  final model = pipeline.model;

  await _throttleIfNeeded();
  yield* _cachedExecuteStream(
    model: model,
    pipeline: pipeline,
    sanitizedMessages: sanitizedMessages,
    useAgent: useAgent,
    cacheIdentity: '$selectedIdentifier|${config.model}',
    cacheIdentifier: selectedIdentifier,
    skipRead: takeSkipRead(),
  );
}

/// Execute the AI stream with the given model and pipeline
Stream<String> _executeStream({
  required BaseChatModel model,
  required LangchainPipeline pipeline,
  required List<ChatMessage> sanitizedMessages,
  required bool useAgent,
}) async* {
  Stream<String> stream;
  if (useAgent) {
    final inputMessage = _latestUserMessage(sanitizedMessages);
    if (inputMessage == null) {
      yield 'No user input provided';
      return;
    }

    final tools = pipeline.tools;
    if (tools.isEmpty) {
      yield 'Agent mode not supported for this provider.';
      return;
    }

    final historyMessages = sanitizedMessages
        .sublist(0, sanitizedMessages.length - 1)
        .toList(growable: false);

    stream = _runner.streamAgent(
      model: model,
      tools: tools,
      history: historyMessages,
      input: inputMessage,
      systemMessage: pipeline.systemMessage,
    );
  } else {
    final prompt = PromptValue.chat(sanitizedMessages);
    stream = _runner.stream(model: model, prompt: prompt);
  }

  var buffer = '';

  try {
    await for (final chunk in stream) {
      buffer = chunk;
      yield buffer;
    }
  } catch (error, stack) {
    final mapped = _mapError(error);
    SjLog.severe('AI error: $mapped\n$stack');
    yield mapped;
  } finally {
    try {
      model.close();
    } catch (_) {}
  }
}

/// 在 [_executeStream] 外面套一层缓存。
///
/// 背景：`AiCache.setAiCache/getAiCache` 此前是**死代码**——
/// UI 上「AI 缓存 / 缓存大小 / 清空缓存」都在（`settings_page/ai.dart`），
/// 但没有任何地方调用写入或读取，于是缓存数恒为 0、清空按钮空转，
/// 用户每次都要等完整的生成。这里把读写接回主链路。
///
/// 语义：
/// - 写：仅在流正常走完后落库。`_executeStream` 产出的是一串**累积**文本
///   （每个 chunk 是「到目前为止的全部内容」），所以以最后一个 chunk 为准，
///   天然不会把半截内容写进缓存；被取消的生成因为提前 break 也不会写。
/// - 读：命中则一次性产出缓存内容并**跳过**网络请求，
///   因此不消耗额度、也不受 RPM 限流影响。
/// - `regenerate=true`（用户主动要新答案）时跳过读，避免「重新生成」拿到同一份缓存。
Stream<String> _cachedExecuteStream({
  required BaseChatModel model,
  required LangchainPipeline pipeline,
  required List<ChatMessage> sanitizedMessages,
  required bool useAgent,
  required String cacheIdentity,
  required String cacheIdentifier,
  required bool skipRead,
}) async* {
  if (!skipRead && cacheIdentity.isNotEmpty) {
    final hash = AiCache.cacheHashFor(sanitizedMessages, cacheIdentity);
    final cached = await AiCache.getAiCache(hash, identity: cacheIdentity);
    if (cached != null && cached.data.isNotEmpty) {
      SjLog.info('AiCache hit: $cacheIdentity');
      // 命中缓存就直接返回，不会走到 _executeStream 的 cleanup，
      // 所以必须在这里自己关掉 model。model 是每次请求新建的
      // （见 LangchainRegistry.resolveByProtocol，ChatOpenAI/ChatAnthropic
      // 都持有自己的 dio 客户端），不关就是每次命中泄漏一个。
      try {
        model.close();
      } catch (_) {}
      yield cached.data;
      return;
    }
  }

  var last = '';
  await for (final chunk in _executeStream(
    model: model,
    pipeline: pipeline,
    sanitizedMessages: sanitizedMessages,
    useAgent: useAgent,
  )) {
    last = chunk;
    yield chunk;
  }

  // 只有拿到非空结果才写；错误信息（_mapError 的产物）不写
  if (cacheIdentity.isNotEmpty &&
      last.isNotEmpty &&
      !last.startsWith('Error: ')) {
    final hash = AiCache.cacheHashFor(sanitizedMessages, cacheIdentity);
    await AiCache.setAiCache(
      hash,
      last,
      cacheIdentifier,
      sanitizedMessages,
      identity: cacheIdentity,
    );
    SjLog.info('AiCache stored: $cacheIdentity');
  }
}

String _mapError(Object error) {
  final base = 'Error: ';

  if (error is TimeoutException) {
    return '${base}Request timed out';
  }

  if (error is SocketException) {
    return '${base}Network error: ${error.message}';
  }

  final message = error.toString().toLowerCase();

  if (message.contains('401') ||
      message.contains('unauthorized') ||
      message.contains('invalid api key')) {
    return '${base}Authentication failed. Please verify API key.';
  }

  if (message.contains('429') || message.contains('rate limit')) {
    return '${base}Rate limit reached. Try again later.';
  }

  if (message.contains('timeout')) {
    return '${base}Request timed out';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('failed host lookup')) {
    return '${base}Network error: ${error.toString()}';
  }

  return '$base${error.toString()}';
}

List<ChatMessage> _sanitizeMessagesForPrompt(List<ChatMessage> messages) {
  return messages.map((message) {
    if (message is AIChatMessage) {
      if (message.reasoningContent.isNotEmpty) {
        return AIChatMessage(
          content: message.content,
          toolCalls: message.toolCalls,
        );
      }
      final plainText = reasoningContentToPlainText(message.content);
      if (plainText == message.content) {
        return message;
      }
      return AIChatMessage(
        content: plainText,
        toolCalls: message.toolCalls,
      );
    }
    return message;
  }).toList(growable: false);
}

String? _latestUserMessage(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message is HumanChatMessage) {
      return message.contentAsString;
    }
  }
  return null;
}
