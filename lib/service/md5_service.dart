import 'dart:io';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/models/import_file_check.dart';
import 'package:songjiang_reader/models/md5_calculating_result.dart';
import 'package:songjiang_reader/models/md5_statistics.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:crypto/crypto.dart';

class MD5Service {
  static Future<String?> calculateFileMd5(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final digest = md5.convert(bytes);
      return digest.toString();
    } catch (e) {
      SjLog.severe('Error calculating MD5 for $filePath: $e');
      return null;
    }
  }

  /// 兜底去重键：`size:<字节数>:<sha1(首 32KB + 尾 32KB)>`。
  ///
  /// 只在 [calculateFileMd5] 拿不到 md5（文件读不出来 / 不存在）时使用。
  ///
  /// 为什么不用 null 跳过查重：那会让"同一个文件导入两次"落两行，而且两行的
  /// file_md5 都是 NULL，事后无法自动收敛（阶段三 harness I4 实测）。
  ///
  /// 为什么不会误合并：
  ///   1) 前缀 `size:` 保证不可能与 32 位十六进制 md5 撞车（md5 不含冒号）；
  ///   2) 对 EPUB/ZIP 而言，尾部 32KB 落在中央目录上，里面含每个条目的
  ///      文件名/CRC32/偏移量 —— 两份不同的 EPUB 几乎必然在这里不同；
  ///   3) 文件 < 64KB 时首尾区间重叠，等价于整个文件的 sha1；
  ///   4) 对比原行为（完全不查重、必然产生重复行），这是严格更优的兜底。
  /// 残留风险：人为构造的"长度相同 + 首尾 32KB 相同"的文件会被判为同一本 ——
  /// 对一个阅读器来说这个概率可接受，且只影响"自动去重"，不影响数据本身。
  static Future<String?> calculateFileFingerprint(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final length = await file.length();
      const window = 32 * 1024;
      final head = await _readSlice(file, 0, window < length ? window : length);
      final tailStart = length > window ? length - window : 0;
      final tail = tailStart >= head.length
          ? await _readSlice(file, tailStart, length)
          : const <int>[];
      final digest = sha1.convert([...head, ...tail]);
      return 'size:$length:$digest';
    } catch (e) {
      SjLog.warning('Error calculating fingerprint for $filePath: $e');
      return null;
    }
  }

  static Future<List<int>> _readSlice(File file, int start, int end) async {
    if (end <= start) return const <int>[];
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      return await raf.read(end - start);
    } finally {
      await raf.close();
    }
  }

  /// 去重键统一入口：md5 优先，失败退到 [calculateFileFingerprint]。
  ///
  /// **导入前预检（[checkImportFiles]）与落库（saveBook）必须用同一个键**，
  /// 否则会出现"预检说不重复、落库却命中已有书"的错位 —— 这正是两处各自
  /// 判断 `md5 != null` 时留下的隐患。
  static Future<String?> dedupKeyFor(String filePath) async {
    final md5 = await calculateFileMd5(filePath);
    if (md5 != null && md5.isNotEmpty) return md5;
    final fingerprint = await calculateFileFingerprint(filePath);
    if (fingerprint != null) {
      SjLog.warning('MD5: $filePath 无法计算 md5，改用兜底指纹 $fingerprint 作为去重键');
    }
    return fingerprint;
  }

  /// 查重入口。空串/空白一律视为"没有 md5" → 返回 null（不参与查重），
  /// 与 [calculateFileMd5] 的返回约定、以及 `getBooksWithoutMd5()` 的口径一致。
  static Future<Book?> checkDuplicateByMd5(String md5) async {
    if (md5.trim().isEmpty) return null;
    return await bookDao.getBookByMd5(md5);
  }

  static Future<MD5CalculationResult> batchCalculateMd5(List<Book> books,
      {Function(int current, int total, String currentFile)?
          onProgress}) async {
    int calculated = 0;
    int skipped = 0;
    int failed = 0;
    List<String> missingFiles = [];

    for (int i = 0; i < books.length; i++) {
      final book = books[i];

      onProgress?.call(i + 1, books.length, book.title);

      if (!await File(book.fileFullPath).exists()) {
        missingFiles.add(book.title);
        skipped++;
        continue;
      }

      final md5 = await calculateFileMd5(book.fileFullPath);
      if (md5 != null) {
        // 有了 idx_books_file_md5_unique 之后，`file_md5` 可能已属于另一本书（历史上
        // 的重复行被无损去重后，md5 留给了保留者）。此时写入会被 ignore 掉，
        // 受影响行数为 0 —— 这不是失败，而是"这本就是重复本"，单独记账。
        final affected = await bookDao.updateBookMd5(book.id, md5);
        if (affected > 0) {
          calculated++;
        } else {
          skipped++;
          SjLog.warning(
              'MD5: 跳过回填 —— md5 已属于另一本书（本行保持不变）bookId=${book.id} title=${book.title}');
        }
      } else {
        failed++;
      }
    }

    return MD5CalculationResult(
      totalBooks: books.length,
      calculated: calculated,
      skipped: skipped,
      failed: failed,
      missingFiles: missingFiles,
    );
  }

  static Future<MD5Statistics> getMd5Statistics() async {
    final allBooks = await bookDao.selectNotDeleteBooks();
    final booksWithoutMd5 = await bookDao.getBooksWithoutMd5();

    int localFilesCount = 0;
    int localFilesWithoutMd5 = 0;

    for (final book in allBooks) {
      if (await File(book.fileFullPath).exists()) {
        localFilesCount++;
        if (book.md5 == null || book.md5!.isEmpty) {
          localFilesWithoutMd5++;
        }
      }
    }

    return MD5Statistics(
      totalBooks: allBooks.length,
      booksWithMd5: allBooks.length - booksWithoutMd5.length,
      booksWithoutMd5: booksWithoutMd5.length,
      localFilesCount: localFilesCount,
      localFilesWithoutMd5: localFilesWithoutMd5,
    );
  }

  static Future<List<ImportFileCheck>> checkImportFiles(
      List<String> filePaths) async {
    List<ImportFileCheck> results = [];

    for (final filePath in filePaths) {
      final md5 = await dedupKeyFor(filePath);
      Book? duplicateBook;

      if (md5 != null) {
        duplicateBook = await checkDuplicateByMd5(md5);
      }

      results.add(ImportFileCheck(
        filePath: filePath,
        md5: md5,
        isDuplicate: duplicateBook != null && !duplicateBook.isDeleted,
        duplicateBook: duplicateBook,
      ));
    }

    return results;
  }
}
