// lib/service/character/distill_persist.dart
//
// 蒸馏落库前的纯逻辑：按「指定人物 / 重要度」收口，以及与旧图合并。
//
// 抽出来的原因：这几步决定"用户的设置到底有没有生效"，而它们很容易写错——
// 写错了不会报错，只会表现成"填了名字还是抽出一堆龙套"，
// 或者更糟：只抽一个人，把其他人物全删了。
//
// 名字归一与关系去重放在 models 层（DAO 读写也要用），这里只做导出与组合。

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_dedupe.dart';
import 'package:songjiang_reader/models/character_relation_merge.dart';

export 'package:songjiang_reader/models/character_dedupe.dart';
export 'package:songjiang_reader/models/character_relation_merge.dart';

/// 按指定人物与重要度收口。
///
/// * [focus] 非空：只留下名字（或别名）在其中的卡片；
/// * [minImportance] > 0：再按重要度筛一次。
///
/// 两者可同时生效。都是空/0 时原样返回。
List<CharacterCard> scopeCharacters(
  List<CharacterCard> all, {
  Set<String> focus = const {},
  int minImportance = 0,
}) {
  final normalized = focus
      .map((e) => canonicalPersonName(e))
      .where((e) => e.isNotEmpty)
      .toSet();

  return all.where((c) {
    if (normalized.isNotEmpty) {
      final hitName = normalized.contains(canonicalPersonName(c.name));
      final hitAlias = (c.aliases ?? const <String>[])
          .any((a) => normalized.contains(canonicalPersonName(a)));
      if (!hitName && !hitAlias) return false;
    }
    if (minImportance > 0 && c.importance < minImportance) return false;
    return true;
  }).toList();
}

/// 合并人物：旧的不动，本次抽到的覆盖同一人的旧条目。
///
/// 用于「只抽这几位」的场景——不能整图替换，否则其他人物会被删掉。
///
/// 「同一人」按别名判定，不只看正名：上一版只比 `name` 全等，
/// 于是「凌小东」和「小东」被当成两个人各存一张，
/// 母亲更是分成了「郑怡云 / 妈妈 / 小云 / 凌母」四张。
List<CharacterCard> mergeCharacters(
  List<CharacterCard> existing,
  List<CharacterCard> incoming,
) =>
    mergeSamePerson([...existing, ...incoming], laterWins: true);

/// 合并关系：同一方向的关系本次覆盖旧的，其余保留。
///
/// 旧实现只丢弃"涉及被重抽人物"的旧关系、然后整批追加本次结果，
/// 于是同一对关系在每次蒸馏后多出一份——这是关系表越用越乱的根源。
///
/// 传入 [characters] 时先按别名把两端改写成正名：
/// 否则「妈妈→」和「郑怡云→」会被当成两条不同关系，合并等于没做。
List<CharacterRelation> mergeRelations(
  List<CharacterRelation> existing,
  List<CharacterRelation> incoming, {
  List<CharacterCard>? characters,
}) {
  var all = <CharacterRelation>[...existing, ...incoming];
  if (characters != null && characters.isNotEmpty) {
    final index = aliasToName(characters);
    all = [for (final r in all) remapRelation(r, index)];
  }
  return dedupeRelations(all);
}
