// ⚠️ 未运行验证（本环境没有 Dart/Flutter SDK）。
//    路径建议：test/service/import_dedup_test.dart
//
// 覆盖目标：块 ③导入流水线 —— 去重环节（导入 → 入库 → 去重）
//
// 为什么这几条是"一改就静默出错"的关键点（每条对应一个真实可复现的问号）：
//   1) 去重键是 `tb_books.file_md5`，但它**没有唯一约束**（DDL 见 dao/database.dart 的
//      `ALTER TABLE tb_books ADD COLUMN file_md5 TEXT`，没有任何 UNIQUE/INDEX）。
//      ⇒ 重复行在数据层是被允许的，"去重"完全靠应用层自觉。
//   2) 查询是 `WHERE file_md5 = ? LIMIT 1`（base_dao.querySingle 固定 limit:1）**且无 ORDER BY**
//      ⇒ 一旦出现重复 md5，"谁赢"由 SQLite 扫描顺序决定，与 updated_at/阅读进度无关。
//   3) `save()` 只用 `book.id != -1` 决定 INSERT 还是 UPDATE，**且不看受影响行数**
//      ⇒ 目标行不存在时 UPDATE 影响 0 行、不抛异常 = 假成功。
//   4) `MD5Service.calculateFileMd5` 失败返回 **null**，而 saveBook 只在 `if (md5 != null)` 时查重
//      ⇒ 同一文件导入两次 → 两行、md5 都为 NULL，事后无法自动判定重复。
//   5) `""`（空串）不是 null ⇒ 会进入查重分支并被 `= ''` 匹配到任意一本空 md5 的书，
//      与 `getBooksWithoutMd5()` 的 `IS NULL OR = ''` 口径冲突。
//
// ⚠️ 本文件需要 lib/ 侧新增一个**测试注入口**才能跑（本轮不得改 lib/，故当前不可运行）：
//    `DBHelper.debugOverrideDatabase(db)` / `DBHelper.debugResetOverride()`
//    原因：BookDao → BaseDao._database → `DBHelper().database` 单例，若不走注入就会调
//    `initDB()` → path_provider / sqflite_common_ffi 平台分支，测试里拿不到内存库。
//    替代方案（不改源码）：把 `databaseFactory` 全局替换为 FFI 后，DBHelper.initDB() 在
//    'windows'/'ios' 分支下会走 `databaseFactory.openDatabase(...)` —— 但那会真的建文件，
//    且 SjPlatform.type 在测试宿主上不可控，故仍推荐加注入口。
//
// ✅ 本文件已按「数据缺陷补丁 0005 / 0006」更新：断言写的是**修复后应有的行为**。
// 仍保留为 characterization 的两条（file_md5 无唯一约束、md5=='' 串味）是**本批未修**的残留，
// 见 交付说明.md「未做与残留」。
// 等价的可运行证明（Python，已实际跑出结果）：
//   generated/sojiangyue-阶段三测试/tool/import_dedup_harness.py

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/service/md5_service.dart';
import 'package:songjiang_reader/models/book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentDbVersion,
        singleInstance: false,
        onCreate: (d, v) => DBHelper().onUpgradeDatabase(d, 0, v),
      ),
    );
    await DBHelper().ensureSchemaIntegrity(db);
    // BookDao 走 BaseDao → DBHelper().database（单例）。测试里直接把单例指到本内存库，
    // 避免 DBHelper.initDB() 去碰 path_provider。落地时可用一个 @visibleForTesting 的注入口，
    // 或改用 `databaseFactory` 全局注入（见文件末尾说明）。
    DBHelper.debugOverrideDatabase(db);
  });

  tearDown(() async {
    DBHelper.debugResetOverride();
    await db.close();
  });

  group('③ 去重键 file_md5 的结构性事实', () {
    test('file_md5 上没有唯一索引（⇒ 重复行是允许的）', () async {
      final idx = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='tb_books'",
      );
      final hasUnique = idx.any((r) => (r['sql'] as String? ?? '').toUpperCase().contains('UNIQUE'));
      final ddl = (await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='tb_books'",
      )).first['sql'] as String;
      expect(hasUnique, isFalse);
      expect(ddl.toUpperCase(), isNot(contains('UNIQUE')));

      // 后果：同一个 md5 可以落两行
      await db.insert('tb_books', {'title': 'a', 'file_md5': 'MD5-SAME'});
      await db.insert('tb_books', {'title': 'b', 'file_md5': 'MD5-SAME'});
      final n = Sqflite.firstIntValue(
        await db.rawQuery("SELECT COUNT(*) FROM tb_books WHERE file_md5='MD5-SAME'"),
      );
      expect(n, 2, reason: '数据层不阻止重复 —— 修好后这里应该是 1（加 UNIQUE 索引）');
    });

    test('getBookByMd5 = WHERE file_md5=? LIMIT 1 且无 ORDER BY：重复时"谁赢"不稳定', () async {
      final id1 = await db.insert('tb_books', {'title': '先', 'file_md5': 'DUP'});
      await db.insert('tb_books', {'title': '后', 'file_md5': 'DUP'});
      final first = await bookDao.getBookByMd5('DUP');
      expect(first, isNotNull);
      expect(first!.title, '先', reason: '当前落回 rowid 靠前的那条；无 ORDER BY ⇒ 不保证稳定');

      // 删掉返回的那条，同一查询换一条返回 —— 说明选择与"更新时间/阅读进度"无关
      await db.delete('tb_books', where: 'id = ?', whereArgs: [id1]);
      final second = await bookDao.getBookByMd5('DUP');
      expect(second!.title, '后');
      // 正确行为建议：改成 `ORDER BY update_time DESC, id DESC LIMIT 1` 或加唯一约束后不再有二义。
    });
  });

  group('③ save() 的 insert/update 分叉', () {
    test('id == -1 → INSERT；id != -1 → UPDATE（不检查受影响行数）', () async {
      final b = Book(id: -1, title: '新书', filePath: 'file/a', md5: 'M1');
      await bookDao.insertBook(b);
      expect(b.id, greaterThan(0));

      // 命中已有 → 走 UPDATE：保留阅读进度、覆盖定位信息
      await db.update('tb_books', {'last_read_position': 'cfi-99', 'reading_percentage': 42.5},
          where: 'id = ?', whereArgs: [b.id]);
      final existing = (await bookDao.selectBookById(b.id));
      final again = Book(
        id: existing.id,
        title: existing.title,
        filePath: 'file/a-2',
        lastReadPosition: existing.lastReadPosition,
        readingPercentage: existing.readingPercentage,
        md5: 'M1',
      );
      await bookDao.insertBook(again);
      final rows = await bookDao.selectBooks();
      expect(rows.length, 1, reason: '同 md5 不应产生重复行');
      expect(rows.first.lastReadPosition, 'cfi-99', reason: '阅读进度要保住');
      expect(rows.first.filePath, 'file/a-2', reason: '但 file_path 会被换成新副本 → 旧副本成孤儿');
    });

    test('目标行已被删除时 save() 必须抛错（patch 0006，修复前是静默假成功）', () async {
      final b = Book(id: -1, title: '会被删掉', filePath: 'file/x', md5: 'M2');
      await bookDao.insertBook(b);
      await db.delete('tb_books', where: 'id = ?', whereArgs: [b.id]);

      // 用同一个 id 再 save 一次：sqlite 的 UPDATE 影响 0 行且不报错，
      // 所以必须由 BookDao.save() 自己检查受影响行数并抛错（patch 0006）。
      final ghost = Book(id: b.id, title: '幽灵', filePath: 'file/x2', md5: 'M2');
      await expectLater(
        bookDao.insertBook(ghost),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('影响 0 行'))),
      );
      final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tb_books'));
      expect(n, 0);
      // 影响面：`updateBook` 保持**不抛**（只把受影响行数返回出去），
      // 因此 13 处直接调用点（book_detail.dart / epub_player.dart / bookshelf_* …）行为不变。
    });
  });

  group('③ md5 缺失/为空时的去重失效', () {
    test('md5 == null 时改用兜底指纹去重（patch 0005）', () async {
      // 修复前：md5 为 null → saveBook 的 `if (md5 != null)` 跳过查重 → 同一个文件落 2 行。
      // 修复后：MD5Service.dedupKeyFor() 退到 `size:<字节数>:<sha1(首尾各 32KB)>`，
      //         于是"同一个文件导入两次"仍然只落 1 行。
      final dir = await Directory.systemTemp.createTemp('sj_dedup_');
      try {
        final f1 = File(p.join(dir.path, 'a.epub'))..writeAsBytesSync(List.filled(9000, 7));
        final f2 = File(p.join(dir.path, 'a_again.epub'))..writeAsBytesSync(List.filled(9000, 7));
        final k1 = await MD5Service.dedupKeyFor(f1.path);
        final k2 = await MD5Service.dedupKeyFor(f2.path);
        expect(k1, isNotNull, reason: '即使读不出 md5，也必须给出一个可用的去重键');
        expect(k1, startsWith('size:'), reason: '兜底键带 size: 前缀，不会与 32 位十六进制 md5 混淆');
        expect(k2, k1, reason: '同一内容的两个副本必须得到同一个键');

        // 用真实 DAO 走一遍落库：第二次应命中已有行
        final a = Book(id: -1, title: '同书', filePath: f1.path, md5: k1);
        await bookDao.insertBook(a);
        final hit = await bookDao.getBookByMd5(k1!);
        expect(hit, isNotNull);
        final b = Book(id: hit!.id, title: hit.title, filePath: f2.path, md5: k1);
        await bookDao.insertBook(b);
        final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tb_books'));
        expect(n, 1, reason: 'md5 缺失路径下也必须只落 1 行（修复前实测 2 行）');
      } finally {
        dir.deleteSync(recursive: true);
      }
      // 残留（本批未修）：calculateFileMd5 失败时的 SjLog 只是一行 warning，UI 不提示。
    });

    test("md5 == '' 会被当成「同一本」，与 getBooksWithoutMd5 口径冲突", () async {
      await db.insert('tb_books', {'title': 'z', 'file_md5': ''});
      final hit = await bookDao.getBookByMd5('');
      expect(hit, isNotNull, reason: "空串会被 `= ''` 命中"); // ignore: unnecessary_string_quotes
      final without = await bookDao.getBooksWithoutMd5();
      expect(without.length, 1, reason: '同一行在 getBooksWithoutMd5 里也被算作"没有 md5"');
      // 两个口径互相矛盾：一个当"同一本"，一个当"缺失"。修好后建议统一（查重前把 '' 归一成 null）。
    });
  });
}
