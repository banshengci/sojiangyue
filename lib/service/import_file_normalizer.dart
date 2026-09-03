import 'dart:io';

import 'package:koni_archive/io.dart';
import 'package:path/path.dart' as p;
import 'package:songjiang_reader/service/book.dart';
import 'package:songjiang_reader/utils/get_path/get_temp_dir.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 导入文件的「路径/扩展名」规范化。
///
/// 背景：安卓上导入的文件路径并不可靠，典型场景有两类：
///
/// 1. 系统分享（`share_handler`）：其安卓实现在拿不到 `_display_name` 时，
///    会用 `MimeTypeMap.getExtensionFromMimeType(mimeType)` 兜底。安卓系统的
///    内置映射表**不认识 epub**，会返回 `null`，最终生成
///    `FILE_1699000000.null` 这样的文件名。
/// 2. 文件选择器（`file_picker`）：部分来源会返回缓存路径，扩展名可能丢失。
///
/// 这两种情况下按扩展名过滤白名单都会被判为「不支持」而**静默丢弃**，
/// 表现就是用户点了导入、书架却没有任何反应。
///
/// 解决办法：不信任路径，改为**按文件内容嗅探真实格式**，
/// 再复制成带正确扩展名的临时文件交给后续导入流程。

/// 读取文件头部若干字节用于格式嗅探。
///
/// 只读前 [size] 字节，避免把几十 MB 的 EPUB 整本读进内存。
List<int> _readHead(String path, int size) {
  final file = File(path);
  final raf = file.openSync(mode: FileMode.read);
  try {
    final len = file.lengthSync();
    final take = len < size ? len : size;
    return raf.readSync(take);
  } finally {
    raf.closeSync();
  }
}

/// ZIP 容器的细分类别。
///
/// EPUB 规范要求 `mimetype` 必须是 ZIP 的第一个条目（且不压缩），
/// 因此它一定落在文件头部，直接在前 1KB 内查找该名字即可与漫画包
/// （CBZ 同为 ZIP 但没有 mimetype 条目）区分开。
///
/// 注意：**ODT 同样要求首条目是 mimetype**，只是内容为
/// `application/vnd.oasis.opendocument.text`。因此必须进一步读取
/// mimetype 的内容，否则 ODT 会被误判成 EPUB，绕过 ODT→EPUB 转换
/// 直接交给引擎解析而失败。
String _sniffZip(List<int> head) {
  // 'mimetype' 的 ASCII 码
  const marker = <int>[0x6D, 0x69, 0x6D, 0x65, 0x74, 0x79, 0x70, 0x65];
  final limit = head.length - marker.length;

  for (var i = 0; i <= limit; i++) {
    var matched = true;
    for (var j = 0; j < marker.length; j++) {
      if (head[i + j] != marker[j]) {
        matched = false;
        break;
      }
    }
    if (!matched) continue;

    // mimetype 条目要求 STORED（不压缩），内容紧跟在条目名之后，
    // 读取其后一小段即可取出真实的 MIME 值。
    final start = i + marker.length;
    final end = start + 128 > head.length ? head.length : start + 128;
    if (end <= start) return 'epub';

    final tail = String.fromCharCodes(head, start, end).toLowerCase();
    if (tail.contains('oasis.opendocument')) return 'odt';
    if (tail.contains('epub')) return 'epub';
    // 有 mimetype 条目但内容无法判断时，按最常见的书籍格式处理
    return 'epub';
  }

  return 'cbz';
}

/// 按文件内容嗅探真实格式，返回不带点的小写扩展名；无法识别时返回 null。
String? sniffExtension(String path) {
  try {
    if (!File(path).existsSync()) return null;
    final head = _readHead(path, 1024);

    // 空文件没有导入意义
    if (head.isEmpty) return null;

    // 过小的文件（不足 4 字节，无法判断魔数）按纯文本处理
    if (head.length < 4) return 'txt';

    // RAR（CBR 漫画）：52 61 72 21 1A 07 (R a r ! \x1a \x07)
    // RAR4 为 `Rar!\x1a\x07\x00`，RAR5 为 `Rar!\x1a\x07\x01\x00`，
    // 两者前 7 字节相同，统一判为 CBR，具体解压交给 koni_archive。
    if (head[0] == 0x52 &&
        head[1] == 0x61 &&
        head[2] == 0x72 &&
        head[3] == 0x21 &&
        head[4] == 0x1A &&
        head[5] == 0x07) {
      return 'cbr';
    }

    // ZIP（EPUB / CBZ / DOCX / ODT 都是 ZIP 容器）：50 4B 03 04
    if (head[0] == 0x50 && head[1] == 0x4B && head[2] == 0x03 && head[3] == 0x04) {
      return _sniffZip(head);
    }

    // PDF：25 50 44 46 (%PDF)
    if (head[0] == 0x25 && head[1] == 0x50 && head[2] == 0x44 && head[3] == 0x46) {
      return 'pdf';
    }

    // RTF：7B 5C 72 74 ({\rt)
    if (head[0] == 0x7B && head[1] == 0x5C && head[2] == 0x72 && head[3] == 0x74) {
      return 'rtf';
    }

    // 其余：不含 NUL 字节的按纯文本处理（TXT / Markdown / HTML 都走这条）
    if (!head.contains(0)) return 'txt';

    return null;
  } catch (e) {
    AnxLog.warning('Import: 嗅探文件格式失败 $path: $e');
    return null;
  }
}

/// 把文件复制为「原名 + 正确扩展名」的临时文件。
Future<File?> _copyWithExtension(
  String src,
  String ext, {
  Directory? tempDir,
}) async {
  try {
    final dir = tempDir ?? await getAnxTempDir();
    var base = p.basenameWithoutExtension(src);
    if (base.isEmpty) base = 'import';
    base = base.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    var targetPath = p.join(dir.path, '$base.$ext');
    var i = 1;
    while (File(targetPath).existsSync()) {
      targetPath = p.join(dir.path, '${base}_${i++}.$ext');
    }

    final copied = await File(src).copy(targetPath);
    AnxLog.info('Import: 已修正扩展名 $src -> ${copied.path}');
    return copied;
  } catch (e) {
    AnxLog.severe('Import: 修正扩展名失败 $src: $e');
    return null;
  }
}

/// 图片扩展名集合（漫画页常见格式）。
const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'avif',
  'tif',
  'tiff',
};

bool _isImageName(String name) {
  final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
  return _imageExtensions.contains(ext);
}

/// 文件名「自然排序」比较器：让 `page2` 排在 `page10` 之前，
/// 保持漫画阅读顺序（否则字典序会把 page10 排到 page2 前面）。
int _naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final aParts = re.allMatches(a).map((m) => m.group(0)!).toList();
  final bParts = re.allMatches(b).map((m) => m.group(0)!).toList();
  final len = aParts.length < bParts.length ? aParts.length : bParts.length;

  for (var i = 0; i < len; i++) {
    final ap = aParts[i];
    final bp = bParts[i];
    final aNum = int.tryParse(ap);
    final bNum = int.tryParse(bp);
    int cmp;
    if (aNum != null && bNum != null) {
      cmp = aNum.compareTo(bNum);
    } else {
      cmp = ap.compareTo(bp);
    }
    if (cmp != 0) return cmp;
  }
  return aParts.length.compareTo(bParts.length);
}

/// 把 CBR（RAR 容器）转换为标准 CBZ（ZIP 容器），供 foliate comic-book 加载器渲染。
///
/// 背景：foliate-js 的 comic-book 加载器只认 ZIP（CBZ），不认 RAR（CBR）。
/// 因此导入 CBR 时，先解压 RAR 中的图片序列、按文件名自然排序，
/// 重打包为 CBZ，再交给已有的漫画渲染链路。
///
/// koni_archive 为纯 Dart 实现（无 FFI / 无原生代码），可读 RAR5/RAR4，
/// 并写出标准 ZIP/CBZ，与本项目「不引入原生依赖」的约束一致。
Future<File?> _convertCbrToCbz(String src, {Directory? tempDir}) async {
  try {
    final dir = tempDir ?? await getAnxTempDir();
    var base = p.basenameWithoutExtension(src);
    if (base.isEmpty) base = 'import';
    base = base.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    var targetPath = p.join(dir.path, '$base.cbz');
    var i = 1;
    while (File(targetPath).existsSync()) {
      targetPath = p.join(dir.path, '${base}_${i++}.cbz');
    }

    final archive = await openArchiveFile(src);
    try {
      // 只保留图片条目，按文件名自然排序以保持漫画页序
      final imageEntries = archive.files
          .where((e) => _isImageName(e.path))
          .toList()
        ..sort((a, b) => _naturalCompare(a.path, b.path));

      if (imageEntries.isEmpty) {
        AnxLog.warning('Import: CBR 内未找到图片条目，跳过：$src');
        return null;
      }

      final writer = await createArchiveFile(
        targetPath,
        format: const ZipWriteFormat(),
      );
      try {
        for (final entry in imageEntries) {
          final bytes = await archive.readBytes(entry, maxSize: 50 << 20);
          await writer.addBytes(
            ArchiveEntrySpec(
              path: entry.path,
              compression: ArchiveCompression.stored,
            ),
            bytes,
          );
        }
        await writer.close();
      } catch (e) {
        // 失败时确保 writer 关闭，避免临时文件残留半截 ZIP
        await writer.close().catchError((_) {});
        rethrow;
      }
    } finally {
      await archive.close();
    }

    AnxLog.info('Import: CBR 已转换为 CBZ：$src -> $targetPath');
    return File(targetPath);
  } catch (e) {
    AnxLog.severe('Import: CBR 转 CBZ 失败 $src: $e');
    return null;
  }
}

/// 规范化导入文件列表。
///
/// - 扩展名已在白名单内：原样保留，不做任何拷贝；
/// - 扩展名缺失或不被支持：按内容嗅探真实格式，复制为带正确扩展名的临时文件；
/// - CBR：RAR 容器不在 foliate 支持范围，解压图片并重打包为 CBZ 后交给漫画渲染链路；
/// - 文件不存在（例如 content:// 这类无法直接读取的 URI）或嗅探失败：跳过并记录日志。
Future<List<File>> normalizeImportFiles(
  List<File> files, {
  Directory? tempDir,
}) async {
  final result = <File>[];

  for (final file in files) {
    final src = file.path;

    if (!File(src).existsSync()) {
      AnxLog.severe('Import: 文件不存在或不可直接读取，跳过：$src');
      continue;
    }

    final ext = p.extension(src).replaceFirst('.', '').toLowerCase();
    if (allowBookExtensions.contains(ext)) {
      result.add(file);
      continue;
    }

    AnxLog.info('Import: 扩展名「$ext」不在白名单，尝试按内容识别：$src');
    final sniffed = sniffExtension(src);
    if (sniffed == null) {
      AnxLog.warning('Import: 无法识别文件格式，跳过：$src');
      continue;
    }

    // CBR 需解压 RAR 并重打包为 CBZ，不能直接复制
    File? fixed;
    if (sniffed == 'cbr') {
      fixed = await _convertCbrToCbz(src, tempDir: tempDir);
    } else {
      fixed = await _copyWithExtension(src, sniffed, tempDir: tempDir);
    }
    if (fixed != null) result.add(fixed);
  }

  return result;
}
