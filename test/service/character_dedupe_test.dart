// 实体消歧：同一人物的多张卡合并。
//
// 数据取自一次真实蒸馏的结果（增量更新 + 只看主要人物）：
// 主角被拆成「凌小东 / 小东 / 我 / 主角」四张，
// 母亲被拆成「郑怡云 / 妈妈 / 小云 / 凌母」四张，
// 每张卡的 aliases 里还填着其他几张的正名。

import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/distill_persist.dart';

CharacterCard card(
  String name, {
  List<String>? aliases,
  int importance = 90,
  String? description,
  String? personality,
}) {
  final now = DateTime(2026, 10, 21);
  return CharacterCard(
    bookId: 1,
    name: name,
    aliases: aliases,
    importance: importance,
    description: description,
    personality: personality,
    createdAt: now,
    updatedAt: now,
  );
}

CharacterRelation rel(
  String from,
  String to, {
  String? type,
  int trust = 50,
  int affection = 50,
}) {
  final now = DateTime(2026, 10, 21);
  return CharacterRelation(
    bookId: 1,
    sourceName: from,
    targetName: to,
    relationType: type,
    trust: trust,
    affection: affection,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  // 主角的四种叫法，别名单互有交叉
  final heroVariants = [
    card('凌小东', aliases: ['我', '哥', '长子', '儿子', '小东', '凌家长男'], importance: 95,
        description: '第一人称叙述者，嘴贫爱顶嘴。'),
    card('小东', aliases: ['我', '东', '哥', '哥哥', '神哥哥', '儿子', '新郎'], importance: 95,
        description: '本章与妈妈性事后的次日清晨，被妈妈宣布「这是最后一次」。'),
    card('我', aliases: ['神经病', '哥', '儿子', '长子', '主角', '家中长子'], importance: 95),
    card('主角', aliases: ['小东'], importance: 88),
  ];

  // 母亲的四种叫法
  final motherVariants = [
    card('郑怡云', aliases: ['妈妈', '老妈', '母上大人', '母亲大人', '云姐'], importance: 92),
    card('妈妈', aliases: ['老妈', '妈', '母亲', '母上大人', '母老虎', '小云'], importance: 95),
    card('小云', aliases: ['妈妈', '妈', '母上大人'], importance: 95),
    card('凌母', aliases: ['妈妈', '老妈', '咱妈'], importance: 85),
  ];

  group('isGenericPersonName', () {
    test('亲称、代词、姓氏代称都不是名字', () {
      for (final n in ['我', '主角', '妈妈', '老妈', '凌母', '凌父', '唐老师']) {
        expect(isGenericPersonName(n), isTrue, reason: n);
      }
    });

    test('真名不是泛称', () {
      for (final n in ['凌小东', '郑怡云', '陆依依', '安诺']) {
        expect(isGenericPersonName(n), isFalse, reason: n);
      }
    });
  });

  group('mergeSamePerson', () {
    test('主角的四种叫法合成一张，正名取真名', () {
      final merged = mergeSamePerson(heroVariants);
      expect(merged.length, 1);
      final hero = merged.single;
      expect(hero.name, '凌小东', reason: '「我」「主角」不能当正名');
      expect(hero.aliases, containsAll(['我', '主角', '小东']));
      expect(hero.aliases, isNot(contains('凌小东')));
    });

    test('母亲的四种叫法合成一张，正名取真名', () {
      final merged = mergeSamePerson(motherVariants);
      expect(merged.length, 1);
      final mom = merged.single;
      expect(mom.name, '郑怡云', reason: '「妈妈」「小云」「凌母」都不能当正名');
      expect(mom.aliases, containsAll(['妈妈', '小云', '凌母']));
    });

    test('合并后保留信息量最大的文本与最高重要度', () {
      final merged = mergeSamePerson(heroVariants);
      final hero = merged.single;
      expect(hero.importance, 95);
      // 「小东」那张的描述更长，应该留下它
      expect(hero.description, contains('次日清晨'));
    });

    test('不相干的人不会被合并', () {
      final merged = mergeSamePerson([
        ...heroVariants,
        card('陆依依', aliases: ['依依', '陆老师']),
        card('安诺', aliases: ['诺诺']),
      ]);
      expect(merged.map((c) => c.name), containsAll(['凌小东', '陆依依', '安诺']));
      expect(merged.length, 3);
    });

    test('只共用一个别名不合并（避免误伤）', () {
      // 两个不同的人都被人叫过「老婆」，不该因此合并
      final merged = mergeSamePerson([
        card('陆依依', aliases: ['老婆', '依依']),
        card('安诺', aliases: ['老婆', '诺诺']),
      ]);
      expect(merged.length, 2);
    });

    test('正名出现在对方别名里就合并', () {
      final merged = mergeSamePerson([
        card('陆依依', aliases: ['依依']),
        card('依依', aliases: ['陆依依', '陆老师']),
      ]);
      expect(merged.length, 1);
      expect(merged.single.name, '陆依依');
    });

    test('合并不改变首次出现的顺序', () {
      final merged = mergeSamePerson([...motherVariants, ...heroVariants]);
      expect(merged.map((c) => c.name).toList(), ['郑怡云', '凌小东']);
    });
  });

  group('关系改写', () {
    test('「妈妈」和「郑怡云」指向同一人时合成一条关系', () {
      final cards = mergeSamePerson(motherVariants);
      final merged = mergeRelations(
        const [],
        [
          rel('凌小东', '妈妈', type: '母子', trust: 55, affection: 75),
          rel('凌小东', '郑怡云', type: '母子', trust: 20, affection: 85),
        ],
        characters: cards,
      );
      expect(merged.length, 1, reason: '同一对关系不能因为叫法不同存两条');
      expect(merged.single.targetName, '郑怡云');
      expect(merged.single.trust, 20, reason: '后者覆盖前者');
    });

    test('旧库里的碎片关系也会被归一化', () {
      final cards = mergeSamePerson(motherVariants);
      final merged = mergeRelations(
        [rel('妈妈', '凌小东', type: '母子')],
        [rel('郑怡云', '凌小东', type: '母子', trust: 30)],
        characters: cards,
      );
      expect(merged.length, 1);
      expect(merged.single.sourceName, '郑怡云');
    });

    test('别名表里没有的名字原样保留', () {
      final cards = mergeSamePerson(motherVariants);
      final merged = mergeRelations(
        const [],
        [rel('凌小东', '陌生人', type: '关联')],
        characters: cards,
      );
      expect(merged.single.targetName, '陌生人');
    });
  });
}
