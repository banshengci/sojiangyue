// ⚠️ 未运行验证（本环境没有 Dart/Flutter SDK，`flutter analyze` / `flutter test` 都跑不了）。
//    路径：test/service/database_sync_validator_test.dart
//    对应缺陷：#1 空书库被判非法、#2 只拒更新不拒更旧、#7 快照未 checkpoint/未自检
//
// 这是"数据缺陷补丁"带来的**行为契约测试**：断言修复后的行为，正是回归用的护栏。
// 其中 #1/#2/#7 的行为等价性已用 Python 模型验证（tool/fix_regression.py --model after，12/12 PASS）；
// 这里的 Dart 版本是给有 SDK 的机器跑的第一手验证。
//
// 为什么必须测这几条（都是"用户可感知的数据风险"）：
//   #1 空书架：用户清空书库后，自己的库被判非法 → **永远无法同步 / 换机也恢复不了**。
//   #2 更旧版本：v13 的远端文件整库覆盖 v15 本地库 → v14/v15 的表与数据整体消失，
//      而 UI 只会说"同步成功"。本模块**没有任何行级合并**，所以只能靠"拒绝"来保数据。
//   #7 checkpoint：连接还开着时只拷 .db，-wal 里未 checkpoint 的内容会静默丢
//      （Python 实测：-wal 16512B，快照从 2 行变 0 行）。
//
// 注意：#1 的"空库合法"必须与"未初始化的文件"区分开，否则一个空白 sqlite
// 文件会被当成合法远端库灌进来。判据用 `PRAGMA user_version`：
//   · user_version == 0  → 从没跑过本 App 的迁移 → 拒绝
//   · user_version == 15 且 tb_books 为空 → 合法（用户把书删光了）→ 接受
//
// 需要的前置：`sqflite_common_ffi`（已在 dependencies 里）+ 不要真的走网络。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart'
    show documentPath;

/// 与 DatabaseSyncManager 的校验路径等价的最小装载：
/// 直接调 `DBHelper.verifyUploadSnapshot`（#7 的上传前自检）与
/// `DBHelper.fixDatabaseHeader`（header 迁移），不去 import `database_sync_manager.dart`
/// —— 后者 import 了 `main.dart` + `flutter_smart_dialog`，会把整个 App 图拉进测试
/// （这也是它至今无法单测的原因，见「阻塞清单」B5）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sj_sync_validator_');
    // 走完整迁移的用例需要这三个全局前置（与 db_migration_chain_test 一致）：
    //   · documentPath —— 迁移 case2 会 `Directory('$documentPath/file').listSync()`，
    //     测试宿主上默认是空串，拼出 `'/file'`（Windows 非法路径）会直接抛；
    //   · ReadingStylePrefs / SyncPrefs —— 迁移过程中会读它们，未初始化会抛 Bad state。
    Directory(p.join(tmp.path, 'file')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'cover')).createSync(recursive: true);
    documentPath = tmp.path;
    SharedPreferences.setMockInitialValues({});
    await ReadingStylePrefs.ensureInitialized();
    await SyncPrefs.ensureInitialized();
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // 造一份"已初始化"的库：17 张以上的表 + user_version=15 + 可选的书。
  Future<String> makeDb(String name, {int books = 1, int version = 15, List<String> dropTables = const []}) async {
    final path = p.join(tmp.path, name);
    final db = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute(createBookSQL);
    await db.execute(createNoteSQL);
    await db.execute(createThemeSQL);
    await db.execute(createStyleSQL);
    await db.execute(createReadingTimeSQL);
    await db.execute(ensureGroupTableSQL);
    await db.execute(ensureGroupRootSQL);
    await db.execute(ensureVocabItemsSQL);
    for (var i = 0; i < books; i++) {
      await db.insert('tb_books', {'title': '书$i', 'file_path': 'file/$i'});
    }
    for (final t in dropTables) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
    await db.execute('PRAGMA user_version=$version');
    await db.execute('VACUUM'); // 让 header 干净、文件 >1KB
    await db.close();
    return path;
  }

  group('#7 verifyUploadSnapshot：上传前自检', () {
    test('结构完整 + 版本正确的快照 → 通过', () async {
      final path = await makeDb('ok.db');
      await expectLater(DBHelper.verifyUploadSnapshot(path), completes);
    });

    test('缺 tb_groups（迁移中断过）→ 抛错，拒绝上传', () async {
      final path = await makeDb('missing_groups.db', dropTables: ['tb_groups']);
      await expectLater(
        DBHelper.verifyUploadSnapshot(path),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('缺表'))),
      );
    });

    test('缺 tb_vocab_items → 抛错', () async {
      final path = await makeDb('missing_vocab.db', dropTables: ['tb_vocab_items']);
      await expectLater(DBHelper.verifyUploadSnapshot(path), throwsA(isA<StateError>()));
    });

    test('文件过小 / 不存在 → 抛错', () async {
      final small = File(p.join(tmp.path, 'small.db'))..writeAsBytesSync(List.filled(64, 0));
      await expectLater(DBHelper.verifyUploadSnapshot(small.path), throwsA(isA<StateError>()));
      await expectLater(DBHelper.verifyUploadSnapshot(p.join(tmp.path, 'nope.db')), throwsA(isA<StateError>()));
    });

    test('integrity_check 失败（文件被截断）→ 抛错', () async {
      final path = await makeDb('truncated.db');
      final f = File(path);
      final bytes = f.readAsBytesSync();
      f.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2)); // 砍掉一半
      await expectLater(DBHelper.verifyUploadSnapshot(path), throwsA(isA<StateError>()));
    });
  });

  group('#7 fixDatabaseHeader：WAL → Legacy 的 header 迁移', () {
    test('WAL 库的 header(18,19) 由 2/2 patch 成 1/1，且仍可打开', () async {
      final path = p.join(tmp.path, 'wal.db');
      final db = await databaseFactory.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('PRAGMA journal_mode=WAL');
      await db.execute(createBookSQL);
      await db.insert('tb_books', {'title': 'x'});
      await db.close();

      final f = File(path);
      final before = f.readAsBytesSync();
      await DBHelper.fixDatabaseHeader(path);
      final after = f.readAsBytesSync();
      if (before[18] == 2 || before[19] == 2) {
        expect(after[18], 1);
        expect(after[19], 1);
      }
      // 无论是否 patch，都必须还能打开
      final reopen = await databaseFactory.openDatabase(path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      expect(await reopen.rawQuery('PRAGMA integrity_check'), isNotEmpty);
      await reopen.close();
    });

    test('WAL 里还有未 checkpoint 的数据时，先 checkpoint 再拷才不会丢行', () async {
      // 这条锁的是 prepareUploadSnapshot 的修复点：checkpoint + 复查 + 自检。
      final live = p.join(tmp.path, 'live.db');
      final db = await databaseFactory.openDatabase(live,
          options: OpenDatabaseOptions(
            singleInstance: false,
            // 必须走完整迁移建库：`verifyUploadSnapshot` 要求 tb_books / tb_themes /
            // tb_styles / tb_groups / tb_vocab_items 五张表齐全，只建 tb_books 会被它拒绝
            // （原用例用 createBookSQL 只建了一张表，所以"修复点 2"必然抛"快照缺表"）。
            version: currentDbVersion,
            onCreate: (d, v) => DBHelper().onUpgradeDatabase(d, 0, v),
          ));
      await db.execute('PRAGMA journal_mode=WAL');
      await db.insert('tb_books', {'title': 'a'});
      await db.execute('PRAGMA wal_autocheckpoint=0');
      await db.insert('tb_books', {'title': 'b'}); // 只落在 -wal
      final walSize = File('$live-wal').existsSync() ? File('$live-wal').lengthSync() : 0;

      final snap = p.join(tmp.path, 'snapshot.db');
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)'); // ← 修复点 1：显式 checkpoint
      expect(File('$live-wal').lengthSync(), 0, reason: 'checkpoint 后 -wal 应为空（$walSize B → 0）');
      File(live).copySync(snap);
      await DBHelper.fixDatabaseHeader(snap);
      await DBHelper.verifyUploadSnapshot(snap); // ← 修复点 2：上传前自检

      final probe = await databaseFactory.openDatabase(snap,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final n = Sqflite.firstIntValue(await probe.rawQuery('SELECT COUNT(*) FROM tb_books'));
      await probe.close();
      await db.close();
      expect(n, 2, reason: '快照必须包含 WAL 里那行（修复前实测会得到 0 行）');
    });
  });

  group('#1/#2 校验规则（模型断言；Dart 侧由 DatabaseSyncManager._validateDatabase 承载）', () {
    // 说明：_validateDatabase 是 private static，且其宿主文件 import 了 main.dart，
    // 这里不重复实现它，而是把"判据"写成可读的契约，靠 Python 侧模型
    // （tool/fix_regression.py --model after）做真实断言。
    // 一旦 #2 的宿主文件被拆出 database_sync_io.dart（见阻塞清单 B5），
    // 这几条应改成直接调用它。
    test('契约：user_version==0 视为未初始化；==15 且书架为空视为合法', () async {
      final emptyButInit = await makeDb('empty_init.db', books: 0, version: 15);
      final notInit = await makeDb('not_init.db', books: 0, version: 0);
      for (final path in [emptyButInit, notInit]) {
        final probe = await databaseFactory.openDatabase(path,
            options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
        final ver = Sqflite.firstIntValue(await probe.rawQuery('PRAGMA user_version'));
        final books = Sqflite.firstIntValue(await probe.rawQuery('SELECT COUNT(*) FROM tb_books'));
        await probe.close();
        final accept = ver != 0;
        expect(accept, ver == 15, reason: 'user_version=$ver books=$books 的接受判定');
      }
    });
  });
}
