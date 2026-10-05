import 'dart:async';
import 'dart:convert';

import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:langchain_core/tools.dart';

typedef JsonMap = Map<String, dynamic>;

/// Recursively converts a map (which may be a const _ConstMap) into a proper
/// Map so that langchain_google mappers can safely cast nested property values.
Map<String, dynamic> _deepConvertMap(Map<dynamic, dynamic> input) {
  return input.map((key, value) {
    final convertedValue = value is Map ? _deepConvertMap(value) : value;
    return MapEntry(key.toString(), convertedValue);
  });
}

abstract class RepositoryTool<I extends Object, O> {
  RepositoryTool({
    required this.name,
    required this.description,
    required Map<String, dynamic> inputJsonSchema,
    this.timeout,
  }) : inputJsonSchema = _deepConvertMap(inputJsonSchema);

  final String name;
  final String description;
  final Map<String, dynamic> inputJsonSchema;
  final Duration? timeout;

  late final Tool _tool = Tool.fromFunction<I, String>(
    name: name,
    description: description,
    inputJsonSchema: inputJsonSchema,
    func: (input) async => _execute(input),
    getInputFromJson: parseInput,
  );

  Tool get tool => _tool;

  I parseInput(Map<String, dynamic> json);

  FutureOr<O> run(I input);

  Map<String, dynamic> serializeSuccess(O output) {
    return {
      'status': 'ok',
      'name': name,
      'data': output,
    };
  }

  Map<String, dynamic> serializeError(Object error) {
    return {
      'status': 'error',
      'name': name,
      'message': error.toString(),
    };
  }

  bool shouldLogError(Object error) => true;

  Future<String> _execute(I input) async {
    try {
      SjLog.info(
          'AiTool: Executing tool $name with input: ${jsonEncode(input)}');
      final result = await _runWithTimeout(() => run(input));
      final serialized = serializeSuccess(result);
      final resultJson = jsonEncode(serialized);
      SjLog.info('AiTool: Tool $name completed with result: $resultJson');
      return resultJson;
    } catch (error, stack) {
      if (shouldLogError(error)) {
        SjLog.severe('Tool $name failed: $error\n$stack');
      }
      final serialized = serializeError(error);
      return jsonEncode(serialized);
    }
  }

  Future<O> _runWithTimeout(FutureOr<O> Function() action) {
    final future = Future<O>.sync(action);
    if (timeout == null) {
      return future;
    }
    return future.timeout(timeout!);
  }
}

/// 一个 AI 工具的定义。由 AiToolRegistry / PluginRegistry 聚合后交给 agent。
///
/// 注意：`build` 的 context 参数类型为 [Object]（历史签名曾用 AiToolContext），
/// 现有全部内置工具的 build 均以 `(_) => ...` 忽略上下文，故弱化为 Object 不影响功能，
/// 同时让本类型可下沉到叶子层 base_tool，避免与插件体系形成 import 环。
class AiToolDefinition {
  const AiToolDefinition({
    required this.id,
    required this.displayNameBuilder,
    required this.descriptionBuilder,
    required this.build,
  });

  final String id;
  final String Function(L10n l10n) displayNameBuilder;
  final String Function(L10n l10n) descriptionBuilder;
  final Tool Function(Object context) build;

  String displayName(L10n l10n) => displayNameBuilder(l10n);

  String description(L10n l10n) => descriptionBuilder(l10n);

  String displayNameOrDefault([L10n? l10n]) =>
      l10n == null ? id : displayName(l10n);

  String descriptionOrDefault([L10n? l10n]) =>
      l10n == null ? '' : description(l10n);
}
