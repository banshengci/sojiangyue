import 'dart:convert';

import 'package:songjiang_reader/config/runtime_config.dart';
import 'package:songjiang_reader/models/character_card.dart';

/// 蒸馏提示词与输出 JSON 契约 + 鲁棒解析。
///
/// 输出约定（模型按此返回 JSON）：
/// {
///   "characters": [ { "name", "aliases":[], "gender", "role",
///       "importance": 0-100, "personality", "background", "motivation",
///       "appearance", "firstAppearanceChapter", "description" } ],
///   "relations": [ { "source", "target", "relationType",
///       "trust": -100..100, "affection": -100..100, "powerGap": -100..100,
///       "conflictPoint", "hiddenAttitude", "note" } ],
///   "world": [ { "category", "name", "description" } ],
///   "timeline": [ { "chapter", "title", "description", "timeNote" } ]
/// }
/// 也允许直接返回字符数组（无 relations/world/timeline）。

String buildDistillSystemPrompt() {
  // 运行时可热更：远端配置中心下发 distill.systemPrompt 覆盖默认提示词。
  final override = RuntimeConfig.instance.getString('distill.systemPrompt');
  if (override != null && override.trim().isNotEmpty) return override;
  return '''
你是一位严谨的中文小说人物分析师。阅读用户提供的章节文本，抽取其中的人物、关系、世界观与时间线。

# 抽取原则
1. 只依据给定文本，不臆造未出现的信息；信息缺失则省略对应字段。
2. 人物去重：同一人物用统一正名（name），别名放入 aliases。
3. 重要度 importance：核心主角 80-100，主要配角 50-79，次要/龙套 1-49。
4. 关系五元组取值 -100 至 100：
   - trust 信任度（高正=信赖，高负=猜忌）
   - affection 好感度（高正=亲近喜爱，高负=厌恶）
   - powerGap 权力差（正=source 高于 target，负=低于）
   - conflictPoint 表面冲突或矛盾点（一句话）
   - hiddenAttitude 隐藏的真实态度（若文本暗示表里不一）
5. relationType 用简短中文标签：夫妻 / 恋人 / 师徒 / 父子 / 母女 / 兄弟 / 君臣 / 上下级 / 主仆 / 朋友 / 知己 / 敌对 / 盟友 / 同门 / 仇人 等；不确定可省略。
6. world 的 category 用：势力 / 地点 / 组织 / 概念 / 物品 / 功法 等。

# 输出
仅输出一个 JSON 对象（可被 json.loads 解析），不要任何解释或 Markdown 代码围栏。
字段缺失时直接省略该键。若本章没有可抽取内容，返回 {"characters":[]}。
''';
}

String buildDistillUserPrompt(String chapterTitle, String text) => '''
【章节】$chapterTitle

【正文】
$text

请按系统指令输出 JSON。
''';

/// 解析模型原始输出为结构化结果。对 ```json 围栏、前后缀散文、字段类型错位都做容错。
DistillResult parseDistillJson(String raw, {required int bookId}) {
  final jsonText = _extractJson(raw);
  if (jsonText == null) return DistillResult();
  try {
    final decoded = jsonDecode(jsonText);
    final now = DateTime.now();
    if (decoded is List) {
      final characters = decoded
          .whereType<Map>()
          .map((m) => _toCard(m.cast<String, dynamic>(), bookId, now))
          .toList();
      return DistillResult(characters: characters);
    }
    if (decoded is Map) {
      final characters = _asList(decoded['characters'])
          .map((m) => _toCard(m, bookId, now))
          .toList();
      final relations = _asList(decoded['relations'])
          .map((m) => _toRelation(m, bookId, now))
          .toList();
      final world =
          _asList(decoded['world'] ?? decoded['settings'])
              .map((m) => _toWorld(m, bookId, now))
              .toList();
      final timeline =
          _asList(decoded['timeline'] ?? decoded['events'])
              .map((m) => _toTimeline(m, bookId, now))
              .toList();
      return DistillResult(
        characters: characters,
        relations: relations,
        world: world,
        timeline: timeline,
      );
    }
  } catch (e) {
    return DistillResult();
  }
  return DistillResult();
}

class DistillResult {
  const DistillResult({
    this.characters = const [],
    this.relations = const [],
    this.world = const [],
    this.timeline = const [],
  });

  final List<CharacterCard> characters;
  final List<CharacterRelation> relations;
  final List<WorldSetting> world;
  final List<TimelineEvent> timeline;
}

String? _extractJson(String raw) {
  if (raw.trim().isEmpty) return null;
  // 去 ```json ... ``` 围栏
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
  final m = fence.firstMatch(raw);
  final body = m?.group(1) ?? raw;
  // 找第一个 { 或 [
  final start = body.indexOf(RegExp(r'[\{\[]'));
  if (start < 0) return null;
  // 从后往前找匹配的结尾
  for (var end = body.length; end > start; end--) {
    final ch = body[end - 1];
    if (ch == '}' || ch == ']') {
      final candidate = body.substring(start, end);
      try {
        jsonDecode(candidate);
        return candidate;
      } catch (_) {
        // 继续向内缩
      }
    }
  }
  return null;
}

List<Map<String, dynamic>> _asList(Object? raw) {
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const [];
}

int _toInt(Object? v) => switch (v) {
      int i => i,
      double d => d.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

String? _str(Object? v) => switch (v) {
      String s => s.isEmpty ? null : s,
      num n => n.toString(),
      _ => null,
    };

List<String>? _strList(Object? v) {
  if (v is List) {
    final r = v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    return r.isEmpty ? null : r;
  }
  if (v is String && v.isNotEmpty) return [v];
  return null;
}

CharacterCard _toCard(Map<String, dynamic> m, int bookId, DateTime now) {
  final name = _str(m['name']) ?? _str(m['title']) ?? '未知人物';
  return CharacterCard(
    bookId: bookId,
    name: name,
    aliases: _strList(m['aliases'] ?? m['alias']),
    gender: _str(m['gender']),
    role: _str(m['role']),
    importance: _toInt(m['importance']).clamp(0, 100),
    personality: _str(m['personality']),
    background: _str(m['background']),
    motivation: _str(m['motivation']),
    appearance: _str(m['appearance']),
    firstAppearanceChapter: _str(m['firstAppearanceChapter'] ?? m['firstChapter']),
    description: _str(m['description']),
    createdAt: now,
    updatedAt: now,
  );
}

CharacterRelation _toRelation(
    Map<String, dynamic> m, int bookId, DateTime now) {
  return CharacterRelation(
    bookId: bookId,
    sourceName: _str(m['source'] ?? m['sourceName'] ?? m['from']) ?? '',
    targetName: _str(m['target'] ?? m['targetName'] ?? m['to']) ?? '',
    relationType: _str(m['relationType'] ?? m['type']),
    trust: _toInt(m['trust']).clamp(-100, 100),
    affection: _toInt(m['affection']).clamp(-100, 100),
    powerGap: _toInt(m['powerGap'] ?? m['power']).clamp(-100, 100),
    conflictPoint: _str(m['conflictPoint'] ?? m['conflict']),
    hiddenAttitude: _str(m['hiddenAttitude'] ?? m['hidden']),
    note: _str(m['note']),
    createdAt: now,
    updatedAt: now,
  );
}

WorldSetting _toWorld(Map<String, dynamic> m, int bookId, DateTime now) {
  return WorldSetting(
    bookId: bookId,
    category: _str(m['category']) ?? '其他',
    name: _str(m['name'] ?? m['title']) ?? '未知设定',
    description: _str(m['description']),
    createdAt: now,
    updatedAt: now,
  );
}

TimelineEvent _toTimeline(Map<String, dynamic> m, int bookId, DateTime now) {
  return TimelineEvent(
    bookId: bookId,
    chapter: _str(m['chapter']),
    title: _str(m['title'] ?? m['name']) ?? '事件',
    description: _str(m['description']),
    timeNote: _str(m['timeNote'] ?? m['time']),
    createdAt: now,
    updatedAt: now,
  );
}
