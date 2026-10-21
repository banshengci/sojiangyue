import 'dart:convert';

import 'package:songjiang_reader/config/runtime_config.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/distill_persist.dart';

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
2. **人物去重**（最容易出错，务必照做）：同一个人只出一张卡。
   动笔前先在心里列一张别名表，把同一人物的所有叫法归到一个正名下：
   - 「我 / 主角 / 男主 / 女主 / 主人公」这类叙述代词，能确定指谁就归到那个人；
     确定不了就整张丢掉，不要单出一张叫「我」的卡。
   - 亲称不是名字：「妈妈 / 老妈 / 母上大人 / 凌母 / 小云」说的是同一个人，
     不要各出一张。正名优先用文本里出现过的**真名**（如「郑怡云」），
     全书都没有真名才用亲称。
   - 姓氏代称（「凌母」「凌父」「沈母」）与真名指向同一人时合并。
   - 一张卡的 aliases 里**只能放自己的别称**，绝不能放另一个人的正名。
     反过来说：如果你发现 A 的正名出现在 B 的 aliases 里，A 和 B 就是同一个人。
   - 宁可少出一张卡，也不要同一个人出两张。
3. 重要度 importance：核心主角 80-100，主要配角 50-79，次要/龙套 1-49。
4. 关系五元组取值 -100 至 100：
   - trust 信任度（高正=信赖，高负=猜忌）
   - affection 好感度（高正=亲近喜爱，高负=厌恶）
   - powerGap 权力差（正=source 高于 target，负=低于）
   - conflictPoint 表面冲突或矛盾点（一句话）
   - hiddenAttitude 隐藏的真实态度（若文本暗示表里不一）
5. relationType 用简短中文标签：夫妻 / 恋人 / 师徒 / 父子 / 母女 / 兄弟 / 君臣 / 上下级 / 主仆 / 朋友 / 知己 / 敌对 / 盟友 / 同门 / 仇人 等；不确定可省略。
6. world 的 category 用：势力 / 地点 / 组织 / 概念 / 物品 / 功法 等。
13. **关系去重**：同一对 source→target 只输出一条。A→B 与 B→A 是两种立场
    （A 单恋 B、B 只当朋友），可以各留一条，但同方向不要重复输出。
14. relationType 只用上面给的固定词表，选最贴切的一个；不要自造近义词
    （「盟友 / 同伴 / 战友 / 朋友」不要对同一对关系轮流用）。
15. 关系总数控制在 40 条以内；优先保留与主要人物相关、羁绊或冲突最深的，
    次要配角之间的寒暄关系可以省略。

# 长度与写法（很重要）
7. 普通字段不超过 80 个汉字；列表字段最多 6 项；aliases 最多 6 个。
8. **没有证据就留空**：字段值直接省略，或在字符串里留空。
   禁止写「证据不足」「未知」「不详」「待补充」这类占位词，也禁止用省略号应付。
9. personality 不要只写抽象词（如"温柔""冷静"）。尽量落到**说话的手感**上：
   口头禅、常见起句、句尾习惯、语气词、以及 1~3 句**原样摘录**的代表台词（放在 description 里，
   形如「代表句：……」），不要改写成旁白总结。
10. 外貌与习惯只写**可重复观察到**的外显特征；不要把只出现一次的桥段动作当成长期人设。
11. 性别与年龄阶段只在文本里有稳定称谓、身份关系或明确描写时才写；拿不准就省略。
12. 如果同一个人物在前后期明显变化，不要强行揉成一个静态人格：
    在 description 里写明「前期…；后期…」，并说清转折由什么引起。

# 输出
仅输出一个 JSON 对象（可被 json.loads 解析），不要任何解释或 Markdown 代码围栏。
字段缺失时直接省略该键。若本章没有可抽取内容，返回 {"characters":[]}。
''';
}

/// 组装用户提示词。
///
/// [focusNames] 非空时只抽这几个人物（以及他们之间的关系）：
/// 整本自动找会把几百个龙套一起抽出来，既贵又难校对；
/// 先锁定 2~4 位主要人物，跑完再增量补人，是更省的做法。
///
/// [chunkIndex] / [chunkTotal] 用来告诉模型这一段在全书里的位置：
/// 前段更适合判断出身与早期立场，中段适合判断稳定的互动模式，
/// 后段才适合判断人物弧线怎么收。不分位置的话，模型会把"后期才变"的人写成一开始就这样。
String buildDistillUserPrompt(
  String chapterTitle,
  String text, {
  List<String> focusNames = const [],
  int? chunkIndex,
  int? chunkTotal,
}) {
  final focus = focusNames
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final focusBlock = focus.isEmpty
      ? ''
      : '''
【只抽这些人物】
${focus.join('、')}
只抽取上述人物（以及他们彼此之间的关系）；其他人即使出现也忽略。
若某人在这段文本里没有出现，就不要输出他。
''';
  final stageBlock = _stageHint(chunkIndex, chunkTotal);
  return '''
【章节】$chapterTitle
${stageBlock.isEmpty ? '' : '\n$stageBlock\n'}
【正文】
$text
$focusBlock
请按系统指令输出 JSON。
''';
}

/// 这一段在全书里的位置提示。
String _stageHint(int? index, int? total) {
  if (index == null || total == null || total <= 1) return '';
  final ratio = (index + 1) / total;
  final stage = ratio <= 0.34
      ? '这是全书的**前段**。更适合判断人物的出身底色、早期立场与初始性情；'
          '不要据此断言他/她的最终态度。'
      : ratio <= 0.67
          ? '这是全书的**中段**。更适合判断人物之间稳定的互动模式、冲突如何升级、'
              '关系往哪个方向走。'
          : '这是全书的**后段**。更适合判断人物弧线如何收束、信念是否松动、'
              '边界是否被打破；写人物时要注意与前段的差异。';
  return '【位置】第 ${index + 1} / $total 段。$stage';
}

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
  final rawName = _str(m['name']) ?? _str(m['title']) ?? '未知人物';
  // 「烈焰（陈思璇）」拆成 name=烈焰 + alias=陈思璇：
  // 不拆的话，同一个人会在关系表里以两种名字各存一份。
  final name = canonicalPersonName(rawName);
  final parenAlias = parentheticalAlias(rawName);
  final aliases = <String>{
    ...(_strList(m['aliases'] ?? m['alias']) ?? const <String>[]),
    if (parenAlias != null) parenAlias,
  }.toList();
  return CharacterCard(
    bookId: bookId,
    name: name,
    aliases: aliases,
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
    sourceName: canonicalPersonName(
        _str(m['source'] ?? m['sourceName'] ?? m['from']) ?? ''),
    targetName: canonicalPersonName(
        _str(m['target'] ?? m['targetName'] ?? m['to']) ?? ''),
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
