import 'dart:async';
import 'dart:io' show Platform;

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:songjiang_reader/dao/deep_read_schema.dart';
import 'package:songjiang_reader/dao/reading_session_schema.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';

/// 本地缓存库版本号。仅随 [localCacheSchema] 变化递增。
const int currentLocalCacheVersion = 1;

/// 本地缓存库文件名。刻意与主库 `app_database.db` 区分开。
const String localCacheDbFileName = 'local_cache.db';

/// 「只住在本机、永不参与 WebDAV 同步」的那批数据的家。
///
/// 为什么要单独一个库文件：主库的 WebDAV 同步是**整库文件快照替换**
/// （上传侧 `VACUUM INTO` 打包整个 `app_database.db`，下载侧 `safeDownloadDatabase()`
/// 原子替换整个库文件），`lib/service/sync/**` 里没有任何按表 SQL ——
/// 也就是说**没有「让某张表不进同步」这种开关**。想让数据真的不同步，
/// 唯一的办法就是让它不住在被同步的那个文件里。
///
/// 副作用正好也是我们要的：这个库不参与迁移链，老用户升级后天然是空的
/// （内容均为可再生缓存或本设备行为数据），新 App 首次访问自动建库。
class LocalCacheDb {
  static final LocalCacheDb _instance = LocalCacheDb._internal();

  factory LocalCacheDb() => _instance;

  LocalCacheDb._internal();

  static Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final opened = await open();
    _database = opened;
    return opened;
  }

  static Future<Database> open() async {
    final dbPath = await resolvePath();
    final version = currentLocalCacheVersion;

    Future<void> createAll(Database db) async {
      await applyDeepReadSchema(db);
      await applyReadingSessionSchema(db);
    }

    switch (SjPlatform.type) {
      case SjPlatformEnum.android:
      case SjPlatformEnum.ohos:
      case SjPlatformEnum.macos:
        // 移动端与 macOS 走 sqflite 插件自带的 factory，无需 ffi 初始化。
        // macOS 分支虽然共用 sqfliteFfiInit 更省心，但保持与主库同样的分支口径，
        // 避免两套库在个别平台上 Factory 不一致。
        return databaseFactory.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: version,
            onCreate: (db, _) => createAll(db),
            onUpgrade: (db, _, __) => createAll(db),
          ),
        );

      case SjPlatformEnum.windows:
      case SjPlatformEnum.ios:
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        return databaseFactory.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: version,
            onCreate: (db, _) => createAll(db),
            onUpgrade: (db, _, __) => createAll(db),
          ),
        );
    }
  }

  /// 缓存库的落盘位置：与主库同目录、不同文件名。
  static Future<String> resolvePath() async {
    switch (SjPlatform.type) {
      case SjPlatformEnum.android:
      case SjPlatformEnum.ohos:
        final base = await getDatabasesPath();
        return join(base, localCacheDbFileName);
      case SjPlatformEnum.windows:
      case SjPlatformEnum.macos:
      case SjPlatformEnum.ios:
        final documentsPath = await getSjDocumentsPath();
        final dir = '$documentsPath${Platform.pathSeparator}databases';
        return join(dir, localCacheDbFileName);
    }
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// 整库清空。目前只预计给「重置某人物的羁绊」这类显式入口调用，
  /// **不要**在删除书籍/会话的常规路径里调用。
  static Future<void> resetall() async {
    try {
      await close();
      final dbPath = await resolvePath();
      await deleteDatabase(dbPath);
      SjLog.warning('LocalCacheDb: 已清空本地缓存库 $dbPath');
    } catch (e, st) {
      SjLog.severe('LocalCacheDb: 清空失败: $e\n$st');
    }
  }
}
