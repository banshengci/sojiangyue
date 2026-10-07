// lib/service/character/character_enrich_service.dart
//
// 人物资料「AI 补全」：把蒸馏时漏掉或写得潦草的字段补齐。
//
// 造梦 persona 的「资料校对 / AI 补全」对应能力。这里刻意收窄了模型的自由度：
// 只允许依据**已给出的信息**（人物卡已有字段 + 关系 + 世界观）做归纳与改写，
// 不允许新增书里没有的情节——否则补全出来的"背景"全是编的，反而污染资料。
// 结果由用户确认后才写库。

import 'dart:convert';

import 'package:langchain/langchain.dart';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 可补全的字段。
enum EnrichField {
  personality('personality', '性格'),
  background('background', '背景'),
  motivation('motivation', '动机'),
  appearance('appearance', '外貌'),
  description('description', '简介'),
  role('role', '身份');

  const EnrichField(this.key, this.label);

  final String key;
  final String label;
}

class CharacterEnrichService {
  /// 对指定字段做补全，返回 {字段key: 内容}。缺失/无法判断的字段不会出现在结果里。
  Future<Map<String, String>> complete({
    required CharacterCard card,
    required BaseChatModel model,
    List<CharacterRelation> relations = const [],
    List<WorldSetting> world = const [],
    List<EnrichField> fields = EnrichField.values,
  }) async {
    if (fields.isEmpty) return const {};

    final prompt = PromptValue.chat([
      ChatMessage.system(_systemPrompt),
      ChatMessage.humanText(
        _buildMaterial(card, relations, world, fields),
      ),
    ]);

    final buffer = StringBuffer();
    await for (final event in model.stream(prompt)) {
      buffer.write(event.output.content);
    }
    return _parse(buffer.toString(), fields);
  }

  static final String _systemPrompt = '''
你在帮读者校订一份小说人物的资料卡。读者会给你这个人已有的全部已知信息，
以及需要补齐的字段清单。

# 铁律
1. **只依据给到的信息**做归纳、提炼、改写。不要新增任何书里没有的情节、
   身世、对话或关系。
2. 如果某个字段靠现有信息根本推不出来，**不要猜**——直接省略这个字段，
   不要写"未知""不详""暂无信息"这类占位话。
3. 信息足够时，把零散线索写成通顺的一两句话，不要罗列。
4. 外貌字段若原文没描写，省略；不要凭空写"眉目清秀"这类套话。
5. 用简体中文，语气平实，不要 Markdown 标题。

# 输出
仅输出一个 JSON 对象，键为字段名，值为内容字符串。不要代码围栏，不要解释：
{"personality": "...", "background": "..."}
'''.trim();

  String _buildMaterial(
    CharacterCard card,
    List<CharacterRelation> relations,
    List<WorldSetting> world,
    List<EnrichField> fields,
  ) {
    final buf = StringBuffer();
    buf.writeln('人物：${card.name}');
    void add(String label, String? v) {
      if (v != null && v.trim().isNotEmpty) buf.writeln('- $label：${v.trim()}');
    }

    add('别名', card.aliases?.join('、'));
    add('性别', card.gender);
    add('身份', card.role);
    add('性格', card.personality);
    add('所求', card.motivation);
    add('过往', card.background);
    add('形貌', card.appearance);
    add('首次出场', card.firstAppearanceChapter);
    add('简介', card.description);
    buf.writeln();

    if (relations.isNotEmpty) {
      buf.writeln('他/她与他人的关系：');
      for (final r in relations.take(10)) {
        final other =
            r.sourceName == card.name ? r.targetName : r.sourceName;
        final bits = <String>[
          if (r.relationType != null && r.relationType!.isNotEmpty)
            r.relationType!,
          if (r.trust != 0) '信任 ${r.trust}',
          if (r.affection != 0) '亲近 ${r.affection}',
          if (r.conflictPoint != null && r.conflictPoint!.isNotEmpty)
            '矛盾：${r.conflictPoint}',
        ];
        buf.writeln('- $other（${bits.isEmpty ? '相识' : bits.join('，')}）');
      }
      buf.writeln();
    }

    if (world.isNotEmpty) {
      buf.writeln('所处世界的设定（供参考，不要照搬到人物身上）：');
      for (final w in world.take(8)) {
        buf.writeln('- ${w.category}·${w.name}');
      }
      buf.writeln();
    }

    buf.writeln('需要补齐的字段：${fields.map((f) => '${f.label}(${f.key})').join('、')}');
    return buf.toString().trim();
  }

  /// 解析并只保留本次请求的字段。
  Map<String, String> _parse(String raw, List<EnrichField> fields) {
    final jsonText = _extractJson(raw);
    if (jsonText == null) {
      SjLog.warning('Enrich: 模型未返回可解析的 JSON');
      return const {};
    }
    Map<String, dynamic> map;
    try {
      map = jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (e) {
      SjLog.warning('Enrich: JSON 解析失败: $e');
      return const {};
    }

    final allowed = fields.map((f) => f.key).toSet();
    final out = <String, String>{};
    map.forEach((k, v) {
      if (!allowed.contains(k)) return;
      final text = v?.toString().trim() ?? '';
      // 过滤模型没忍住写的占位话
      if (text.isEmpty) return;
      if (text == '未知' || text == '不详' || text == '暂无' || text == '暂无信息') {
        return;
      }
      out[k] = text;
    });
    return out;
  }

  String? _extractJson(String raw) {
    var s = raw.trim();
    if (s.contains('```')) {
      final m = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
      if (m != null) s = m.group(1)!.trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return s.substring(start, end + 1);
  }
}
