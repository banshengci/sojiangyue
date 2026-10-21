// 渲染「各怀心思」段，看实际喂给模型的是什么。
//
//   dart run tool/check_playbook.dart

import 'dart:io';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/relation_playbook.dart';

CharacterCard card(String name, String? motivation) {
  final now = DateTime(2026, 10, 21);
  return CharacterCard(
    bookId: 1,
    name: name,
    motivation: motivation,
    importance: 90,
    createdAt: now,
    updatedAt: now,
  );
}

CharacterRelation rel(
  String a,
  String b, {
  String? type,
  int trust = 0,
  int affection = 0,
  int powerGap = 0,
  String? conflict,
  String? hidden,
}) {
  final now = DateTime(2026, 10, 21);
  return CharacterRelation(
    bookId: 1,
    sourceName: a,
    targetName: b,
    relationType: type,
    trust: trust,
    affection: affection,
    powerGap: powerGap,
    conflictPoint: conflict,
    hiddenAttitude: hidden,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final cast = [
    card('凌小东', '查清父亲死因，护住这个家'),
    card('郑怡云', '把儿子挡在那些事之外'),
    card('安诺', '拿回被凌家扣下的那本账'),
    card('陆依依', '保住医院，不想再有人死'),
  ];

  final relations = [
    // 母子：亲近、信任，但母亲瞒着他
    rel('郑怡云', '凌小东', type: '母子', trust: 70, affection: 85,
        conflict: '儿子越查越近，她不知道该不该说', hidden: '宁可被恨也要瞒到底'),
    // 主角对母亲：信任但有被隐瞒的直觉
    rel('凌小东', '郑怡云', type: '母子', trust: 45, affection: 80,
        hidden: '隐约觉得她在骗自己'),
    // 敌对
    rel('安诺', '凌小东', type: '仇人', trust: -70, affection: -60,
        conflict: '他父亲留下的东西', hidden: '其实并不想真的动手'),
    // 同盟但不完全信任
    rel('陆依依', '凌小东', type: '盟友', trust: 30, affection: 40,
        powerGap: -30, conflict: '她怕他把医院拖下水'),
  ];

  print(buildRelationPlaybook(characters: cast, relations: relations));

  // 关键性质自检（flutter test 在本机跑不起来，这里做同等验证）
  final out = buildRelationPlaybook(characters: cast, relations: relations);
  // 按行首匹配分块：「对 **郑怡云**」这种引用不算新块
  int blockStart(String name) => out.indexOf('\n**$name**\n');
  final sonAt = blockStart('凌小东');
  final momAt = blockStart('郑怡云');
  final foeAt = blockStart('安诺');
  final sonBlock = out.substring(sonAt, momAt);
  final momBlock = out.substring(momAt, foeAt);

  void check(String what, bool ok) {
    print('${ok ? 'PASS' : 'FAIL'}  $what');
    if (!ok) exitCode = 1;
  }

  print('\n--- 自检 ---');
  check('儿子用自己的心里话', sonBlock.contains('隐约觉得她在骗自己'));
  check('儿子的段里没有母亲的心里话', !sonBlock.contains('宁可被恨也要瞒到底'));
  check('母亲用自己的心里话', momBlock.contains('宁可被恨也要瞒到底'));
  check('母亲对儿子只演一条', '对 **凌小东**'.allMatches(momBlock).length == 1);
  check('儿子对母亲只演一条', '对 **郑怡云**'.allMatches(sonBlock).length == 1);
}
