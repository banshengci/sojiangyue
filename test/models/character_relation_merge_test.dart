import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_relation_merge.dart';

/// 关系去重与人物名归一。
///
/// 起因：实机截图里同一个角色对着同一个对象有八九条关系
/// （盟友/同伴/战友/朋友…数值各不相同）。根因是蒸馏逐段跑，
/// 每段都 `relations.addAll(...)`，同一方向的关系被反复追加。
void main() {
  final t0 = DateTime(2026);

  CharacterRelation rel(
    String from,
    String to, {
    String? type,
    int trust = 50,
    int affection = 50,
  }) =>
      CharacterRelation(
        bookId: 1,
        sourceName: from,
        targetName: to,
        relationType: type,
        trust: trust,
        affection: affection,
        createdAt: t0,
        updatedAt: t0,
      );

  group('人物名归一', () {
    test('剥掉末尾括号别名', () {
      expect(canonicalPersonName('烈焰（陈思璇）'), '烈焰');
      expect(canonicalPersonName('烈焰(陈思璇)'), '烈焰');
    });

    test('没有括号名保持原样，只去空白', () {
      expect(canonicalPersonName('  林黛玉 '), '林黛玉');
      expect(canonicalPersonName('贾 宝 玉'), '贾宝玉');
    });

    test('括号在中间不动（不是别名后缀）', () {
      expect(canonicalPersonName('某（甲）人'), '某（甲）人');
    });

    test('括号别名能被单独取出来', () {
      expect(parentheticalAlias('烈焰（陈思璇）'), '陈思璇');
      expect(parentheticalAlias('烈焰'), isNull);
    });
  });

  group('关系去重', () {
    test('同一方向多条只留一条', () {
      final out = dedupeRelations([
        rel('姬动', '云天机', type: '盟友', trust: 60),
        rel('姬动', '云天机', type: '同伴', trust: 70),
        rel('姬动', '云天机', type: '战友', trust: 80),
      ]);
      expect(out.length, 1);
      expect(out.single.trust, 80);
      expect(out.single.relationType, '战友');
    });

    test('反向关系不算重复（两种立场）', () {
      final out = dedupeRelations([
        rel('姬动', '蓝宝儿', type: '单恋', affection: 70),
        rel('蓝宝儿', '姬动', type: '朋友', affection: 40),
      ]);
      expect(out.length, 2);
    });

    test('名字写法不同但归一后相同 → 合并', () {
      final out = dedupeRelations([
        rel('姬动', '烈焰（陈思璇）', type: '恋人', trust: 90),
        rel('姬动', '烈焰', type: '恋人', trust: 95),
      ]);
      expect(out.length, 1);
      expect(out.single.trust, 95);
    });

    test('后者没写关系类型时，保留前者的类型', () {
      final out = dedupeRelations([
        rel('姬动', '姚谦书', type: '盟友', trust: 75),
        rel('姬动', '姚谦书', type: null, trust: 80),
      ]);
      expect(out.single.trust, 80, reason: '数值以后出现的为准');
      expect(out.single.relationType, '盟友', reason: '类型不该被空值抹掉');
    });

    test('保留首次出现的顺序，界面不跳动', () {
      final out = dedupeRelations([
        rel('A', 'B'),
        rel('C', 'D'),
        rel('A', 'B', trust: 90),
      ]);
      expect(out.map((r) => r.sourceName).toList(), ['A', 'C']);
    });

    test('空列表与单条不炸', () {
      expect(dedupeRelations(const []), isEmpty);
      expect(dedupeRelations([rel('A', 'B')]).length, 1);
    });
  });
}
