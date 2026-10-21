// lib/models/character_dedupe.dart
//
// 同一人物的多张卡合并（实体消歧）。
//
// 为什么需要：蒸馏是按切片逐段跑的，每段独立判断"这人叫什么"，
// 于是同一个人会被拆成好几张卡——
//   主角：凌小东 / 小东 / 我 / 主角
//   母亲：郑怡云 / 妈妈 / 小云 / 凌母
// 更糟的是每张卡的 aliases 里还填着其他几张的正名，互相指认，
// 关系表也跟着分成「妈妈→」「小云→」「郑怡云→」三条。
//
// 提示词里写了「同一人物用统一正名」也约束不住：模型看不到上一次的输出。
// 所以只能在解析之后做一次实体消歧，用别名互指关系把碎片拼回去。

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_relation_merge.dart';

/// 不能当正名的词：亲称、叙述代词、身份称呼。
///
/// 合并后要在这组里挑一个最"像名字"的当正名，
/// 否则「我」和「妈妈」会被选成主角与母亲的正名。
const Set<String> _genericExact = {
  '我', '你', '他', '她', '它', '咱', '俺', '我们', '你们', '他们', '她们',
  '主角', '男主', '女主', '主人公', '第一人称', '旁白', '众人', '某人',
  '妈妈', '爸爸', '母亲', '父亲', '爸妈', '父母', '老妈', '老爸', '娘', '爹',
  '哥', '姐', '弟', '妹', '哥哥', '姐姐', '弟弟', '妹妹',
  '儿子', '女儿', '长子', '次子', '长女', '次女', '大儿子', '小儿子',
  '丈夫', '妻子', '老公', '老婆', '未婚妻', '未婚夫', '男朋友', '女朋友',
  '爷爷', '奶奶', '外公', '外婆', '叔叔', '阿姨', '舅舅', '姑姑', '婶婶',
  '少爷', '小姐', '老爷', '夫人', '太太', '先生',
};

/// 是不是「不是名字的名字」。
bool isGenericPersonName(String raw) {
  final name = canonicalPersonName(raw);
  if (name.isEmpty) return true;
  if (_genericExact.contains(name)) return true;
  // 「凌母」「凌父」「沈母」：姓氏 + 亲属字
  if (RegExp(r'^[\u4e00-\u9fa5](母|父)$').hasMatch(name)) return true;
  // 「唐老师」「王医生」这类身份称呼
  if (RegExp(r'(老师|医生|护士|经理|部长|局长|老板|同学|学长|学姐)$').hasMatch(name)) {
    return true;
  }
  return false;
}

/// 把指向同一个人的多张卡合并成一张。
///
/// 判定同一人的两条规则：
/// 1. **正名互指**：A 的正名出现在 B 的别名里（或反过来）。
///    这是最强信号——模型自己在别名里承认了"这也是我"。
/// 2. **共用两个以上别名**：只共用一个（比如都叫「老婆」）不动，
///    不同人之间偶尔撞一个称呼是常事，两个以上基本就是同一人。
///
/// [laterWins] 为真时，后出现的卡在字段冲突上优先（增量更新用：
/// 本次重读的结果比旧数据新）。
///
/// 返回顺序按每组首次出现的位置，保证界面稳定。
List<CharacterCard> mergeSamePerson(
  List<CharacterCard> cards, {
  bool laterWins = false,
}) {
  if (cards.length <= 1) return List<CharacterCard>.of(cards);

  // 每张卡的标识集：正名 + 别名，全部归一化
  final keys = <Set<String>>[];
  for (final c in cards) {
    final set = <String>{canonicalPersonName(c.name)};
    for (final a in c.aliases ?? const <String>[]) {
      set.add(canonicalPersonName(a));
    }
    set.remove('');
    keys.add(set);
  }

  final parent = List<int>.generate(cards.length, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  // 总是让下标小的当根：合并后的顺序才等于首次出现的顺序
  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra == rb) return;
    if (ra < rb) {
      parent[rb] = ra;
    } else {
      parent[ra] = rb;
    }
  }

  // 规则 1：正名互指
  for (var i = 0; i < cards.length; i++) {
    for (var j = i + 1; j < cards.length; j++) {
      final nameI = canonicalPersonName(cards[i].name);
      final nameJ = canonicalPersonName(cards[j].name);
      if (nameI == nameJ || keys[j].contains(nameI) || keys[i].contains(nameJ)) {
        union(i, j);
      }
    }
  }

  // 规则 2：共用两个以上别名
  final owners = <String, List<int>>{};
  for (var i = 0; i < cards.length; i++) {
    for (final k in keys[i]) {
      (owners[k] ??= <int>[]).add(i);
    }
  }
  final hits = <String, int>{};
  for (final list in owners.values) {
    if (list.length < 2) continue;
    for (var a = 0; a < list.length; a++) {
      for (var b = a + 1; b < list.length; b++) {
        final key = '${list[a]}:${list[b]}';
        hits[key] = (hits[key] ?? 0) + 1;
      }
    }
  }
  for (final entry in hits.entries) {
    if (entry.value < 2) continue;
    final parts = entry.key.split(':');
    union(int.parse(parts[0]), int.parse(parts[1]));
  }

  final groups = <int, List<int>>{};
  for (var i = 0; i < cards.length; i++) {
    (groups[find(i)] ??= <int>[]).add(i);
  }

  final roots = groups.keys.toList()..sort();
  return [
    for (final root in roots)
      groups[root]!.length == 1
          ? cards[groups[root]!.first]
          : _mergeGroup(
              [for (final i in groups[root]!) cards[i]],
              laterWins: laterWins,
            ),
  ];
}

CharacterCard _mergeGroup(List<CharacterCard> group, {required bool laterWins}) {
  // 正名：先看像不像名字，再看长度，最后比重要度
  int score(CharacterCard c) {
    final n = canonicalPersonName(c.name);
    return (isGenericPersonName(n) ? 0 : 1000) + n.length * 10 + c.importance;
  }

  var best = group.first;
  for (final c in group) {
    if (score(c) > score(best)) best = c;
  }
  final name = canonicalPersonName(best.name);

  final aliases = <String>[];
  void addAlias(String? raw) {
    final v = canonicalPersonName(raw ?? '');
    if (v.isEmpty || v == name) return;
    if (!aliases.contains(v)) aliases.add(v);
  }

  for (final c in group) {
    addAlias(c.name);
    for (final a in c.aliases ?? const <String>[]) {
      addAlias(a);
    }
  }

  // 文本字段取信息量最大的那份；增量更新时取最新的
  String? pickText(String? Function(CharacterCard) read) {
    String? chosen;
    for (final c in group) {
      final v = read(c)?.trim();
      if (v == null || v.isEmpty) continue;
      if (chosen == null || laterWins || v.length > chosen.length) {
        chosen = v;
      }
    }
    return chosen;
  }

  String? pickFirst(String? Function(CharacterCard) read) {
    for (final c in group) {
      final v = read(c)?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  var importance = 0;
  DateTime? created;
  for (final c in group) {
    if (c.importance > importance) importance = c.importance;
    if (created == null || c.createdAt.isBefore(created)) created = c.createdAt;
  }

  int? id;
  for (final c in group) {
    if (c.id != null) {
      id = c.id;
      break;
    }
  }

  return CharacterCard(
    id: id,
    bookId: best.bookId,
    name: name,
    aliases: aliases.isEmpty ? null : aliases,
    gender: pickFirst((c) => c.gender),
    role: pickFirst((c) => c.role),
    importance: importance,
    personality: pickText((c) => c.personality),
    background: pickText((c) => c.background),
    motivation: pickText((c) => c.motivation),
    appearance: pickText((c) => c.appearance),
    firstAppearanceChapter: pickFirst((c) => c.firstAppearanceChapter),
    description: pickText((c) => c.description),
    avatarPath: pickFirst((c) => c.avatarPath),
    source: best.source,
    createdAt: created ?? best.createdAt,
    updatedAt: best.updatedAt,
  );
}

/// 别名 → 正名。用来把关系里的「妈妈」「小云」改写成「郑怡云」。
Map<String, String> aliasToName(List<CharacterCard> cards) {
  final map = <String, String>{};
  for (final c in cards) {
    final name = canonicalPersonName(c.name);
    map[name] = name;
  }
  for (final c in cards) {
    final name = canonicalPersonName(c.name);
    for (final a in c.aliases ?? const <String>[]) {
      final v = canonicalPersonName(a);
      // 不覆盖已有的正名，否则「妈妈」可能被当成某个别名的别名
      if (v.isNotEmpty && !map.containsKey(v)) map[v] = name;
    }
  }
  return map;
}

/// 按别名表改写一条关系的两端。表里没有的名字原样保留。
CharacterRelation remapRelation(
  CharacterRelation r,
  Map<String, String> index,
) {
  final s = canonicalPersonName(r.sourceName);
  final t = canonicalPersonName(r.targetName);
  final ns = index[s] ?? s;
  final nt = index[t] ?? t;
  if (ns == s && nt == t) return r;
  return CharacterRelation(
    id: r.id,
    bookId: r.bookId,
    sourceName: ns,
    targetName: nt,
    relationType: r.relationType,
    trust: r.trust,
    affection: r.affection,
    powerGap: r.powerGap,
    conflictPoint: r.conflictPoint,
    hiddenAttitude: r.hiddenAttitude,
    note: r.note,
    source: r.source,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  );
}
