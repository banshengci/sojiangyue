// lib/service/character/distill_persist.dart
//
// 蒸馏落库前的纯逻辑：按「指定人物 / 重要度」收口，以及与旧图合并。
//
// 抽出来的原因：这两步决定"用户的设置到底有没有生效"，而它们很容易写错——
// 写错了不会报错，只会表现成"填了名字还是抽出一堆龙套"，
// 或者更糟：只抽一个人，把其他人物全删了。

import 'package:songjiang_reader/models/character_card.dart';

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
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();

  return all.where((c) {
    if (normalized.isNotEmpty) {
      final hitName = normalized.contains(c.name.trim());
      final hitAlias = (c.aliases ?? const <String>[])
          .any((a) => normalized.contains(a.trim()));
      if (!hitName && !hitAlias) return false;
    }
    if (minImportance > 0 && c.importance < minImportance) return false;
    return true;
  }).toList();
}

/// 合并人物：旧的不动，本次抽到的覆盖同名旧条目。
///
/// 用于「只抽这几位」的场景——不能整图替换，否则其他人物会被删掉。
List<CharacterCard> mergeCharacters(
  List<CharacterCard> existing,
  List<CharacterCard> incoming,
) {
  final incomingNames = incoming.map((c) => c.name).toSet();
  return [
    ...existing.where((c) => !incomingNames.contains(c.name)),
    ...incoming,
  ];
}

/// 合并关系：涉及被重抽人物的旧关系丢弃（可能已过时），其余保留。
List<CharacterRelation> mergeRelations(
  List<CharacterRelation> existing,
  List<CharacterRelation> incoming,
) {
  final touched = <String>{
    for (final r in incoming) ...[r.sourceName, r.targetName],
  };
  return [
    ...existing.where((r) =>
        !touched.contains(r.sourceName) && !touched.contains(r.targetName)),
    ...incoming,
  ];
}
