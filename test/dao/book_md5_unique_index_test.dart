// ⚠️ 未运行验证（本环境没有 Dart/Flutter SDK，`flutter analyze` / `flutter test` 都跑不了）。
//    路径：test/dao/book_md5_unique_index_test.dart
//    对应补丁：#0010（无损 md5 去重 + 唯一索引）、#0011（`''` 语义统一为「缺失」）
//
// 🔴 本文件的第一条断言是**红线**：不允许删除或合并用户的书籍行。
//    无损方案的原理（也是它成立的前提）：
//      · SQLite 的唯一索引把 **NULL 视为互不相等** ⇒ 多行 `file_md5 IS NULL` 可以共存；
//      · `''`（空串）不是 NULL，会互相冲突 ⇒ 必须先统一成 NULL；
//      · 于是"同 md5 只留一行持有 md5，其余置 NULL"就能在**零删行、零改其它列**的前提下建索引。
//    `idx_books_file_md5_unique` 是**部分索引**（`WHERE file_md5 IS NOT NULL AND file_md5 <> ''`），
//    把这条语义写进 schema。
//
// 为什么这几条是"一改就静默出错"的关键点：
//   1) 去重逻辑写错（比如误用 `DELETE`、或把保留者选成"id 最小"）会**静默改变用户的阅读进度归属**；
//   2) 漏了 `''` → 建索引直接失败 → 自愈每次打开都报 severe，且索引永远建不起来；
//   3) 唯一索引加上之后，`batchCalculateMd5` 回填会撞约束 —— 必须用
//      `ConflictAlgorithm.ignore` 降级成"不写入、不抛"，否则整批回填中途炸掉；
//   4) `''` 语义不统一时，`getBookByMd5('')` 会命中"另一本"空 md5 的书（假重复）。

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/models/book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  /// 造一个"老库"：完整迁移 + 历史重复数据（`''` / NULL / 3 行同 md5）。
  Future<void> seedLegacy() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentDbVersion,
        singleInstance: false,
        onCreate: (d, v) => DBHelper().onUpgradeDatabase(d, 0, v),
      ),
    );
    DBHelper.debugOverrideDatabase(db, allow: true); // #0008 的测试注入口
    final rows = <List<Object?>>[
      ['重复-旧', '2025-11-02T10:00:00', 'MD5-DUP', 'file/dup-1.epub'],
      ['重复-中', '2026-03-15T09:30:00', 'MD5-DUP', 'file/dup-2.epub'],
      ['重复-新', '2026-09-01T20:11:00', 'MD5-DUP', 'file/dup-3.epub'],
      ['唯一书', '2026-01-01T00:00:00', 'MD5-ONLY', 'file/only.epub'],
      ['空串A', '2026-01-01T00:00:00', '', 'file/a.epub'],
      ['空串B', '2026-01-01T00:00:00', '', 'file/b.epub'],
      ['无md5', '2026-01-01T00:00:00', null, 'file/c.epub'],
    ];
    for (final r in rows) {
      await db.insert('tb_books', {
        'title': r[0], 'update_time': r[1], 'file_md5': r[2], 'file_path': r[3],
        'cover_path': '', 'is_deleted': 0, 'reading_percentage': 0.0,
      });
    }
    // 注意：这里**故意不建唯一索引**，模拟"老库还没跑过自愈"。
  }

  setUp(seedLegacy);
  tearDown(() async {
    DBHelper.debugResetOverride();
    await db.close();
  });

  const cols = 'id,title,cover_path,file_path,last_read_position,reading_percentage,'
      'author,is_deleted,description,create_time,update_time';

  group('#0010 零删行（红线）', () {
    test('自愈前后：行数与"除 file_md5 外所有列"逐字节一致', () async {
      final before = await db.rawQuery('SELECT $cols FROM tb_books ORDER BY id');
      await DBHelper().ensureSchemaIntegrity(db);
      final after = await db.rawQuery('SELECT $cols FROM tb_books ORDER BY id');
      expect(after.length, before.length, reason: '不允许删除任何书籍行');
      expect(after.toString(), before.toString(), reason: '不允许改动除 file_md5 之外的任何列');
    });

    test('被清空的是"同组里 update_time 较旧"的行，md5 留给最新的那本', () async {
      await DBHelper().ensureSchemaIntegrity(db);
      final keeper = await db.rawQuery("SELECT id FROM tb_books WHERE file_md5 = 'MD5-DUP'");
      expect(keeper.length, 1);
      expect(keeper.first['id'], 3, reason: 'id=3 是「重复-新」，update_time 最新');
      final cleared = await db.rawQuery(
          "SELECT id FROM tb_books WHERE id IN (1, 2) AND file_md5 IS NULL ORDER BY id");
      expect(cleared.length, 2);
    });

    test('审计表记录了 book_id / old_md5 / kept_book_id / reason（可人工还原）', () async {
      await DBHelper().ensureSchemaIntegrity(db);
      final audit = await db.rawQuery(
          'SELECT book_id, old_md5, kept_book_id, reason FROM tb_book_md5_dedup_audit ORDER BY id');
      expect(audit.length, 4, reason: '2 行重复被释放 + 2 行空串被规范化');
      final dup = audit.where((r) => r['reason'] == 'duplicate_file_md5_released').toList();
      expect(dup.length, 2);
      for (final r in dup) {
        expect(r['old_md5'], 'MD5-DUP');
        expect(r['kept_book_id'], 3);
      }
      final empty = audit.where((r) => r['reason'] == 'empty_string_normalized_to_null').toList();
      expect(empty.length, 2);
    });
  });

  group('#0010 唯一索引', () {
    test('自愈后部分唯一索引存在，且 WHERE 子句写明语义', () async {
      await DBHelper().ensureSchemaIntegrity(db);
      final row = await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_books_file_md5_unique'");
      expect(row.length, 1);
      final sql = (row.first['sql'] as String).toUpperCase();
      expect(sql, contains('UNIQUE'));
      expect(sql, contains("FILE_MD5 IS NOT NULL"));
    });

    test('重复 md5 被拒；多行 NULL 可共存（无损方案的前提）', () async {
      await DBHelper().ensureSchemaIntegrity(db);
      // 多行 NULL 可以共存 —— 这是"无损"能成立的根本原因
      await db.insert('tb_books', {'title': '再插一本无 md5', 'file_md5': null});
      await db.insert('tb_books', {'title': '又插一本无 md5', 'file_md5': null});

      await expectLater(
        db.insert('tb_books', {'title': '重复导入', 'file_md5': 'MD5-ONLY'}),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('自愈可重复执行：幂等（数据/审计都不再变）', () async {
      await DBHelper().ensureSchemaIntegrity(db);
      final rows1 = await db.rawQuery('SELECT id,file_md5 FROM tb_books ORDER BY id');
      final audit1 = await db.rawQuery('SELECT COUNT(*) c FROM tb_book_md5_dedup_audit');
      await DBHelper().ensureSchemaIntegrity(db);
      await DBHelper().ensureSchemaIntegrity(db);
      final rows2 = await db.rawQuery('SELECT id,file_md5 FROM tb_books ORDER BY id');
      final audit2 = await db.rawQuery('SELECT COUNT(*) c FROM tb_book_md5_dedup_audit');
      expect(rows2.toString(), rows1.toString());
      expect(audit2.first['c'], audit1.first['c']);
    });

    test('回填撞唯一约束时只跳过该行（updateBookMd5 返回 0，不抛）', () async {
      await DBHelper().ensureSchemaIntegrity(db);
      final affected = await bookDao.updateBookMd5(1, 'MD5-ONLY'); // 该 md5 已属于 id=4
      expect(affected, 0, reason: 'ignore 语义：冲突行不写入');
      final row = await db.rawQuery('SELECT file_md5 FROM tb_books WHERE id = 1');
      expect(row.first['file_md5'], isNull, reason: '原值保持不动');
    });
  });

  group('#0011 `\"\"` 语义统一为「缺失」', () {
    test('空串 = 缺失：getBookByMd5(\"\") 返回 null，不再命中别的书', () async {
      // 造一本 `file_md5 = ''` 的行（模拟"迁移还没跑"的中间状态）
      await db.insert('tb_books', {'title': '空串书', 'file_md5': ''});
      expect(await bookDao.getBookByMd5(''), isNull);
      expect(await bookDao.getBookByMd5('   '), isNull);
      // 而非空 md5 照常命中
      expect((await bookDao.getBookByMd5('MD5-ONLY'))?.title, '唯一书');
    });

    test('getBooksWithoutMd5 与 getBookByMd5 口径一致', () async {
      await db.insert('tb_books', {'title': '空串书', 'file_md5': ''});
      final without = await bookDao.getBooksWithoutMd5();
      expect(without.any((b) => b.title == '空串书'), isTrue, reason: '空串算"没有 md5"');
      expect(await bookDao.getBookByMd5(''), isNull, reason: '同一行不能又被当成"就是这本书"');
    });

    test('updateBookMd5 拒绝写入空串（返回 0，库里的值不变）', () async {
      await db.insert('tb_books', {'title': '有 md5 的书', 'file_md5': 'MD5-KEEP'});
      final id = Sqflite.firstIntValue(
          await db.rawQuery("SELECT id FROM tb_books WHERE file_md5 = 'MD5-KEEP'"));
      expect(await bookDao.updateBookMd5(id!, ''), 0);
      expect(await bookDao.updateBookMd5(id, '   '), 0);
      final row = await db.rawQuery('SELECT file_md5 FROM tb_books WHERE id = ?', [id]);
      expect(row.first['file_md5'], 'MD5-KEEP');
    });
  });
}
