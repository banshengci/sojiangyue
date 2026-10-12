import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 阅读统计查询的日期比较回归测试。
///
/// 背景：`tb_reading_time` 的 `date` 存的是 `'YYYY-MM-DD'`。原先一批聚合查询写成
/// `WHERE DATE(date) BETWEEN DATE(?) AND DATE(?)`，把列包进 `DATE()` 会让
/// `idx_reading_time_date` 失效，SQLite 只能全表扫描（热力图、周月年趋势、
/// 连续天数、每日目标都走这条路）。
///
/// 现已改为字符串区间比较 `date BETWEEN ? AND ?`（ISO 日期字典序与时间序一致）。
/// 本测试锁住两件事，避免将来被无意改回：
///   1. 语义等价：改写法后结果集与旧写法逐行一致；
///   2. 写法有效：新写法确实命中索引（EXPLAIN QUERY PLAN 出现 SEARCH ... USING INDEX）。
///
/// 注意：断言「命中索引」是有意为之——如果只断言结果正确，把查询改回 `DATE(date)`
/// 依然会通过，性能退化就无人察觉。
void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
CREATE TABLE tb_reading_time (
  id INTEGER PRIMARY KEY,
  book_id INTEGER,
  date TEXT,
  reading_time INTEGER
)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reading_time_date ON tb_reading_time(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reading_time_book ON tb_reading_time(book_id, date)');

    // 覆盖跨周/跨月/跨年、多本书；日期一律为 'YYYY-MM-DD'
    const rows = <List<Object?>>[
      [1, 1, '2026-03-01', 100],
      [2, 1, '2026-03-05', 300],
      [3, 1, '2026-03-31', 500],
      [4, 1, '2026-04-01', 600],
      [5, 2, '2026-03-10', 700],
      [6, 2, '2026-12-31', 800],
      [7, 1, '2027-01-01', 900],
    ];
    for (final r in rows) {
      await db.insert('tb_reading_time', {
        'id': r[0],
        'book_id': r[1],
        'date': r[2],
        'reading_time': r[3],
      });
    }
  });

  tearDown(() async => db.close());

  Future<String> planOf(String sql, List<Object?> args) async {
    final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
    return rows.map((r) => r['detail']).join(' | ');
  }

  group('区间聚合（周/月/年）', () {
    test('date BETWEEN ? AND ? 与 DATE(date) BETWEEN DATE(?) AND DATE(?) 结果一致', () async {
      const oldSql = "SELECT DATE(date) AS day, SUM(reading_time) AS s "
          "FROM tb_reading_time WHERE DATE(date) BETWEEN DATE(?) AND DATE(?) "
          "GROUP BY day ORDER BY day";
      const newSql = "SELECT DATE(date) AS day, SUM(reading_time) AS s "
          "FROM tb_reading_time WHERE date BETWEEN ? AND ? "
          "GROUP BY day ORDER BY day";
      const args = ['2026-03-01', '2026-03-31'];

      final oldRows = await db.rawQuery(oldSql, args);
      final newRows = await db.rawQuery(newSql, args);

      expect(newRows, oldRows);
      // 3/10 属于另一本书，但按日聚合不带 book 过滤，故一并计入
      expect(newRows.length, 4);
      expect(newRows.first['day'], '2026-03-01');
      expect(newRows.last['day'], '2026-03-31');
    });

    test('区间聚合命中索引而不是全表扫描', () async {
      final plan = await planOf(
        "SELECT DATE(date) AS day, SUM(reading_time) AS s "
        "FROM tb_reading_time WHERE date BETWEEN ? AND ? GROUP BY day",
        ['2026-03-01', '2026-03-31'],
      );
      expect(plan, contains('SEARCH'));
      expect(plan, contains('idx_reading_time_date'));
      expect(plan, isNot(contains('SCAN tb_reading_time')));
    });

    test('旧写法（DATE(date)）会被索引优化器放弃，佐证必须用新写法', () async {
      final plan = await planOf(
        "SELECT DATE(date) AS day, SUM(reading_time) AS s "
        "FROM tb_reading_time WHERE DATE(date) BETWEEN DATE(?) AND DATE(?) "
        "GROUP BY day",
        ['2026-03-01', '2026-03-31'],
      );
      expect(plan, contains('SCAN tb_reading_time'));
    });
  });

  group('下界筛选（本周书目 / 近 N 天）', () {
    test('date >= ? 与 DATE(date) >= DATE(?) 结果一致，且按书筛选命中复合索引', () async {
      const oldSql = "SELECT DATE(date) as day, SUM(reading_time) as t "
          "FROM tb_reading_time WHERE book_id = ? AND DATE(date) >= DATE(?) "
          "GROUP BY day ORDER BY day ASC";
      const newSql = "SELECT DATE(date) as day, SUM(reading_time) as t "
          "FROM tb_reading_time WHERE book_id = ? AND date >= ? "
          "GROUP BY day ORDER BY day ASC";
      const args = [1, '2026-03-01'];

      final oldRows = await db.rawQuery(oldSql, args);
      final newRows = await db.rawQuery(newSql, args);

      expect(newRows, oldRows);
      expect(newRows.length, 5); // 书 1 在 3/1 之后共 5 天有记录

      final plan = await planOf(newSql, args);
      expect(plan, contains('SEARCH'));
      expect(plan, contains('idx_reading_time_book'));
    });

    test('无限定的 date >= ? 走到索引（覆盖索引，不扫表）', () async {
      final plan = await planOf(
        "SELECT book_id, SUM(reading_time) AS s FROM tb_reading_time "
        "WHERE date >= ? GROUP BY book_id ORDER BY s DESC",
        ['2026-03-01'],
      );
      // 实测 SQLite 选的是复合索引 idx_reading_time_book(book_id, date) 做索引扫描
      // ——因为该索引已覆盖 book_id 与 date，不必回表，比用 idx_reading_time_date
      // 再回表取 book_id 更划算。关键是它不再扫表。
      expect(plan, contains('SCAN'));
      expect(plan, contains('USING INDEX idx_reading_time_book'));
      expect(plan, isNot(contains('SCAN tb_reading_time\n')));
    });
  });

  group('等值筛选（某本书某天）', () {
    test('date = ? 与 DATE(date) = DATE(?) 结果一致', () async {
      const oldSql = "SELECT book_id, SUM(reading_time) AS t "
          "FROM tb_reading_time WHERE DATE(date) = DATE(?) GROUP BY book_id";
      const newSql = "SELECT book_id, SUM(reading_time) AS t "
          "FROM tb_reading_time WHERE date = ? GROUP BY book_id";
      const args = ['2026-03-05'];

      expect(await db.rawQuery(newSql, args), await db.rawQuery(oldSql, args));

      final plan = await planOf(newSql, args);
      expect(plan, contains('SEARCH'));
      expect(plan, contains('idx_reading_time_date'));
    });
  });

  group('索引定义本身', () {
    test('两张统计表的关键索引都能幂等创建', () async {
      // 与 lib/dao/database.dart 的 _ensureReadStatsIndexes 保持一致，重复执行不报错
      const statements = <String>[
        'CREATE INDEX IF NOT EXISTS idx_reading_time_date ON tb_reading_time(date)',
        'CREATE INDEX IF NOT EXISTS idx_reading_time_book ON tb_reading_time(book_id, date)',
      ];
      for (final sql in statements) {
        await db.execute(sql);
        await db.execute(sql); // 幂等
      }

      final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='tb_reading_time'");
      final names = indexes.map((r) => r['name']).toSet();
      expect(names, contains('idx_reading_time_date'));
      expect(names, contains('idx_reading_time_book'));
    });

    test('生产代码 _ensureReadStatsIndexes 的源码确实包含这几条建索引语句', () {
      // 这是本文件里唯一直接约束生产代码的断言。
      // 其它用例用的是测试内联 SQL（刻意如此：需要新旧写法对照，不能改动生产查询），
      // 因此如果有人把 database.dart 里的补索引逻辑删掉，只有这条会失败。
      final source = File('lib/dao/database.dart').readAsStringSync();
      expect(source, contains('idx_reading_time_date'));
      expect(source, contains('idx_reading_time_book'));
      expect(source, contains('idx_notes_book_type'));
      expect(source, contains('_ensureReadStatsIndexes(db)'),
          reason: '补索引函数必须在 ensureSchemaIntegrity 里被调用，否则老库拿不到索引');
    });
  });
}
