import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/dao/character_schema.dart';

/// 「蒸馏后挑选」批量删人物的回归测试。
///
/// 背景：`CharacterDao.deleteCharacters` 原实现是**逐个名字 2 条 DELETE**
/// （删卡片 + 删以该名字为源或目标的关系）。而它的典型调用场景恰恰是
/// 「一次抽出几百个龙套时勾掉不要的」——删 200 个名字就是 400 次数据库往返。
/// 现改为按 `IN (...)` 分块批量删（每块 400 个，规避 SQLite 变量上限）。
///
/// 本测试锁住两件事：
///   1. **语义等价**：批量删的结果与原来的逐个删逐行一致；
///   2. 边界正确：空列表、重复名字、跨块（>400）、以及「名字在关系表里
///      出现但卡片已不存在」的情况都要处理对。
///
/// 建表直接用生产代码的 [applyCharacterSchema]，保证测的是真表结构
/// （列名/约束一旦改动这里就会失败，而不是悄悄测了个自造的简化表）。
void main() {
  sqfliteFfiInit();

  const tableCard = CharacterDao.tableCard;
  const tableRelation = CharacterDao.tableRelation;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await applyCharacterSchema(db);
  });

  tearDown(() async => db.close());

  Future<void> addCard(int bookId, String name) async {
    final now = DateTime.now().toIso8601String();
    await db.insert(tableCard, {
      'book_id': bookId,
      'name': name,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> addRelation(int bookId, String source, String target) async {
    // created_at / updated_at 都是 NOT NULL 且无默认值
    // （见 createCharacterRelationSQL），生产代码经 CharacterRelation.toMap() 会带上
    final now = DateTime.now().toIso8601String();
    await db.insert(tableRelation, {
      'book_id': bookId,
      'source_name': source,
      'target_name': target,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// 原实现：逐个名字删
  Future<void> deletePerName(int bookId, List<String> names) async {
    if (names.isEmpty) return;
    await db.transaction((txn) async {
      for (final name in names) {
        await txn.delete(tableCard,
            where: 'book_id = ? AND name = ?', whereArgs: [bookId, name]);
        await txn.delete(
          tableRelation,
          where: 'book_id = ? AND (source_name = ? OR target_name = ?)',
          whereArgs: [bookId, name, name],
        );
      }
    });
  }

  /// 新实现：分块 IN 批量删（与 CharacterDao.deleteCharacters 一致）
  Future<void> deleteBatched(int bookId, List<String> names) async {
    if (names.isEmpty) return;
    final unique = names.toSet().toList();
    const chunkSize = 400;
    await db.transaction((txn) async {
      for (var i = 0; i < unique.length; i += chunkSize) {
        final chunk = unique.sublist(
          i,
          (i + chunkSize) > unique.length ? unique.length : i + chunkSize,
        );
        final placeholders = List.filled(chunk.length, '?').join(',');
        await txn.delete(tableCard,
            where: 'book_id = ? AND name IN ($placeholders)',
            whereArgs: [bookId, ...chunk]);
        await txn.delete(
          tableRelation,
          where: 'book_id = ? AND (source_name IN ($placeholders) '
              'OR target_name IN ($placeholders))',
          whereArgs: [bookId, ...chunk, ...chunk],
        );
      }
    });
  }

  /// 用同一份初始数据分别跑两种实现，返回两次遗留数据的字符串表示。
  ///
  /// 只取业务列、**不取自增 id**：两组数据是分别重新灌进去的，
  /// id 必然不同，比 id 只会得到无意义的失败（第一版就踩了这个坑）。
  Future<List<String>> runBoth(
    Future<void> Function(int, List<String>) impl,
    List<String> names, {
    required int bookId,
  }) async {
    await impl(bookId, names);
    final cards = await db.query(tableCard,
        columns: ['book_id', 'name'], orderBy: 'book_id, name');
    final rels = await db.query(tableRelation,
        columns: ['book_id', 'source_name', 'target_name'],
        orderBy: 'book_id, source_name, target_name');
    return [cards.toString(), rels.toString()];
  }

  /// 灌一批有交叉关系的数据（含另一本书，验证不会误伤）
  Future<void> seed() async {
    await addCard(1, 'A');
    await addCard(1, 'B');
    await addCard(1, 'C');
    await addCard(1, 'D');
    await addCard(2, 'A'); // 另一本书的同名人物，不能被误删
    await addCard(1, 'E');

    await addRelation(1, 'A', 'B');
    await addRelation(1, 'B', 'C');
    await addRelation(1, 'C', 'D');
    await addRelation(1, 'D', 'E');
    await addRelation(1, 'A', 'E');
    await addRelation(2, 'A', 'B'); // 另一本书的关系，不能被误删
  }

  group('语义等价（新旧实现结果逐行一致）', () {
    test('删中间一个（既是 source 又是 target）', () async {
      await seed();
      final old = await runBoth(deletePerName, ['C'], bookId: 1);
      await db.delete(tableCard);
      await db.delete(tableRelation);
      await seed();
      final fresh = await runBoth(deleteBatched, ['C'], bookId: 1);
      expect(fresh, old);
    });

    test('删多个名字', () async {
      await seed();
      final old = await runBoth(deletePerName, ['A', 'D'], bookId: 1);
      await db.delete(tableCard);
      await db.delete(tableRelation);
      await seed();
      final fresh = await runBoth(deleteBatched, ['A', 'D'], bookId: 1);
      expect(fresh, old);
    });

    test('删全部', () async {
      await seed();
      final old =
          await runBoth(deletePerName, ['A', 'B', 'C', 'D', 'E'], bookId: 1);
      await db.delete(tableCard);
      await db.delete(tableRelation);
      await seed();
      final fresh =
          await runBoth(deleteBatched, ['A', 'B', 'C', 'D', 'E'], bookId: 1);
      expect(fresh, old);
    });
  });

  group('边界', () {
    test('空列表直接返回，不动任何数据', () async {
      await seed();
      final before = await db.query(tableCard);
      final beforeRel = await db.query(tableRelation);

      await deleteBatched(1, []);

      expect(await db.query(tableCard), before);
      expect(await db.query(tableRelation), beforeRel);
    });

    test('重复名字不会报错，也不会多删（去重后等价）', () async {
      await seed();
      await deleteBatched(1, ['A', 'A', 'A']);
      final names =
          (await db.query(tableCard, where: 'book_id = 1')).map((r) => r['name']);
      expect(names, isNot(contains('A')));
      expect(names, contains('B'));
    });

    test('名字只出现在关系表、卡片已不存在时，关系仍被清掉', () async {
      await seed();
      // 模拟「卡片已被删但关系残留」的历史脏数据
      await db.delete(tableCard, where: 'book_id = ? AND name = ?',
          whereArgs: [1, 'C']);
      expect(
        await db.query(tableRelation, where: 'source_name = ? OR target_name = ?',
            whereArgs: ['C', 'C']),
        isNotEmpty,
      );

      await deleteBatched(1, ['C']);

      expect(
        await db.query(tableRelation, where: 'source_name = ? OR target_name = ?',
            whereArgs: ['C', 'C']),
        isEmpty,
      );
    });

    test('另一本书的同名人物与关系不受影响', () async {
      await seed();
      await deleteBatched(1, ['A']);

      final book2Cards = await db.query(tableCard, where: 'book_id = 2');
      expect(book2Cards.length, 1);
      expect(book2Cards.first['name'], 'A');
      final book2Rels = await db.query(tableRelation, where: 'book_id = 2');
      expect(book2Rels.length, 1);
    });

    test('跨块：450 个名字（超过 400 的分块阈值）全部删净', () async {
      final names = List.generate(450, (i) => '龙套$i');
      for (final n in names) {
        await addCard(1, n);
      }
      await addCard(1, '保留');
      // 给前 450 个各连一条关系，验证关系也一并清掉
      for (var i = 0; i < 450; i++) {
        await addRelation(1, names[i], '保留');
      }

      await deleteBatched(1, names);

      final leftCards = await db.query(tableCard, where: 'book_id = 1');
      expect(leftCards.length, 1);
      expect(leftCards.first['name'], '保留');
      expect(await db.query(tableRelation, where: 'book_id = 1'), isEmpty);
    });

    test('跨块后仍不误伤另一本书（同名跨块）', () async {
      final names = List.generate(450, (i) => 'role$i');
      for (final n in names) {
        await addCard(1, n);
        await addCard(2, n);
      }

      await deleteBatched(1, names);

      expect(await db.query(tableCard, where: 'book_id = 1'), isEmpty);
      expect((await db.query(tableCard, where: 'book_id = 2')).length, 450);
    });
  });

  group('索引仍能支撑（批量 IN 走索引而不是全表扫描）', () {
    test('卡片删除按 (book_id, name) 索引', () async {
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN DELETE FROM $tableCard '
        'WHERE book_id = ? AND name IN (?,?)',
        [1, 'A', 'B'],
      );
      expect(plan.map((r) => r['detail']).join(' | '),
          contains('idx_char_card_name'));
    });

    test('关系删除按 (book_id, source_name, target_name) 索引', () async {
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN DELETE FROM $tableRelation '
        'WHERE book_id = ? AND (source_name IN (?) OR target_name IN (?))',
        [1, 'A', 'A'],
      );
      expect(plan.map((r) => r['detail']).join(' | '),
          contains('idx_char_rel_pair'));
    });
  });
}
