// lib/models/character_relation_merge.dart
//
// 人物名的归一与关系去重。
//
// 放在 models 层而不是 service：DAO 读写关系时也要用——
// 老库里已经存进去的重复关系不会自己消失，必须读取时就地合并，
// 否则用户不重跑蒸馏就永远看到那一屏重复。
//
// 为什么会有重复：蒸馏按切片逐段跑，每段都会回一份关系。
// 原先的实现是 `relations.addAll(...)`，同一对关系每段都追加一条，
// 于是「盟友 → 云天机」能出现五六次，数值还各不相同。

import 'package:songjiang_reader/models/character_card.dart';

/// 规范人物名：去掉首尾空白与内部空白，并剥掉名字末尾的括号别名。
///
/// 蒸馏输出里同一个人常有几种写法：「烈焰」「烈焰（陈思璇）」「烈焰(陈思璇)」。
/// 不归一化的话，关系表里这三者会被当成三个人各存一条。
String canonicalPersonName(String raw) {
  var name = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (name.isEmpty) return name;
  final m = RegExp(r'^(.*?)[（(]([^（）()]{1,20})[）)]$').firstMatch(name);
  if (m != null) {
    final base = m.group(1)!.trim();
    if (base.isNotEmpty) return base;
  }
  return name;
}

/// 从「烈焰（陈思璇）」里取出被剥掉的别名；没有则返回 null。
String? parentheticalAlias(String raw) {
  final name = raw.trim();
  final m = RegExp(r'^.*?[（(]([^（）()]{1,20})[）)]$').firstMatch(name);
  final alias = m?.group(1)?.trim();
  if (alias == null || alias.isEmpty) return null;
  return alias == canonicalPersonName(name) ? null : alias;
}

/// 一对方的关系键：按方向区分。
///
/// `A→B` 与 `B→A` 是两种立场（A 单恋 B、B 只当朋友），不能合并；
/// 同方向重复出现的一定是同一条关系。
String relationKey(CharacterRelation r) =>
    '${canonicalPersonName(r.sourceName)}→${canonicalPersonName(r.targetName)}';

/// 同一方向的关系去重。
///
/// **后者覆盖前者**：切片按全书顺序跑，越靠后的切片越接近"现在"的状态。
/// 但覆盖时保留前者独有的非空字段——后期切片没提到关系类型，
/// 不该把前面已经抽到的「恋人」抹成空。
///
/// 返回顺序按首次出现的位置，保证界面稳定（不会因为重跑而跳动）。
List<CharacterRelation> dedupeRelations(List<CharacterRelation> list) {
  final byKey = <String, CharacterRelation>{};
  for (final r in list) {
    final key = relationKey(r);
    final prev = byKey[key];
    byKey[key] = prev == null ? r : _mergeRelation(prev, r);
  }
  return byKey.values.toList();
}

CharacterRelation _mergeRelation(
  CharacterRelation prev,
  CharacterRelation next,
) {
  String? pick(String? older, String? newer) {
    final y = newer?.trim() ?? '';
    if (y.isNotEmpty) return y;
    final x = older?.trim() ?? '';
    return x.isEmpty ? null : x;
  }

  return CharacterRelation(
    id: next.id ?? prev.id,
    bookId: next.bookId,
    sourceName: next.sourceName,
    targetName: next.targetName,
    relationType: pick(prev.relationType, next.relationType),
    trust: next.trust,
    affection: next.affection,
    powerGap: next.powerGap,
    conflictPoint: pick(prev.conflictPoint, next.conflictPoint),
    hiddenAttitude: pick(prev.hiddenAttitude, next.hiddenAttitude),
    note: pick(prev.note, next.note),
    source: next.source,
    createdAt: prev.createdAt,
    updatedAt: next.updatedAt,
  );
}
