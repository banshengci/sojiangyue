import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/distill_persist.dart';

/// 蒸馏落库前的收口与合并。
///
/// 这组逻辑对应两个真实抱怨：
/// 1. 「填了人物名，还是抽出一堆龙套」——收口没生效；
/// 2. 「只抽一个人，结果其他人物全没了」——用替换代替了合并。
void main() {
  final t0 = DateTime(2026, 1, 1);

  CharacterCard card(
    String name, {
    int importance = 50,
    List<String>? aliases,
  }) =>
      CharacterCard(
        bookId: 1,
        name: name,
        aliases: aliases,
        importance: importance,
        createdAt: t0,
        updatedAt: t0,
      );

  CharacterRelation rel(String a, String b) => CharacterRelation(
        bookId: 1,
        sourceName: a,
        targetName: b,
        createdAt: t0,
        updatedAt: t0,
      );

  group('scopeCharacters：指定人物', () {
    final all = [card('林黛玉'), card('贾宝玉'), card('袭人')];

    test('不填名字、不筛重要度 → 原样返回', () {
      expect(scopeCharacters(all).length, 3);
    });

    test('只保留指定名字', () {
      final kept = scopeCharacters(all, focus: {'林黛玉'});
      expect(kept.map((c) => c.name), ['林黛玉']);
    });

    test('别名命中同样保留', () {
      final withAlias = [
        card('林黛玉', aliases: ['黛玉', '颦儿']),
        card('袭人'),
      ];
      final kept = scopeCharacters(withAlias, focus: {'黛玉'});
      expect(kept.single.name, '林黛玉');
    });

    test('名字前后空格会被裁掉', () {
      final kept = scopeCharacters(all, focus: {'  林黛玉  '});
      expect(kept.single.name, '林黛玉');
    });

    test('空字符串名字被忽略，不会变成"一个都不要"', () {
      expect(scopeCharacters(all, focus: {'', '  '}).length, 3);
    });

    test('名字在书里不存在 → 结果为空（而不是回退成全部）', () {
      expect(scopeCharacters(all, focus: {'不存在的人'}), isEmpty);
    });
  });

  group('scopeCharacters：重要度', () {
    final all = [
      card('主角', importance: 90),
      card('配角', importance: 60),
      card('龙套', importance: 20),
    ];

    test('minImportance=50 只留主角与配角', () {
      final kept = scopeCharacters(all, minImportance: 50);
      expect(kept.map((c) => c.name), ['主角', '配角']);
    });

    test('minImportance=0 不过滤', () {
      expect(scopeCharacters(all, minImportance: 0).length, 3);
    });

    test('与指定人物同时生效：先看名字再看重要度', () {
      final kept = scopeCharacters(
        all,
        focus: {'主角', '龙套'},
        minImportance: 50,
      );
      expect(kept.map((c) => c.name), ['主角']);
    });
  });

  group('mergeCharacters：局部抽取不能删掉其他人', () {
    test('旧人物保留，同名被新结果替换', () {
      final existing = [card('林黛玉', importance: 30), card('贾宝玉')];
      final incoming = [card('林黛玉', importance: 95)];

      final merged = mergeCharacters(existing, incoming);
      expect(merged.length, 2);
      final lin = merged.firstWhere((c) => c.name == '林黛玉');
      expect(lin.importance, 95, reason: '同名应以新结果为准');
      expect(merged.any((c) => c.name == '贾宝玉'), isTrue,
          reason: '没被重抽的人物必须保留');
    });

    test('新人物追加', () {
      final merged = mergeCharacters([card('贾宝玉')], [card('林黛玉')]);
      expect(merged.map((c) => c.name), ['贾宝玉', '林黛玉']);
    });

    test('空旧图时等于直接写入', () {
      expect(mergeCharacters([], [card('林黛玉')]).single.name, '林黛玉');
    });
  });

  group('mergeRelations', () {
    test('涉及被重抽人物的旧关系丢弃，其余保留', () {
      final existing = [
        rel('林黛玉', '贾宝玉'), // 涉及重抽对象 → 丢
        rel('袭人', '晴雯'), // 无关 → 留
      ];
      final incoming = [rel('林黛玉', '贾宝玉')];

      final merged = mergeRelations(existing, incoming);
      expect(merged.length, 2);
      expect(merged.any((r) => r.sourceName == '袭人'), isTrue);
      expect(
        merged.where((r) => r.sourceName == '林黛玉').length,
        1,
        reason: '同一对关系不应重复',
      );
    });

    test('没有新关系时原样保留', () {
      final existing = [rel('甲', '乙')];
      expect(mergeRelations(existing, const []).length, 1);
    });
  });
}
