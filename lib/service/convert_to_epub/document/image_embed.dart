import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/document/xml_utils.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 单张图片内嵌的大小上限。
///
/// 超过该大小的图片会被跳过（保留空 src），避免转换出的 EPUB 体积失控。
const int maxEmbedImageBytes = 5 * 1024 * 1024;

/// 按扩展名猜测 MIME 类型；未知类型返回 null（调用方应跳过内嵌）。
String? guessMimeType(String filePath) {
  switch (path.extension(filePath).toLowerCase().replaceFirst('.', '')) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
    case 'jpe':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'svg':
      return 'image/svg+xml';
    case 'bmp':
      return 'image/bmp';
    case 'ico':
      return 'image/x-icon';
    case 'tif':
    case 'tiff':
      return 'image/tiff';
    default:
      return null;
  }
}

/// 把字节数据编码为 data URI。
String toDataUri(List<int> bytes, String mimeType) =>
    'data:$mimeType;base64,${base64Encode(bytes)}';

/// 判断图片地址是否无需处理（远程地址或已经是 data URI）。
bool _isRemoteOrData(String src) {
  final s = src.trim().toLowerCase();
  return s.startsWith('data:') ||
      s.startsWith('http://') ||
      s.startsWith('https://') ||
      s.startsWith('//');
}

/// 把可能是百分号编码的路径还原为普通路径（失败时返回原值）。
String _decodeUriPath(String src) {
  if (!src.contains('%')) return src;
  try {
    return Uri.decodeComponent(src);
  } catch (_) {
    return src;
  }
}

/// 把 HTML 中指向本地相对路径的图片内嵌为 base64 data URI。
///
/// [baseDir] 是原始文档所在目录，用于解析相对路径。
/// 远程图片与 data URI 原样保留；无法解析的图片会置空 src，
/// 避免生成指向不存在资源的 EPUB。
String embedLocalImages(String html, Directory baseDir) {
  if (!html.contains('<img')) return html;
  return html.replaceAllMapped(
      RegExp(r'''(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2''',
          caseSensitive: false, dotAll: true), (m) {
    final src = m.group(3) ?? '';
    if (src.trim().isEmpty || _isRemoteOrData(src)) return m.group(0)!;

    final candidate = _decodeUriPath(src.trim());
    final resolved = candidate.startsWith('file:')
        ? _fileUriToPath(candidate)
        : path.normalize(path.join(baseDir.path, candidate));

    if (resolved == null) {
      return '${m.group(1)}${m.group(2)}${m.group(2)}';
    }
    final dataUri = _readAsDataUri(resolved, () {
      final imageFile = File(resolved);
      return imageFile.existsSync() ? imageFile.readAsBytesSync() : null;
    });
    if (dataUri == null) {
      SjLog.info('Convert: 图片无法内嵌（跳过）：$src');
      return '${m.group(1)}${m.group(2)}${m.group(2)}';
    }
    return '${m.group(1)}${m.group(2)}$dataUri${m.group(2)}';
  });
}

/// 把 HTML 中指向 ZIP 归档内图片的相对路径内嵌为 base64 data URI。
///
/// 用于 DOCX（word/media/*）与 ODT（Pictures/*）等基于 ZIP 的文档格式。
String embedArchiveImages(String html, Archive archive) {
  if (!html.contains('<img')) return html;
  return html.replaceAllMapped(
      RegExp(r'''(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2''',
          caseSensitive: false, dotAll: true), (m) {
    final src = m.group(3) ?? '';
    if (src.trim().isEmpty || _isRemoteOrData(src)) return m.group(0)!;

    final target = _normalizeArchivePath(_decodeUriPath(src.trim()));
    final found = findArchiveFile(archive, target);
    if (found == null) {
      SjLog.info('Convert: 归档内找不到图片：$src');
      return '${m.group(1)}${m.group(2)}${m.group(2)}';
    }
    final dataUri =
        _readAsDataUri(found.name, () => found.content as List<int>?);
    if (dataUri == null) {
      return '${m.group(1)}${m.group(2)}${m.group(2)}';
    }
    return '${m.group(1)}${m.group(2)}$dataUri${m.group(2)}';
  });
}

/// 规范化归档内路径：去掉 `./`、折叠 `../`、去除前导 `/`。
String _normalizeArchivePath(String raw) {
  final segments = raw.replaceAll('\\', '/').split('/');
  final stack = <String>[];
  for (final seg in segments) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (stack.isNotEmpty) stack.removeLast();
      continue;
    }
    stack.add(seg);
  }
  return stack.join('/');
}

String? _fileUriToPath(String uri) {
  try {
    return File.fromUri(Uri.parse(uri)).path;
  } catch (_) {
    return null;
  }
}

/// 读取图片字节并转成 data URI；超限、缺失或类型不支持时返回 null。
String? _readAsDataUri(String forMime, List<int>? Function() read) {
  final mime = guessMimeType(forMime);
  if (mime == null) return null;
  final bytes = read();
  if (bytes == null || bytes.isEmpty) return null;
  if (bytes.length > maxEmbedImageBytes) {
    SjLog.warning('Convert: 图片过大（${bytes.length} 字节），跳过内嵌：$forMime');
    return null;
  }
  return toDataUri(bytes, mime);
}

/// 取 HTML 中第一个「本地相对路径」图片的 src。
///
/// 远程地址（http/https）、data URI 与空 src 会被跳过；
/// 返回的 src 未经路径还原（调用方自行处理百分号编码与路径拼接）。
String? firstLocalImageSrc(String html) {
  if (!html.contains('<img')) return null;
  final m = RegExp(r'''(<img\b[^>]*?\bsrc\s*=\s*["'])(.*?)["']''',
          caseSensitive: false, dotAll: true)
      .firstMatch(html);
  if (m == null) return null;
  final src = m.group(2) ?? '';
  if (src.trim().isEmpty) return null;
  if (_isRemoteOrData(src)) return null;
  return src.trim();
}

/// 读取本地相对路径图片的字节；路径不存在或类型不支持时返回 null。
List<int>? readLocalImageBytes(Directory baseDir, String src) {
  final candidate = _decodeUriPath(src.trim());
  final resolved = candidate.startsWith('file:')
      ? _fileUriToPath(candidate)
      : path.normalize(path.join(baseDir.path, candidate));
  if (resolved == null) return null;
  final file = File(resolved);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  if (bytes.length > maxEmbedImageBytes) {
    SjLog.warning('Convert: 封面图片过大（${bytes.length} 字节），跳过：$src');
    return null;
  }
  return bytes;
}

/// 在 ZIP 归档的多个候选前缀下找到第一个图片文件。
///
/// 用于 DOCX（`word/media/`）与 ODT（`Pictures/`）等基于 ZIP 的文档，
/// 抽取首张图片作为书籍封面。返回 null 表示无封面图片。
ArchiveFile? firstImageInArchive(Archive archive, {List<String> prefixes = const ['word/media/']}) {
  const imageExt = {
    'png',
    'jpg',
    'jpeg',
    'jpe',
    'gif',
    'webp',
    'bmp',
    'svg',
    'tif',
    'tiff',
  };
  final lowerPrefixes = prefixes.map((p) => p.toLowerCase()).toList();
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.toLowerCase().replaceAll('\\', '/');
    if (!lowerPrefixes.any((p) => name.startsWith(p))) continue;
    final ext = path.extension(name).toLowerCase().replaceFirst('.', '');
    if (!imageExt.contains(ext)) continue;
    return f;
  }
  return null;
}

/// 把归档图片文件转成（字节 + MIME）封面数据；不可用时返回 null。
({List<int> bytes, String mime})? archiveImageCover(ArchiveFile? file) {
  if (file == null) return null;
  final mime = guessMimeType(file.name);
  if (mime == null) return null;
  final bytes = file.content;
  if (bytes == null || bytes.isEmpty || bytes.length > maxEmbedImageBytes) {
    return null;
  }
  return (bytes: List<int>.from(bytes), mime: mime);
}
