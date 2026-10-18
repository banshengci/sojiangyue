// lib/plugin/plugin_npc_runner.dart
//
// 临时角色生成：按当前场景造一个「来客」，由宿主写入会话。
//
// 与增强器/规则的区别：那两个是自动发生的，这个是**用户点一下才发生**，
// 所以不需要开关——点它本身就是同意。

import 'dart:convert';

import 'package:langchain_core/prompts.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 生成结果。
typedef GeneratedNpc = ({String name, String why});

/// 组装提示词（纯函数，便于测试）。
String buildNpcPrompt({
  required PluginNpcGenerator generator,
  required String bookTitle,
  required List<String> members,
  String? scene,
}) {
  final buf = StringBuffer();
  buf.writeln('你要为《$bookTitle》的一个对话场景安排一名临时来客。');
  if (members.isNotEmpty) {
    buf.writeln('当前在场：${members.join('、')}。');
  }
  if (scene != null && scene.trim().isNotEmpty) {
    buf.writeln('当前情境：${scene.trim()}');
  }
  buf.writeln();
  buf.writeln('## 这个来客该是什么样');
  buf.writeln(generator.direction.trim());
  buf.writeln();
  buf.writeln('要求：');
  buf.writeln('- 名字要像这本书里的人，2~4 个字，不要用「神秘人」「来客」这类占位名');
  buf.writeln('- 不能和在场的人重名');
  buf.writeln('- 动机清楚，但不要抢主角的戏');
  buf.writeln();
  buf.writeln('只输出一个 JSON 对象：{"name": "名字", "why": "一句话说明为什么此刻出现"}');
  return buf.toString();
}

/// 解析模型输出。
///
/// 容错：带回代码块围栏、前后加解释、只给了一行名字，都尽量救回来；
/// 救不回来返回 null，由调用方提示用户重试。
GeneratedNpc? parseNpcOutput(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;

  // 去围栏
  text = text
      .replaceAll(RegExp(r'```(?:json)?', multiLine: true), '')
      .replaceAll('```', '')
      .trim();

  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map) {
        final name = (decoded['name'] ?? '').toString().trim();
        if (name.isNotEmpty && name.length <= 12) {
          return (name: name, why: (decoded['why'] ?? '').toString().trim());
        }
      }
    } catch (_) {
      // 落到下面的兜底
    }
  }

  // 兜底：第一行当成名字（模型有时只回一个名字）
  final firstLine = text.split('\n').first.trim();
  if (firstLine.isNotEmpty && firstLine.length <= 12) {
    return (name: firstLine, why: '');
  }
  return null;
}

/// 调模型生成一名临时角色。失败返回 null（调用方提示，不影响会话）。
Future<GeneratedNpc?> generateNpc({
  required PluginNpcGenerator generator,
  required String bookTitle,
  required List<String> members,
  String? scene,
}) async {
  final model = resolveCurrentModel();
  if (model == null) {
    SjLog.warning('PluginNpc: 未配置模型，无法生成临时角色');
    return null;
  }
  try {
    final prompt = buildNpcPrompt(
      generator: generator,
      bookTitle: bookTitle,
      members: members,
      scene: scene,
    );
    final res = await model.invoke(PromptValue.string(prompt));
    final text = _extractText(res);
    return parseNpcOutput(text);
  } catch (e) {
    SjLog.warning('PluginNpc: 生成失败: $e');
    return null;
  }
}

String _extractText(dynamic res) {
  try {
    final out = (res as dynamic).output;
    final c = (out as dynamic).content;
    return c is String ? c : c.toString();
  } catch (_) {
    return res.toString();
  }
}
