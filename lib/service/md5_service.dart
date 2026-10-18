import 'dart:io';
import 'dart:isolate';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/models/import_file_check.dart';
import 'package:songjiang_reader/models/md5_calculating_result.dart';
import 'package:songjiang_reader/models/md5_statistics.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:crypto/crypto.dart';

/// 流式读取文件并计算 MD5 的同步实现（在后台 isolate 中调用）。
///
/// 两个要点：
/// 1. **分块**：用 `md5.startChunkedConversion` 逐块喂数据，
///    内存占用与文件大小无关（固定为一个 chunk）。crypto 包明确要求大文件
///    不要用 `md5.convert(bytes)`——那需要把整个文件读进内存。
///    CBZ/CBR 漫画包常见上百 MB，整读会直接把内存打爆。
/// 2. **后台 isolate**：本函数是**同步**的，逐块读盘算哈希期间不会让出事件循环；
///    若在主 isolate 上跑，界面（包括「正在计算 MD5」的进度对话框）会完全卡死。
///    调用方负责用 [Isolate.run] 把它放到后台 isolate。
String _md5OfFileSync(String filePath) {
  const chunkSize = 1 << 20; // 1 MiB
  final out = _DigestSink();
  final sink = md5.startChunkedConversion(out);
  final raf = File(filePath).openSync(mode: FileMode.read);
  try {
    while (true) {
      final chunk = raf.readSync(chunkSize);
      if (chunk.isEmpty) break;
      sink.add(chunk);
    }
  } finally {
    raf.closeSync();
  }
  sink.close();
  final digest = out.value;
  if (digest == null) {
    throw StateError('chunked MD5 未产出 digest: $filePath');
  }
  return digest.toString();
}

/// 接住 chunked 转换最终产出的 [Digest]。
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class MD5Service {
  /// 计算文件 MD5。
  ///
  /// 实现方式见 [_md5OfFileSync]：分块读取 + 后台 isolate。
  /// 相比原先的「整文件读入内存后 md5.convert」，内存占用恒定，
  /// 且不会阻塞 UI——导入/批量补算时用户能看到进度真的在走。
  static Future<String?> calculateFileMd5(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      return await Isolate.run(() => _md5OfFileSync(filePath));
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
  /// file_md5 都是 NULL，事后无法自动收敛。
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
  /// 否则会出现"预检说不重复、落库却命中已有书"的错位。
  static Future<String?> dedupKeyFor(String filePath) async {
    final md5 = await calculateFileMd5(filePath);
    if (md5 != null && md5.isNotEmpty) return md5;
    final fingerprint = await calculateFileFingerprint(filePath);
    if (fingerprint != null) {
      SjLog.warning('MD5: $filePath 无法计算 md5，改用兜底指纹 $fingerprint 作为去重键');
    }
    return fingerprint;
  }

  /// 按 MD5 查是否已有同名文件的书（单条场景的便捷入口）。
  ///
  /// 空串/空白一律视为「没有 md5」→ 返回 null（不参与查重），
  /// 与 [calculateFileMd5] 的返回约定、以及 getBooksWithoutMd5() 的口径一致。
  /// 实现复用批量查询，避免与 [checkImportFiles] 各维护一套取数逻辑。
  static Future<Book?> checkDuplicateByMd5(String md5) async {
    if (md5.trim().isEmpty) return null;
    final map = await bookDao.getBooksByMd5s([md5]);
    return map[md5];
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
        await bookDao.updateBookMd5(book.id, md5);
        calculated++;
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

  /// 导入前逐文件检查是否与书库重复。
  ///
  /// 两处刻意的设计：
  /// 1. **先全部算哈希，再一次性查库**。原先是在循环里「算一个、查一次库」，
  ///    导入 N 个文件就是 N 次数据库往返；改为算完集中查一次
  ///    （[BookDao.getBooksByMd5s] 内部按 500 分块，规避 SQLite 变量上限）。
  /// 2. **串行算哈希**。哈希本身已在后台 isolate（见 [calculateFileMd5]），
  ///    不阻塞 UI；但刻意不并发——同时打开几十个文件句柄去争抢磁盘，
  ///    在机械硬盘 / 低速存储上反而更慢，而导入本来就是用户可等待的操作。
  ///    串行的另一个好处是进度语义天然正确：返回结果的顺序与入参一致。
  static Future<List<ImportFileCheck>> checkImportFiles(
      List<String> filePaths) async {
    // 第一遍：算哈希（内存恒定、不阻塞 UI）
    final md5ByPath = <String, String?>{};
    for (final filePath in filePaths) {
      // 用 dedupKeyFor：md5 拿不到时退到兜底指纹，与落库口径一致
      md5ByPath[filePath] = await dedupKeyFor(filePath);
    }

    // 一次性把库里已有的同哈希书取回来
    final existing = await bookDao.getBooksByMd5s(
      md5ByPath.values.whereType<String>().toList(),
    );

    // 第二遍：按入参顺序组装结果
    return filePaths.map((filePath) {
      final md5 = md5ByPath[filePath];
      final duplicateBook = md5 == null ? null : existing[md5];
      return ImportFileCheck(
        filePath: filePath,
        md5: md5,
        isDuplicate: duplicateBook != null && !duplicateBook.isDeleted,
        duplicateBook: duplicateBook,
      );
    }).toList();
  }
}
