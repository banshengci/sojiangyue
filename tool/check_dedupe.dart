// 用真实蒸馏数据验一遍实体消歧。
//
// 这两个模型文件是纯 Dart（只依赖 dart:convert），不经过 Flutter，
// 所以在本机跑不了 flutter test 的情况下，可以用 dart 直接验证逻辑。
//
//   dart run tool/check_dedupe.dart
//
// 注意：必须用 package: 导入，不能写相对路径——
// 相对路径会让同一个类出现两份，和 models 里的 package: 引用对不上类型。

import 'dart:io';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_dedupe.dart';
import 'package:songjiang_reader/models/character_relation_merge.dart';

CharacterCard card(String name, List<String> aliases, int importance) {
  final now = DateTime(2026, 10, 21);
  return CharacterCard(
    bookId: 1,
    name: name,
    aliases: aliases,
    importance: importance,
    createdAt: now,
    updatedAt: now,
  );
}

CharacterRelation rel(String from, String to, int trust) {
  final now = DateTime(2026, 10, 21);
  return CharacterRelation(
    bookId: 1,
    sourceName: from,
    targetName: to,
    trust: trust,
    affection: 50,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final cards = [
    card('凌小东', ['我', '哥', '长子', '儿子', '小东', '凌家长男'], 95),
    card('妈妈', ['老妈', '妈', '母亲', '母上大人', '母老虎', '小云'], 95),
    card('小东', ['我', '东', '哥', '哥哥', '神哥哥', '儿子', '新郎'], 95),
    card('小云', ['妈妈', '妈', '母上大人'], 95),
    card('我', ['神经病', '哥', '儿子', '长子', '主角', '家中长子'], 95),
    card('安诺', ['诺诺'], 92),
    card('郑怡云', ['妈妈', '老妈', '母上大人', '母亲大人', '云姐'], 92),
    card('主角', ['小东'], 88),
    card('凌母', ['妈妈', '老妈', '咱妈'], 85),
    card('陆依依', ['依依', '陆老师'], 82),
  ];

  final merged = mergeSamePerson(cards);
  stdout.writeln('合并前 ${cards.length} 张 → 合并后 ${merged.length} 张');
  for (final c in merged) {
    stdout.writeln('  ${c.name}  (重要度 ${c.importance})  别名: ${(c.aliases ?? []).join('、')}');
  }

  final index = aliasToName(merged);
  final relations = [
    rel('凌小东', '妈妈', 55),
    rel('凌小东', '郑怡云', 20),
    rel('妈妈', '凌小东', 50),
    rel('小云', '凌小东', 45),
    rel('凌小东', '陆依依', 80),
  ];
  final deduped = dedupeRelations([
    for (final r in relations) remapRelation(r, index),
  ]);
  stdout.writeln('\n关系 ${relations.length} 条 → ${deduped.length} 条');
  for (final r in deduped) {
    stdout.writeln('  ${r.sourceName} → ${r.targetName}  trust=${r.trust}');
  }
}
