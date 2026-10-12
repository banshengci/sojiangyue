import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `selectRandomNote()` 的回归测试。
///
/// 原实现是 `ORDER BY RANDOM() LIMIT 1`，SQLite 会把全部命中行取出来、
/// 逐行算随机数再排序（EXPLAIN 里的 `USE TEMP B-TREE FOR ORDER BY`）。
/// 现改为「随机取一个 id 下界 + 取第一条 id >= 下界的命中行」，
/// 目的是不再随笔记量线性变慢。本测试锁住改写后的行为：
///   1. 只返回批注类型（highlight / underline / bookmark），不含书评；
///   2. 空表 / 只有书评时返回 null；
///   3. 只有一条时总能取到它（含下界恰好等于 minId 的边界）；
///   4. 多次调用能覆盖到不止一行（确认不是永远返回同一行）；
///   5. 查询计划不含 `TEMP B-TREE FOR ORDER BY`。
///
/// 这里直接复刻生产 SQL（与 lib/dao/book_note.dart 保持一致），
/// 因为该 DAO 依赖全局 DBHelper，无法在纯测试里初始化。
void main() {
  sqfliteFfiInit();

  const typeFilter = "type IN ('highlight', 'underline', 'bookmark')";
  const minMaxSql =
      "SELECT MIN(id) AS min_id, MAX(id) AS max_id FROM tb_notes WHERE $typeFilter";
  const hitSql =
      "SELECT * FROM tb_notes WHERE $typeFilter AND id >= ? LIMIT 1";
  const fallbackSql =
      "SELECT * FROM tb_notes WHERE $typeFilter ORDER BY id LIMIT 1";

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
CREATE TABLE tb_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER, content TEXT, cfi TEXT, chapter TEXT,
  type TEXT, color TEXT, create_time TEXT, update_time TEXT
)''');
  });

  tearDown(() async => db.close());

  Future<void> insertNote(int bookId, String type) async {
    await db.insert('tb_notes', {
      'book_id': bookId,
      'content': 'c-$bookId-$type',
      'type': type,
    });
  }

  /// 复刻生产逻辑，返回取到的行
  Future<Map<String, Object?>?> pickRandom(int randomSeedValue) async {
    final range = await db.rawQuery(minMaxSql);
    final minId = range.first['min_id'] as int?;
    final maxId = range.first['max_id'] as int?;
    if (minId == null || maxId == null) return null;

    final startId = minId + (randomSeedValue % (maxId - minId + 1));
    final hit = await db.rawQuery(hitSql, [startId]);
    if (hit.isNotEmpty) return hit.first;
    final fallback = await db.rawQuery(fallbackSql);
    return fallback.isEmpty ? null : fallback.first;
  }

  group('空与边界', () {
    test('空表返回 null', () async {
      expect(await db.rawQuery(minMaxSql), isNotEmpty);
      expect((await db.rawQuery(minMaxSql)).first['min_id'], isNull);
      expect(await pickRandom(0), isNull);
    });

    test('只有书评（非批注类型）时返回 null', () async {
      await insertNote(1, 'review');
      await insertNote(1, 'review');
      expect(await pickRandom(0), isNull);
    });

    test('只有一条批注时，任何下界都能回绕取到它', () async {
      await insertNote(1, 'highlight');
      for (var seed = 0; seed < 5; seed++) {
        final row = await pickRandom(seed);
        expect(row, isNotNull, reason: 'seed=$seed');
        expect(row!['type'], 'highlight');
      }
    });

    test('下界恰好等于 minId 时不会漏掉第一条', () async {
      await insertNote(1, 'highlight'); // id = 1
      await insertNote(1, 'underline'); // id = 2
      final row = await pickRandom(0); // 下界 = minId
      expect(row, isNotNull);
      expect(row!['id'], 1);
    });
  });

  group('过滤正确性', () {
    test('永远不返回书评类型', () async {
      await insertNote(1, 'highlight');
      await insertNote(1, 'review');
      await insertNote(1, 'bookmark');
      await insertNote(1, 'review');
      await insertNote(1, 'underline');

      for (var seed = 0; seed < 40; seed++) {
        final row = await pickRandom(seed);
        expect(row, isNotNull, reason: 'seed=$seed');
        expect(row!['type'], isNot('review'), reason: 'seed=$seed');
      }
    });

    test('多次调用能覆盖到多行，而不是恒定一行', () async {
      for (var i = 0; i < 30; i++) {
        await insertNote((i % 3) + 1, 'highlight');
      }
      final seen = <Object?>{};
      for (var seed = 0; seed < 30; seed++) {
        final row = await pickRandom(seed);
        if (row != null) seen.add(row['id']);
      }
      expect(seen.length, greaterThan(1));
    });
  });

  group('性能特征', () {
    test('改写后的查询不含 TEMP B-TREE FOR ORDER BY', () async {
      for (var i = 0; i < 200; i++) {
        await insertNote((i % 5) + 1, i % 7 == 0 ? 'review' : 'highlight');
      }
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_book_type '
          'ON tb_notes(book_id, type)');

      Future<String> planOf(String sql, [List<Object?>? args]) async {
        final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
        return rows.map((r) => r['detail']).join(' | ');
      }

      // 新写法：不该出现排序用的临时 B 树
      final rangePlan = await planOf(minMaxSql);
      final hitPlan = await planOf(hitSql, [100]);
      expect(rangePlan, isNot(contains('TEMP B-TREE')));
      expect(hitPlan, isNot(contains('TEMP B-TREE')));
      expect(hitPlan, isNot(contains('RANDOM')));

      // 旧写法确实会引入临时 B 树——这是本次改写的动机，留作对照
      final oldPlan = await planOf(
          "SELECT * FROM tb_notes WHERE $typeFilter ORDER BY RANDOM() LIMIT 1");
      expect(oldPlan, contains('TEMP B-TREE FOR ORDER BY'));
    });
  });
}
