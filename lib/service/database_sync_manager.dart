import 'dart:io' as io;
import 'package:songjiang_reader/utils/platform_utils.dart';
import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/service/sync/sync_client_base.dart';
import 'package:songjiang_reader/utils/get_path/get_cache_dir.dart';
import 'package:songjiang_reader/utils/get_path/databases_path.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:path/path.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database safe sync manager
/// Provides safe database download, validation and recovery mechanisms
class DatabaseSyncManager {
  static const String _tempDbPrefix = 'temp_database_';
  static const String _backupDbPrefix = 'backup_database_';
  static const int _maxBackupCount = 3;

  /// Safe database download
  ///
  /// Process:
  /// 1. Download to cache temp file
  /// 2. Validate database integrity
  /// 3. Backup current database
  /// 4. Atomic replace database
  /// 5. Validate replacement result
  static Future<DatabaseSyncResult> safeDownloadDatabase({
    required SyncClientBase client,
    required String remoteDbFileName,
    void Function(int received, int total)? onProgress,
  }) async {
    final databasesPath = await getSjDatabasesPath();
    final cacheDir = SjPlatform.isOhos
        ? '${await getSjDatabasesPath()}/cache'
        : (await getSjCacheDir()).path;
    final localDbPath = join(databasesPath, 'app_database.db');

    // Generate temp file name (use timestamp to ensure uniqueness)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDbName = '$_tempDbPrefix$timestamp.db';
    final tempDbPath = join(cacheDir, tempDbName);

    try {
      SjLog.info('DatabaseSync: Starting safe database download');
      SjLog.info('DatabaseSync: Remote file: $remoteDbFileName');
      SjLog.info('DatabaseSync: Temp file: $tempDbPath');

      // Step 1: Download to temp file
      await client.downloadFile(
        'anx/$remoteDbFileName',
        tempDbPath,
        onProgress: onProgress,
      );

      SjLog.info('DatabaseSync: Download completed, starting validation');

      // Step 2: Validate downloaded database
      final validationResult = await _validateDatabase(tempDbPath);
      if (!validationResult.isValid) {
        await _cleanupTempFile(tempDbPath);
        return DatabaseSyncResult.failure(
          'Database validation failed: ${validationResult.error}',
          DatabaseSyncFailureType.validationFailed,
        );
      }

      SjLog.info(
          'DatabaseSync: Validation passed, proceeding with replacement');

      // Step 3: Backup current database
      final backupPath = await _createBackup(localDbPath);
      SjLog.info('DatabaseSync: Created backup at: $backupPath');

      // Step 4: Atomic replace database
      await _atomicReplaceDatabase(tempDbPath, localDbPath);

      // Step 5: Validate replaced database
      final finalValidation = await _validateDatabase(localDbPath);
      if (!finalValidation.isValid) {
        SjLog.severe(
            'DatabaseSync: Final validation failed, recovering from backup');
        await _recoverFromBackup(backupPath, localDbPath);
        return DatabaseSyncResult.failure(
          'Database replacement validation failed, recovered from backup',
          DatabaseSyncFailureType.replacementFailed,
        );
      }

      // Step 6: Cleanup and maintain backups
      await _cleanupOldBackups();
      await _cleanupTempFile(tempDbPath);

      SjLog.info(
          'DatabaseSync: Safe database download completed successfully');
      return DatabaseSyncResult.success('Database synchronized successfully');
    } catch (e) {
      SjLog.severe('DatabaseSync: Error during safe download: $e');
      await _cleanupTempFile(tempDbPath);

      return DatabaseSyncResult.failure(
        'Database sync failed: $e',
        DatabaseSyncFailureType.downloadFailed,
      );
    }
  }

  /// Validate database integrity
  static Future<DatabaseValidationResult> _validateDatabase(
      String dbPath) async {
    try {
      // Check if file exists and is not empty
      final dbFile = io.File(dbPath);
      if (!dbFile.existsSync()) {
        return DatabaseValidationResult.invalid('Database file does not exist');
      }

      final fileSize = dbFile.lengthSync();
      if (fileSize < 1024) {
        // Database file should be at least 1KB
        return DatabaseValidationResult.invalid(
            'Database file too small: ${fileSize}B');
      }

      // First, ensure the database is converted from WAL mode to DELETE mode
      // This is necessary because downloaded databases may be in WAL mode
      // and SQLite can't open them properly without the WAL files
      if (!SjPlatform.isOhos) {
        await DBHelper.fixDatabaseHeader(dbPath);
      }

      // Initialize FFI for desktop platforms
      Database? db;
      try {
        // Platform-specific database opening
        if (SjPlatform.isWindows) {
          sqfliteFfiInit();
          db = await databaseFactoryFfi.openDatabase(
            dbPath,
            options: OpenDatabaseOptions(
              readOnly: false,
              singleInstance: false,
            ),
          );
        } else {
          // Android/iOS
          db = await openDatabase(
            dbPath,
            readOnly: false,
            singleInstance: false,
          );
        }

        // Basic integrity check
        final integrityResult = await db.rawQuery('PRAGMA integrity_check');
        if (integrityResult.isEmpty ||
            integrityResult.first.values.first != 'ok') {
          return DatabaseValidationResult.invalid(
              'Database integrity check failed');
        }

        // Check if required tables exist
        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('tb_books', 'tb_themes', 'tb_styles')");

        if (tables.length < 3) {
          return DatabaseValidationResult.invalid('Missing required tables');
        }

        // Check database version first —— 它同时也是"这份文件是否被本 App 初始化过"的判据。
        final versionResult = await db.rawQuery('PRAGMA user_version');
        final dbVersion = versionResult.first.values.first as int;

        // user_version == 0 表示这份文件从来没跑过本 App 的迁移：
        // 要么是别人的 / 空白 sqlite 文件，要么是迁移根本没开始就中断了。
        // 这才是"未初始化"，与"库是好的但用户把书删光了"必须区分开。
        if (dbVersion == 0) {
          return DatabaseValidationResult.invalid(
              'Database is not initialized by this app (user_version=0)');
        }

        // tb_books 为空**不再**判非法。
        // 用户把书全部删光后，自己的库依然是一份完全合法的库；原来的
        // `if (count == 0) return invalid('Books table is empty')` 会让他
        // 永远无法上传，也无法在换机后从云端恢复（阶段三 harness S1b 实测）。
        // 这里把"空"降级为可接受状态，只记一条日志，不再提供拒绝理由。
        final bookCount =
            await db.rawQuery('SELECT COUNT(*) as count FROM tb_books');
        final count = bookCount.first['count'] as int;

        if (count == 0) {
          SjLog.info(
              'DatabaseSync: 远端库结构合法、书架为空（user_version=$dbVersion），按合法库接受');
        }

        if (dbVersion > currentDbVersion) {
          return DatabaseValidationResult.invalid(
              'Database version ($dbVersion) is newer than current version ($currentDbVersion)');
        }

        // 保守策略：**也拒绝更旧的库**。
        //
        // 依据：本模块是"整库文件替换"，**没有任何行级合并/冲突解决**（全文件 403 行可核对）。
        // 拿 v13 的文件覆盖本地 v15 的库，会让 v14/v15 引入的表（tb_gameplay_sessions 等）
        // 连同其中的数据整体消失，而用户只会看到"同步成功"。
        // 阶段三 harness S3 实测：本地 5 本 → 同步后 3 本，本地新增的 2 本不可恢复，
        // 且 PRAGMA user_version 从 15 回退到 13。
        //
        // 为什么不做自动合并：合并需要逐表主键 + 每行时间戳/墓碑，而当前 18 张表里
        // 大部分没有 updated_at 语义（tb_reading_time 只有 date 文本、tb_vocab_items
        // 没有稳定业务主键），先把"错的替换"挡住，比引入一个不可验证的合并要安全。
        if (dbVersion < currentDbVersion) {
          SjLog.severe(
              'DatabaseSync: 拒绝用更旧的远端库（v$dbVersion）覆盖本地 v$currentDbVersion '
              '—— 整库替换会丢数据');
          return DatabaseValidationResult.invalid(
              'Database version ($dbVersion) is older than current version '
              '($currentDbVersion). 整库替换会丢失 v${dbVersion + 1}..v$currentDbVersion 引入的'
              '表和数据，已拒绝同步。请在已升级到最新版的设备上先同步一次，'
              '或手动处理远端文件（Cache 目录里保留有同步前的本地备份）。');
        }

        SjLog.info(
            'DatabaseSync: Validation passed - $count books found, version $dbVersion');
        return DatabaseValidationResult.valid();
      } finally {
        await db?.close();
      }
    } catch (e) {
      return DatabaseValidationResult.invalid('Database validation error: $e');
    }
  }

  /// Create database backup
  static Future<String> _createBackup(String localDbPath) async {
    final cacheDir = await getSjCacheDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupName = '$_backupDbPrefix$timestamp.db';
    final backupPath = join(cacheDir.path, backupName);

    // Ensure database is closed
    await DBHelper.close();

    // Copy file
    await io.File(localDbPath).copy(backupPath);

    return backupPath;
  }

  /// Atomic replace database
  static Future<void> _atomicReplaceDatabase(
      String tempDbPath, String localDbPath) async {
    // Ensure database is closed
    await DBHelper.close();

    // Clean up local WAL files before replacement
    // This is critical on ALL platforms to avoid stale WAL/SHM files conflicting with the new DB
    await DBHelper.cleanupWalFiles(localDbPath);

    // Use file move operation for atomic replacement
    final tempFile = io.File(tempDbPath);
    await tempFile.copy(localDbPath);

    // Re-initialize database
    await DBHelper().initDB();
  }

  /// Recover database from backup
  static Future<void> _recoverFromBackup(
      String backupPath, String localDbPath) async {
    try {
      await DBHelper.close();
      // Ensure clean state before recovery
      await DBHelper.cleanupWalFiles(localDbPath);

      await io.File(backupPath).copy(localDbPath);
      await DBHelper().initDB();

      SjLog.info(
          'DatabaseSync: Successfully recovered from backup: $backupPath');
    } catch (e) {
      SjLog.severe('DatabaseSync: Failed to recover from backup: $e');
      rethrow;
    }
  }

  /// Cleanup temp file
  static Future<void> _cleanupTempFile(String tempDbPath) async {
    try {
      final tempFile = io.File(tempDbPath);
      if (tempFile.existsSync()) {
        await tempFile.delete();
        SjLog.info('DatabaseSync: Cleaned up temp file: $tempDbPath');
      }
    } catch (e) {
      SjLog.warning('DatabaseSync: Failed to cleanup temp file: $e');
    }
  }

  /// Cleanup expired backup files
  static Future<void> _cleanupOldBackups() async {
    try {
      final cacheDir = await getSjCacheDir();
      final backupFiles = cacheDir
          .listSync()
          .where((file) => file.path.contains(_backupDbPrefix))
          .cast<io.File>()
          .toList();

      // Sort by modification time, keep the latest ones
      backupFiles
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      if (backupFiles.length > _maxBackupCount) {
        final filesToDelete = backupFiles.skip(_maxBackupCount);
        for (final file in filesToDelete) {
          await file.delete();
          SjLog.info('DatabaseSync: Cleaned up old backup: ${file.path}');
        }
      }
    } catch (e) {
      SjLog.warning('DatabaseSync: Failed to cleanup old backups: $e');
    }
  }

  /// Show sync error dialog
  static Future<void> showSyncErrorDialog(DatabaseSyncResult result) async {
    String title;
    String content;
    final context = navigatorKey.currentContext!;

    switch (result.failureType) {
      case DatabaseSyncFailureType.downloadFailed:
        title = L10n.of(context).downloadFailed;
        content = L10n.of(context).downloadFailedContent;
        break;
      case DatabaseSyncFailureType.validationFailed:
        title = L10n.of(context).syncValidationFailed;
        content = L10n.of(context).syncValidationFailedContent;
        break;
      case DatabaseSyncFailureType.replacementFailed:
        title = L10n.of(context).replacementFailed;
        content = L10n.of(context).replacementFailedContent;
        break;
      default:
        title = L10n.of(context).syncUnknownError;
        content = result.message;
    }

    await SmartDialog.show(
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content),
            const SizedBox(height: 12),
            Text(
              'Details: ${result.message}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => SmartDialog.dismiss(),
            child: Text(L10n.of(navigatorKey.currentContext!).commonOk),
          ),
        ],
      ),
    );
  }

  /// Get available backup files
  static Future<List<String>> getAvailableBackups() async {
    try {
      final cacheDir = await getSjCacheDir();
      final backupFiles = cacheDir
          .listSync()
          .where((file) => file.path.contains(_backupDbPrefix))
          .cast<io.File>()
          .map((file) => file.path)
          .toList();

      backupFiles.sort((a, b) => b.compareTo(a));
      return backupFiles;
    } catch (e) {
      SjLog.warning('DatabaseSync: Failed to get available backups: $e');
      return [];
    }
  }
}

/// Database validation result
class DatabaseValidationResult {
  final bool isValid;
  final String? error;

  const DatabaseValidationResult._(this.isValid, this.error);

  factory DatabaseValidationResult.valid() =>
      const DatabaseValidationResult._(true, null);
  factory DatabaseValidationResult.invalid(String error) =>
      DatabaseValidationResult._(false, error);
}

/// Database sync result
class DatabaseSyncResult {
  final bool isSuccess;
  final String message;
  final DatabaseSyncFailureType? failureType;

  const DatabaseSyncResult._(this.isSuccess, this.message, this.failureType);

  factory DatabaseSyncResult.success(String message) =>
      DatabaseSyncResult._(true, message, null);

  factory DatabaseSyncResult.failure(
          String message, DatabaseSyncFailureType type) =>
      DatabaseSyncResult._(false, message, type);
}

///  Database sync failure types
enum DatabaseSyncFailureType {
  downloadFailed,
  validationFailed,
  replacementFailed,
}
