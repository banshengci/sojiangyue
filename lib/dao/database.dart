import 'dart:async';
import 'dart:io';
import 'package:songjiang_reader/utils/get_path/get_cache_dir.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/dao/character_chat_schema.dart';
import 'package:songjiang_reader/dao/character_extras_schema.dart';
import 'package:songjiang_reader/dao/character_schema.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/utils/get_path/databases_path.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Current app database version
const int currentDbVersion = 14;

const createBookSQL = '''
CREATE TABLE tb_books (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT,
  cover_path TEXT,
  file_path TEXT,
  last_read_position TEXT,
  reading_percentage REAL,
  author TEXT,
  is_deleted INTEGER,
  description TEXT,
  create_time TEXT,
  update_time TEXT
)
''';

const createThemeSQL = '''
CREATE TABLE tb_themes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  background_color TEXT,
  text_color TEXT,
  background_image_path TEXT
)
''';

const createStyleSQL = '''
CREATE TABLE tb_styles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  font_size REAL,
  font_family TEXT,
  line_height REAL,
  letter_spacing REAL,
  word_spacing REAL,
  paragraph_spacing REAL,
  side_margin REAL,
  top_margin REAL,
  bottom_margin REAL
)
''';

// 松江阅预置阅读主题。
// 命名取江南 / 水墨意象，配色与品牌松绿体系呼应；
// 深色主题刻意避开纯黑 + 纯白，减轻夜间阅读的眩光。
const primaryTheme1 = '''
INSERT INTO tb_themes (name, background_color, text_color, background_image_path) VALUES ('宣纸', 'fffbf7ee', 'ff2e2a24', '')
''';
const primaryTheme2 = '''
INSERT INTO tb_themes (name, background_color, text_color, background_image_path) VALUES ('松烟', 'ff121815', 'ffe6ede4', '')
''';
const primaryTheme3 = '''
INSERT INTO tb_themes (name, background_color, text_color, background_image_path) VALUES ('竹月', 'ffe9efe6', 'ff26412f', '')
''';
const primaryTheme4 = '''
INSERT INTO tb_themes (name, background_color, text_color, background_image_path) VALUES ('藕荷', 'fff6ebe7', 'ff4a3a36', '')
''';
const primaryTheme5 = '''
INSERT INTO tb_themes (name, background_color, text_color, background_image_path) VALUES ('秋杏', 'fffaf0dc', 'ff3b2f22', '')
''';
const primaryTheme6 = '''
INSERT INTO tb_themes (name, background_color, text_color, background_image_path) VALUES ('苍黛', 'ff0b0f0d', 'ffc6d0c8', '')
''';

/// 老用户升级用：把上游遗留的两个预置配色换成松江阅品牌配色。
/// 按原始配色精确匹配，避免误伤用户自建主题。
const upgradeTheme1 = '''
UPDATE tb_themes SET name = '宣纸', background_color = 'fffbf7ee', text_color = 'ff2e2a24'
  WHERE background_color = 'fffbfbf3' AND text_color = 'ff343434'
''';
const upgradeTheme2 = '''
UPDATE tb_themes SET name = '松烟', background_color = 'ff121815', text_color = 'ffe6ede4'
  WHERE background_color = 'ff040404' AND text_color = 'fffeffeb'
''';

const createNoteSQL = '''
CREATE TABLE tb_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER,
  content TEXT,
  cfi TEXT,
  chapter TEXT,
  type TEXT,
  color TEXT,
  create_time TEXT,
  update_time TEXT
)
''';

const createReadingTimeSQL = '''
CREATE TABLE tb_reading_time (
  id INTEGER PRIMARY KEY,
  book_id INTEGER,
  date TEXT,
  reading_time INTEGER
)
''';

const createGroupSQL = '''
CREATE TABLE tb_groups (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  parent_id INTEGER,
  is_deleted INTEGER DEFAULT 0,
  create_time TEXT,
  update_time TEXT,
  FOREIGN KEY (parent_id) REFERENCES tb_groups(id)
)
''';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  static Database? _database;
  static bool updatedDB = false;

  factory DBHelper() {
    return _instance;
  }

  DBHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDB();
    return _database!;
  }

  Future<Database> initDB() async {
    int dbVersion = currentDbVersion;
    switch (SjPlatform.type) {
      case SjPlatformEnum.macos:
      case SjPlatformEnum.android:
      case SjPlatformEnum.ohos:
        final databasePath = await getSjDatabasesPath();
        final path = join(databasePath, 'app_database.db');
        final db = await openDatabase(
          path,
          version: dbVersion,
          onCreate: (db, version) async {
            await onUpgradeDatabase(db, 0, version);
          },
          onUpgrade: onUpgradeDatabase,
        );
        // 打开后做一次幂等结构自检，兜住历史上可能中断的迁移
        await ensureSchemaIntegrity(db);
        return db;
      case SjPlatformEnum.ios:
      case SjPlatformEnum.windows:
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;

        final databasePath = await getSjDatabasesPath();
        SjLog.info('Database: database path: $databasePath');
        final path = join(databasePath, 'app_database.db');

        final db = await databaseFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: dbVersion,
            onCreate: (db, version) async {
              await onUpgradeDatabase(db, 0, version);
            },
            onUpgrade: onUpgradeDatabase,
          ),
        );
        await ensureSchemaIntegrity(db);
        return db;
    }
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// Checkpoint WAL to merge data into main database file
  /// Returns true if checkpoint was successful or not needed
  static Future<bool> checkpointWal() async {
    try {
      final db = await DBHelper().database;
      // Use rawQuery instead of execute for PRAGMA wal_checkpoint
      // because it returns a result row which can cause issues with execute()
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      SjLog.info('Database: WAL checkpoint completed');
      return true;
    } catch (e) {
      SjLog.warning('Database: WAL checkpoint failed: $e');
      return false;
    }
  }

  /// Get the path to the WAL file for a database
  static String getWalPath(String dbPath) => '$dbPath-wal';

  /// Get the path to the SHM file for a database
  static String getShmPath(String dbPath) => '$dbPath-shm';

  /// Check if WAL files exist for a database and have content
  static bool hasWalFiles(String dbPath) {
    final walFile = File(getWalPath(dbPath));
    return walFile.existsSync() && walFile.lengthSync() > 0;
  }

  /// Delete WAL auxiliary files
  static Future<void> cleanupWalFiles(String dbPath) async {
    try {
      final walFile = File(getWalPath(dbPath));
      final shmFile = File(getShmPath(dbPath));
      if (walFile.existsSync()) await walFile.delete();
      if (shmFile.existsSync()) await shmFile.delete();
      SjLog.info('Database: WAL files cleaned up');
    } catch (e) {
      SjLog.warning('Database: Failed to cleanup WAL files: $e');
    }
  }

  /// Create a snapshot of the database for upload using VACUUM INTO
  /// This avoids closing the database or locking it for long periods
  static Future<String> prepareUploadSnapshot() async {
    try {
      final db = await DBHelper().database;
      final cacheDir = await getSjCacheDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final snapshotPath = join(cacheDir.path, 'snapshot_aaaa_$timestamp.db');

      // Ensure any existing file is removed
      final snapshotFile = File(snapshotPath);
      if (snapshotFile.existsSync()) {
        await snapshotFile.delete();
      }

      // VACUUM INTO creates a transactionally consistent copy
      // It works even if the DB is in WAL mode and open
      try {
        // Use string interpolation instead of binding for VACUUM INTO
        // as some SQLite wrappers/versions don't support bindings in VACUUM statements
        final escapedPath = snapshotPath.replaceAll("'", "''");
        await db.execute("VACUUM INTO '$escapedPath'");
      } catch (e) {
        SjLog.warning('Database: VACUUM INTO failed ($e)');

        // Fallback strategy for platforms with older SQLite versions
        // (SQLite 3.27.0+ required for VACUUM INTO support)
        SjLog.info('Database: Using fallback strategy (Checkpoint+Copy)');

        // 1. Force Checkpoint to ensure all WAL data is written to main DB file
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

        // 2. Copy file manually
        final databasePath = await getSjDatabasesPath();
        final dbPath = join(databasePath, 'app_database.db');
        await File(dbPath).copy(snapshotPath);
      }

      SjLog.info('Database: Created snapshot at $snapshotPath');

      // Ensure the snapshot has a clean header (Legacy mode)
      // This guarantees the uploaded file is compatible with all platforms
      await fixDatabaseHeader(snapshotPath);

      return snapshotPath;
    } catch (e) {
      SjLog.severe('Database: Failed to create snapshot: $e');
      rethrow;
    }
  }

  /// Directly patch the database file header to switch from WAL mode to Legacy mode
  /// WAL mode sets the file format byte (offset 18) and version byte (offset 19) to 2
  /// We need to reset them to 1 (Legacy) to allow opening without -wal file
  static Future<void> fixDatabaseHeader(String dbPath) async {
    try {
      final file = File(dbPath);
      if (!file.existsSync()) return;

      // 1. Check header first to avoid expensive read/write if not needed
      bool needsPatch = false;
      final raf = await file.open(mode: FileMode.read);
      try {
        if (await raf.length() > 20) {
          await raf.setPosition(18);
          final writeVersion = await raf.readByte();
          final readVersion = await raf.readByte();

          if (writeVersion == 2 || readVersion == 2) {
            needsPatch = true;
            SjLog.info(
                'Database: Detected WAL mode in header (v$writeVersion/v$readVersion), patching to Legacy mode');
          }
        }
      } finally {
        await raf.close();
      }

      // 2. Patch if needed logic (Read-Modify-Write)
      if (needsPatch) {
        final bytes = await file.readAsBytes();
        if (bytes.length > 20) {
          bytes[18] = 1; // Write version: 1 (Legacy)
          bytes[19] = 1; // Read version: 1 (Legacy)

          await file.writeAsBytes(bytes, flush: true);
          SjLog.info('Database: patched header 18, 19 to 1 successfully');
        }
      }
    } catch (e) {
      SjLog.warning('Database: Failed to patch database header: $e');
    }
  }

  /// Get the latest modification time including WAL file
  /// This ensures we detect changes even if they're only in the WAL
  static DateTime getLatestModTime(String dbPath) {
    final dbFile = File(dbPath);
    final walFile = File(getWalPath(dbPath));

    DateTime dbTime = dbFile.existsSync()
        ? dbFile.lastModifiedSync()
        : DateTime.fromMillisecondsSinceEpoch(0);

    if (walFile.existsSync()) {
      DateTime walTime = walFile.lastModifiedSync();
      if (walTime.isAfter(dbTime)) {
        return walTime;
      }
    }

    return dbTime;
  }

  Future<void> onUpgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    SjLog.info('Database: upgrade database from $oldVersion to $newVersion');
    switch (oldVersion) {
      case 0:
        SjLog.info('Database: create database version $newVersion');
        await db.execute(createBookSQL);
        await db.execute(createNoteSQL);
        await db.execute(createThemeSQL);
        await db.execute(createStyleSQL);
        await db.execute(createReadingTimeSQL);
        await db.execute(primaryTheme1);
        await db.execute(primaryTheme2);
        await db.execute(primaryTheme3);
        await db.execute(primaryTheme4);
        await db.execute(primaryTheme5);
        await db.execute(primaryTheme6);
        continue case1;
      case1:
      case 1:
        // add a column (rating) to tb_books
        await db.execute('ALTER TABLE tb_books ADD COLUMN rating REAL');
        // remove '/data/user/0/com.songjiang.reader/app_flutter/' from file_path & cover_path
        await db.execute(
            "UPDATE tb_books SET file_path = REPLACE(file_path, '/data/user/0/com.songjiang.reader/app_flutter/', '')");
        await db.execute(
            "UPDATE tb_books SET cover_path = REPLACE(cover_path, '/data/user/0/com.songjiang.reader/app_flutter/', '')");
        continue case2;
      case2:
      case 2:
        // replave ' ' with '_' in db and cut file name to 25
        await db.execute(
            "UPDATE tb_books SET file_path = REPLACE(file_path, ' ', '_')");
        await db.execute(
            "UPDATE tb_books SET cover_path = REPLACE(cover_path, ' ', '_')");
        await db.execute(
            "UPDATE tb_books SET file_path = SUBSTR(file_path, 0, 25)");
        await db.execute(
            "UPDATE tb_books SET cover_path = SUBSTR(cover_path, 0, 25)");
        await db
            .execute("UPDATE tb_books SET file_path = file_path || '.epub'");
        await db
            .execute("UPDATE tb_books SET cover_path = cover_path || '.png'");

        final basePath = getBasePath('');
        final fileDir = Directory('$basePath/file');
        final coverDir = Directory('$basePath/cover');
        fileDir.listSync().forEach((element) {
          if (element is File) {
            final path = element.path;
            String pathAfterReplace = path.replaceAll(' ', '_');
            int endIndex =
                (pathAfterReplace.length < 72) ? pathAfterReplace.length : 72;
            final newPath = '${pathAfterReplace.substring(0, endIndex)}.epub';
            element.rename(newPath);
          }
        });
        coverDir.listSync().forEach((element) {
          if (element is File) {
            final path = element.path;
            String pathAfterReplace = path.replaceAll(' ', '_');
            int endIndex =
                (pathAfterReplace.length < 72) ? pathAfterReplace.length : 72;
            final newPath = '${pathAfterReplace.substring(0, endIndex)}.png';
            element.rename(newPath);
          }
        });
        continue case3;
      case3:
      case 3:
        // remove former book style
        ReadingStylePrefs.removeBookStyle();
        // 原先这里会 `.then` 遍历所有书、对缺封面的调用 resetBookCover()，
        // 而它内部走 getBookMetadata（headless WebView 重新解析）。两个问题：
        //   1) 迁移此刻仍在 openDatabase 内部，_database 还没赋值，任何 DAO 调用
        //      都会触发二次 openDatabase 并复入同一把锁，抛
        //      "Bad state: inner synchronized block spawned outside the block"
        //      （实测安装后启动即报一条 SEVERE，见 2026-10-07 日志）；
        //   2) 对老库每本书都启一次 WebView，启动开销极大。
        // 该逻辑属于历史遗留（v2→v3 的封面路径变更），导入侧现已具备兜底解析，
        // 不再需要在迁移中做，故移除以免拖垮启动。
        continue case4;
      case4:
      case 4:
        // add a column (group_id) to tb_books, and set all group_id to 0 default
        await db.execute("ALTER TABLE tb_books ADD COLUMN group_id INTEGER");
        await db.execute("UPDATE tb_books SET group_id = 0");
        continue case5;
      case5:
      case 5:
        // add a column (reader_note) to tb_notes, null default
        await db.execute("ALTER TABLE tb_notes ADD COLUMN reader_note TEXT");
        continue case6;
      case6:
      case 6:
        // create groups table and migrate existing data
        await db.execute(createGroupSQL);
        // add a column (file_md5) to tb_books
        await db.execute("ALTER TABLE tb_books ADD COLUMN file_md5 TEXT");

        // Insert root group
        await db.execute(
            "INSERT INTO tb_groups (id, name, parent_id, create_time, update_time) VALUES (0, 'Root', NULL, datetime('now'), datetime('now'))");

        // Get all unique group_ids from books
        final List<Map<String, dynamic>> uniqueGroups = await db.rawQuery('''
          SELECT DISTINCT group_id 
          FROM tb_books 
          WHERE group_id IS NOT NULL AND group_id != 0
        ''');

        // Create groups for existing group_ids
        for (var i = 0; i < uniqueGroups.length; i++) {
          final groupId = uniqueGroups[i]['group_id'];
          await db.execute('''
            INSERT INTO tb_groups (id, name, parent_id, create_time, update_time)
            VALUES (?, '...', 0, datetime('now'), datetime('now'))
          ''', [groupId]);
        }
        continue case7;
      case7:
      case 7:
        // 松江阅阅读主题：为主题表增加名字列，并把预置配色换成品牌色系。
        // 新建库在 createThemeSQL 里已带 name 列，这里检测后跳过，只对老库迁移。
        final themeColumns = await db.rawQuery('PRAGMA table_info(tb_themes)');
        final hasThemeName =
            themeColumns.any((column) => column['name'] == 'name');
        if (!hasThemeName) {
          await db.execute('ALTER TABLE tb_themes ADD COLUMN name TEXT');
          await db.execute(upgradeTheme1);
          await db.execute(upgradeTheme2);
          await db.execute(primaryTheme3);
          await db.execute(primaryTheme4);
          await db.execute(primaryTheme5);
          await db.execute(primaryTheme6);
        }
        continue case8;
      case8:
      case 8:
        // 松江阅：生词/难句本
        await db.execute('''
          CREATE TABLE IF NOT EXISTS tb_vocab_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term TEXT NOT NULL,
            gloss TEXT,
            book_id INTEGER,
            book_title TEXT,
            chapter TEXT,
            create_time TEXT,
            review_count INTEGER NOT NULL DEFAULT 0,
            last_review_time TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_vocab_term ON tb_vocab_items(term)');
        continue case9;
      case9:
      case 9:
        // 松江阅：书籍系列元数据（Calibre 风格）
        final bookCols = await db.rawQuery('PRAGMA table_info(tb_books)');
        final hasSeries =
            bookCols.any((c) => c['name'] == 'series_name');
        if (!hasSeries) {
          await db.execute('ALTER TABLE tb_books ADD COLUMN series_name TEXT');
          await db.execute('ALTER TABLE tb_books ADD COLUMN series_index REAL');
        }
        continue case10;
      case10:
      case 10:
        // 松江阅 P0：角色卡 / 关系 / 设定 / 时间线
        await applyCharacterSchema(db);
        continue case11;
      case11:
      case 11:
        // 松江阅：角色对话（会话 + 消息）
        await applyCharacterChatSchema(db);
        continue case12;
      case12:
      case 12:
        // 松江阅：自设卡 / 穿越场景 / 原著知识 / 剧情回顾
        await applyCharacterExtrasSchema(db);
        continue case13;
      case13:
      case 13:
        // 松江阅：人物卡头像路径
        await addCharacterAvatarColumn(db);
    }

    if (oldVersion != 0 && SyncPrefs.webdavStatus) {
      updatedDB = true;
    }
  }
}

// ---- 打开数据库后的结构自检 ----

/// 幂等补齐「必须存在的表与列」。
///
/// 为什么需要它：迁移是一次性的。历史上 case3 曾在迁移过程中调用 DAO，
/// 触发 openDatabase 复入同一把锁而抛异常（见 2026-10-07 实机日志）。
/// 一旦某个 case 因意外中断，库结构就会停在中间状态，而 sqflite 已把
/// user_version 写成最新值，之后**永远不会重跑迁移**——用户只能清数据重装。
///
/// 这里每次打开数据库都做一遍幂等补齐（表用 CREATE TABLE IF NOT EXISTS，
/// 列先 PRAGMA 判存在再 ALTER），从而具备自愈能力。
Future<void> ensureSchemaIntegrity(Database db) async {
  try {
    await applyCharacterSchema(db);
    await applyCharacterChatSchema(db);
    await applyCharacterExtrasSchema(db);
    await addCharacterAvatarColumn(db);

    // tb_books 历史上分几次加的列
    await _ensureColumn(db, 'tb_books', 'rating', 'REAL');
    await _ensureColumn(db, 'tb_books', 'group_id', 'INTEGER');
    await _ensureColumn(db, 'tb_books', 'file_md5', 'TEXT');
    await _ensureColumn(db, 'tb_books', 'series_name', 'TEXT');
    await _ensureColumn(db, 'tb_books', 'series_index', 'REAL');
    // 其他表的历史新增列
    await _ensureColumn(db, 'tb_notes', 'reader_note', 'TEXT');
    await _ensureColumn(db, 'tb_themes', 'name', 'TEXT');
  } catch (e, st) {
    // 自检失败不应阻断启动
    SjLog.severe('Database: 结构自检失败: $e\n$st');
  }
}

Future<void> _ensureColumn(
  Database db,
  String table,
  String column,
  String type,
) async {
  try {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.isEmpty) return; // 表不存在，交给各自的 create 语句
    if (cols.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    SjLog.info('Database: 自检补列 $table.$column');
  } catch (e) {
    SjLog.warning('Database: 自检补列失败 $table.$column: $e');
  }
}
