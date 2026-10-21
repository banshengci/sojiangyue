// 「各怀心思」段的生成逻辑。
//
// 重点是方向性：关系 A→B 记的是 A 的态度。
// 双向关系同时存在时，各自只能看到自己那一条，
// 不能把对方的心里话当成自己的立场。

import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/relation_playbook.dart';

CharacterCard card(String name, {String? motivation}) {
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

/// 按「独占一行」的 `**名字**` 切块。
///
/// 不能直接用 `indexOf('**郑怡云**')`：人物段里还有「- 对 **郑怡云**（母子）」
/// 这种引用，第一次命中会落在别人的段中间，切出来的内容是错的。
Map<String, String> splitBlocks(String out) {
  final blocks = <String, String>{};
  String? current;
  final buf = StringBuffer();
  for (final line in out.split('\n')) {
    final m = RegExp(r'^\*\*(.+?)\*\*$').firstMatch(line);
    if (m != null) {
      if (current != null) blocks[current] = buf.toString();
      current = m.group(1)!;
      buf.clear();
    } else if (current != null) {
      buf.writeln(line);
    }
  }
  if (current != null) blocks[current] = buf.toString();
  return blocks;
}

void main() {
  final son = card('凌小东', motivation: '查清父亲死因');
  final mom = card('郑怡云', motivation: '把儿子挡在那些事之外');

  test('双向关系各用各的方向，不把对方心里话算成自己的', () {
    final out = buildRelationPlaybook(
      characters: [son, mom],
      relations: [
        // 母亲的态度：信儿子，但瞒着他
        rel('郑怡云', '凌小东', type: '母子', trust: 70, affection: 85,
            hidden: '宁可被恨也要瞒到底'),
        // 儿子的态度：隐约觉得被骗
        rel('凌小东', '郑怡云', type: '母子', trust: 45, affection: 80,
            hidden: '隐约觉得她在骗自己'),
      ],
    );
    final blocks = splitBlocks(out);

    expect(blocks['凌小东'], contains('隐约觉得她在骗自己'));
    expect(blocks['凌小东'], isNot(contains('宁可被恨也要瞒到底')),
        reason: '母亲的心里话不能出现在儿子的段里');

    expect(blocks['郑怡云'], contains('宁可被恨也要瞒到底'));
    expect(blocks['郑怡云'], isNot(contains('隐约觉得她在骗自己')),
        reason: '儿子的心里话不能出现在母亲的段里');
  });

  test('同一个人对同一个对手只演一条', () {
    final out = buildRelationPlaybook(
      characters: [son, mom],
      relations: [
        rel('郑怡云', '凌小东', trust: 70),
        rel('凌小东', '郑怡云', trust: 45),
      ],
    );
    final blocks = splitBlocks(out);
    expect('对 **郑怡云**'.allMatches(blocks['凌小东']!).length, 1);
    expect('对 **凌小东**'.allMatches(blocks['郑怡云']!).length, 1);
  });

  test('只有反向关系时，数值当近似值，但不搬心里话', () {
    final out = buildRelationPlaybook(
      characters: [son, mom],
      relations: [
        rel('郑怡云', '凌小东', trust: 70, hidden: '宁可被恨也要瞒到底',
            conflict: '儿子越查越近'),
      ],
    );
    final blocks = splitBlocks(out);
    expect(blocks['凌小东'], contains('对 **郑怡云**'), reason: '反向关系仍要能演');
    expect(blocks['凌小东'], isNot(contains('宁可被恨也要瞒到底')));
    expect(blocks['凌小东'], isNot(contains('儿子越查越近')));
  });

  test('信任高低会改变「会做/不会做」', () {
    final high = splitBlocks(buildRelationPlaybook(
      characters: [son, mom],
      relations: [rel('凌小东', '郑怡云', trust: 80)],
    ));
    final low = splitBlocks(buildRelationPlaybook(
      characters: [son, mom],
      relations: [rel('凌小东', '郑怡云', trust: -70)],
    ));
    expect(high['凌小东'], contains('把后背交给对方'));
    expect(low['凌小东'], contains('认定对方是敌人'));
    expect(low['凌小东'], contains('借别人的手'));
  });

  test('不在场的人不进关系段', () {
    final out = buildRelationPlaybook(
      characters: [son, mom],
      relations: [
        rel('凌小东', '安诺', type: '仇人', trust: -70),
        rel('凌小东', '郑怡云', type: '母子', trust: 45),
      ],
    );
    expect(out, isNot(contains('安诺')), reason: '场上没人接得住这条线');
  });

  test('单人玩法保留场外对手（那是他的性格来源）', () {
    final out = buildRelationPlaybook(
      characters: [son],
      relations: [rel('凌小东', '安诺', type: '仇人', trust: -70)],
      allowOffstageCounterpart: true,
    );
    expect(out, contains('安诺'));
  });

  test('所求写成「自己的算盘」，不预设性别', () {
    final out = buildRelationPlaybook(
      characters: [mom],
      relations: [rel('郑怡云', '凌小东', trust: 70)],
      allowOffstageCounterpart: true,
    );
    expect(out, contains('自己的算盘'));
    expect(out, isNot(contains('他的算盘')));
  });

  test('没有关系时不生成这一段', () {
    expect(buildRelationPlaybook(characters: [son], relations: const []), '');
  });

  test('带上「怎么用」的规则', () {
    final out = buildRelationPlaybook(
      characters: [son, mom],
      relations: [rel('凌小东', '郑怡云', trust: 45)],
    );
    expect(out, contains('关系是**动机**，不是台词'));
    expect(out, contains('同盟是暂时的'));
    expect(out, contains('以本局的数值为准'));
  });
}
