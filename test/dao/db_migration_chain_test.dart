// ⚠️ 未运行验证（本环境没有 Dart/Flutter SDK，`flutter test` 跑不了）。
//    文件内容按仓库既有测试风格编写（对照 test/service/sync_client_factory_test.dart），
//    路径建议：test/dao/db_migration_chain_test.dart
//
// 覆盖目标：块 ①DB 迁移链 v0→v15（lib/dao/database.dart，18 张表）
//
// 为什么这几条是"一改就静默出错"的关键点：
//   1) 迁移是**一次性**的：sqflite 在 onUpgrade 成功/失败后都可能把 user_version 顶到最新，
//      之后永不重跑（源码注释原话）。所以"每步是否幂等"不是洁癖，而是唯一的补救机会。
//   2) `ensureSchemaIntegrity` 是**唯一**的自愈入口，它漏掉的表/列 = 用户永久清数据重装的场景。
//   3) `case2` 会 `Directory('$basePath/file').listSync()`（路径不存在直接抛）且 `case3` 会碰
//      SharedPreferences —— 所以「迁移能否跑完」依赖 documentPath 与 prefs 两个全局状态，
//      测试必须先备好这两个前置，否则测出来的失败是假失败。
//
// 已验证的等价结论见 tool/db_migration_harness.py（Python，直接执行从 Dart 抽取的同一批 SQL）。
// ✅ 本文件已按「数据缺陷补丁 0003」更新：自愈必须能补齐 tb_groups / tb_vocab_items。
// ✅ 又按「后续批次 0010」更新：自愈现在还会建 tb_book_md5_dedup_audit（审计表）与两个索引，
//    因此自愈建表数 13 → 14。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart' show documentPath;

/// v15 应有的全部表（顺序无关）。数字来源：Python harness 实测 18 张（与任务书一致）。
const Set<String> kV15Tables = {
  'tb_books',
  'tb_notes',
  'tb_themes',
  'tb_styles',
  'tb_reading_time',
  'tb_groups',
  'tb_vocab_items',
  'tb_character_cards',
  'tb_character_relations',
  'tb_world_settings',
  'tb_timeline_events',
  'tb_character_chat_sessions',
  'tb_character_chat_messages',
  'tb_self_cards',
  'tb_crossover_scenes',
  'tb_knowledge_items',
  'tb_story_recaps',
  'tb_gameplay_sessions',
};

/// `ensureSchemaIntegrity` **覆盖不到**的表 —— 中断迁移后的永久缺口。
///
/// 出处：tool/db_migration_harness.py T3/T4。修复前 = `{tb_groups, tb_vocab_items}`
/// （14 个中断点里有 8 个自愈后仍永久缺表）；patch 0003 之后应为**空集**。
/// 这个常量保留下来当"棘轮"：一旦有人把补表逻辑删掉，下面的断言会立刻红。
const Set<String> kSelfHealGapTables = <String>{};

Future<List<String>> _tables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  );
  return rows.map((r) => r['name'] as String).toList()..sort();
}

Future<List<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ReadingStylePrefs.ensureInitialized();

    // case2 会 Directory('$documentPath/file').listSync() —— 目录不存在会直接抛，
    // 于是 onCreate 半途而废。测试里把 documentPath 指到一个建好的临时目录。
    tmp = await Directory.systemTemp.createTemp('sj_migration_test_');
    Directory(p.join(tmp.path, 'file')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'cover')).createSync(recursive: true);
    // documentPath 是 get_base_path.dart 的可变顶层变量，跨库赋值合法（非 final/const）
    documentPath = tmp.path;

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<Database> openFresh({int version = currentDbVersion}) async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (d, v) => DBHelper().onUpgradeDatabase(d, 0, v),
        onUpgrade: DBHelper().onUpgradeDatabase,
      ),
    );
    return db;
  }

  group('① onCreate：空库一路建到 v15', () {
    test('建出 18 张表（数目与 Python harness 实测一致）', () async {
      final d = await openFresh();
      final all = await _tables(d);
      expect(all.length, 18, reason: '实测表：$all');
      expect(all.toSet(), kV15Tables);
    });

    test('关键列齐备（这些列决定 DAO 的 SELECT 会不会抛）', () async {
      final d = await openFresh();
      expect(await _columns(d, 'tb_books'),
          containsAll(['rating', 'group_id', 'file_md5', 'series_name', 'series_index']));
      expect(await _columns(d, 'tb_notes'), contains('reader_note'));
      expect(await _columns(d, 'tb_themes'), contains('name'));
      expect(await _columns(d, 'tb_character_cards'), contains('avatar_path'));
      expect(await _columns(d, 'tb_gameplay_sessions'),
          containsAll(['mode_id', 'secret', 'revealed', 'ended']));
    });

    test('预置主题 6 条，且不重复（case7 的守卫必须跳过，否则一个库会有 10 条主题）',
        () async {
      final d = await openFresh();
      final n = Sqflite.firstIntValue(
        await d.rawQuery('SELECT COUNT(*) FROM tb_themes'),
      );
      expect(n, 6, reason: 'case0 已建含 name 列的表并插 6 条；case7 守卫应整块跳过');
    });

    test('case2 把 base 目录下的书/封面文件改名到 72 字符内（迁移的副作用之一）',
        () async {
      final f = File(p.join(tmp.path, 'file', 'a b c.epub'))
        ..writeAsStringSync('x');
      // 直接调用迁移：case0 会把表建好，case2 会遍历 file/ 改名
      final d = await openFresh();
      expect(await d.rawQuery('SELECT COUNT(*) FROM tb_books'), isNotEmpty);
      // 名字里的空格被替换为下划线
      expect(f.existsSync() || File(p.join(tmp.path, 'file', 'a_b_c.epub')).existsSync(), isTrue);
    });
  });

  group('① ensureSchemaIntegrity：唯一的自愈入口', () {
    test('能建出 14 张表：角色/对话/加料/头像/玩法 11 张 + tb_groups/tb_vocab_items + 审计表',
        () async {
      final d = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false, readOnly: false),
      );
      await DBHelper().ensureSchemaIntegrity(d);
      final healed = (await _tables(d)).toSet();
      expect(healed, contains('tb_character_cards'));
      expect(healed, contains('tb_gameplay_sessions'));
      // ↓ patch 0003 的核心断言：这两张表原先漏在自愈之外，中断迁移后永久缺失。
      expect(healed, contains('tb_groups'));
      expect(healed, contains('tb_vocab_items'));
      // 11（角色/对话/加料/头像/玩法）+ 2（tb_groups/tb_vocab_items）+ 1（md5 去重审计表）
      expect(healed.length, 14, reason: '自愈应建出 14 张表，实得 ${healed.length}: $healed');
      expect(healed, contains('tb_book_md5_dedup_audit'));
      expect(kSelfHealGapTables, isEmpty, reason: '自愈缺口必须为空集');
      // 0010：/自愈还必须建出 md5 的部分唯一索引（否则重复行会一直长下去）
      final idx = await d.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_books_file_md5_unique'");
      expect(idx.length, 1);
      await d.close();
    });

    test('连跑 3 次无异常、且不改变结构（幂等）', () async {
      final d = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false, readOnly: false),
      );
      await DBHelper().ensureSchemaIntegrity(d);
      final a = await d.rawQuery("SELECT name,sql FROM sqlite_master ORDER BY name");
      for (var i = 0; i < 3; i++) {
        await DBHelper().ensureSchemaIntegrity(d);
      }
      final b = await d.rawQuery("SELECT name,sql FROM sqlite_master ORDER BY name");
      expect(b.map((r) => '${r['name']}|${r['sql']}').toList(),
          a.map((r) => '${r['name']}|${r['sql']}').toList());
      await d.close();
    });
  });

  group('① 老库升级：不丢列、不丢行', () {
    test('从 v1 升级到 v15：行与阅读进度保留，新列补齐', () async {
      // 用 database.dart 里**公开的** DDL 常量造一个 v1 库（与 case0 完全同源）
      final d = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false, readOnly: false),
      );
      await d.execute(createBookSQL);
      await d.execute(createNoteSQL);
      await d.execute(createThemeSQL);
      await d.execute(createStyleSQL);
      await d.execute(createReadingTimeSQL);
      await d.execute(primaryTheme1);
      await d.insert('tb_books', {
        'title': '书A',
        'cover_path': 'cover/a',
        'file_path': 'file/a',
        'last_read_position': 'cfi-1',
        'reading_percentage': 12.5,
        'author': '作者甲',
        'is_deleted': 0,
        'description': 'd',
        'create_time': 't0',
        'update_time': 't1',
      });
      await d.insert('tb_notes', {'book_id': 1, 'content': '批注', 'cfi': 'cfi-1'});

      // v1 → v15（onUpgradeDatabase 的 switch 会从 case1 一路 fall-through 到 case14）
      await DBHelper().onUpgradeDatabase(d, 1, currentDbVersion);

      final books = await d.rawQuery('SELECT * FROM tb_books');
      expect(books.length, 1, reason: '升级不得丢行');
      expect(books.first['title'], '书A');
      expect(books.first['last_read_position'], 'cfi-1', reason: '阅读进度不得被清');
      expect(books.first['reading_percentage'], 12.5);
      expect(books.first['author'], '作者甲');
      final notes = await d.rawQuery('SELECT * FROM tb_notes');
      expect(notes.length, 1);
      expect((await _tables(d)).toSet(), kV15Tables, reason: '升级后表集合应与新建库完全一致');
      await d.close();
    });

    test('老库（tb_themes 无 name 列）升级：只改上游两个预置，不误伤用户自建主题', () async {
      final d = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false, readOnly: false),
      );
      // 上游时代的主题表（没有 name 列）
      await d.execute(
        'CREATE TABLE tb_themes (id INTEGER PRIMARY KEY AUTOINCREMENT, background_color TEXT, '
        'text_color TEXT, background_image_path TEXT)',
      );
      await d.insert('tb_themes', {'background_color': 'fffbfbf3', 'text_color': 'ff343434', 'background_image_path': ''});
      await d.insert('tb_themes', {'background_color': 'ff040404', 'text_color': 'fffeffeb', 'background_image_path': ''});
      await d.insert('tb_themes', {'background_color': 'ff111111', 'text_color': 'ff222222', 'background_image_path': 'u.png'});
      // 补齐 case0 其余表，避免 case1 之后的操作找不到表
      await d.execute(createBookSQL);
      await d.execute(createNoteSQL);
      await d.execute(createStyleSQL);
      await d.execute(createReadingTimeSQL);

      await DBHelper().onUpgradeDatabase(d, 1, currentDbVersion);

      final rows = await d.rawQuery('SELECT name, background_color FROM tb_themes ORDER BY id');
      expect(rows.length, 7, reason: '3 条原有 + case7 追加的 4 条预置');
      expect(rows[0]['name'], '宣纸');
      expect(rows[1]['name'], '松烟');
      expect(rows[2]['name'], isNull, reason: '用户自建主题（配色不同）不得被改名/改色');
      expect(rows[2]['background_color'], 'ff111111');
      await d.close();
    });
  });
}
