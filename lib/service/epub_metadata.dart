// lib/service/epub_metadata.dart
//
// 纯 Dart 的 EPUB 元数据解析器（兜底用）。
//
// 背景：导入书籍时，元数据（书名/作者/简介/封面）原本是靠「本地 HTTP server +
// headless WebView 跑 foliate-js」解析的。这条路在老设备上不可靠——
// 实测 Android 10 + 系统 WebView（Chrome 83）上 foliate 加载后不再回调，
// 元数据永远拿不到，导入流程空转到超时，用户看到的就是「导入了但书架没有」。
//
// 这里提供不依赖 WebView / 不依赖 JS 引擎的兜底实现，只用项目已有的 archive 包，
// 直接读 EPUB 的 container.xml → OPF，取 dc:title / dc:creator / dc:description
// 与封面图。EPUB2 的 <meta name="cover">、EPUB3 的 properties="cover-image"
// 以及「文件名带 cover 的图片」三种写法都能识别。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'package:songjiang_reader/utils/log/common.dart';

/// 书籍元数据（字段与 foliate-js 的 onMetadata 对齐）。
class BookMetadata {
  const BookMetadata({
    required this.title,
    this.author = '',
    this.description = '',
    this.cover = '',
  });

  final String title;
  final String author;
  final String description;

  /// data URI（形如 `data:image/jpeg;base64,...`），
  /// 与 `saveImageToLocal` 期望的封面格式一致。
  final String cover;
}

class EpubMetadataExtractor {
  /// 解析文件；失败时退回用文件名当标题，尽量不让导入失败。
  static Future<BookMetadata> extract(File file) async {
    final fallbackTitle = p.basenameWithoutExtension(file.path);
    try {
      final bytes = await file.readAsBytes();
      return fromBytes(bytes, fallbackTitle: fallbackTitle);
    } catch (e) {
      SjLog.warning('EpubMeta: 读取失败，退回文件名当标题: $e');
      return BookMetadata(title: fallbackTitle);
    }
  }

  static BookMetadata fromBytes(
    Uint8List bytes, {
    required String fallbackTitle,
  }) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      SjLog.warning('EpubMeta: 不是有效的 ZIP/EPUB: $e');
      return BookMetadata(title: fallbackTitle);
    }

    final container = _readText(archive, 'META-INF/container.xml');
    final opfPath = container == null
        ? null
        : _firstMatch(container, r'full-path="([^"]+)"');
    if (opfPath == null) {
      SjLog.warning('EpubMeta: slot container.xml 里没有 full-path');
      return BookMetadata(title: fallbackTitle);
    }
    final opf = _readText(archive, opfPath);
    if (opf == null) {
      SjLog.warning('EpubMeta: 读不到 OPF: $opfPath');
      return BookMetadata(title: fallbackTitle);
    }

    final title = _decode(
      _firstMatch(opf, r'<dc:title[^>]*>([\s\S]*?)</dc:title>') ?? '',
    );
    final author = _decode(
      _firstMatch(opf, r'<dc:creator[^>]*>([\s\S]*?)</dc:creator>') ?? '',
    );
    final description = _stripTags(
      _decode(
        _firstMatch(opf, r'<dc:description[^>]*>([\s\S]*?)</dc:description>') ??
            '',
      ),
    );
    final cover = _extractCover(archive, opf, opfPath);

    final finalTitle = title.trim().isEmpty ? fallbackTitle : title.trim();
    SjLog.info(
        'EpubMeta: 解析完成 title=$finalTitle author=${author.trim()} 封面=${cover.isEmpty ? '无' : '有'}');
    return BookMetadata(
      title: finalTitle,
      author: author.trim(),
      description: description.trim(),
      cover: cover,
    );
  }

  // ---- 封面 ----

  static String _extractCover(Archive archive, String opf, String opfPath) {
    String? href;

    // EPUB3: <item ... properties="cover-image" ...>
    for (final m in RegExp(r'<item\b[^>]*>', caseSensitive: false)
        .allMatches(opf)) {
      final tag = m.group(0)!;
      if (!tag.contains('cover-image')) continue;
      href = _firstMatch(tag, r'href="([^"]+)"');
      if (href != null) break;
    }

    // EPUB2: <meta name="cover" content="ID"/> → 找同 id 的 manifest item
    if (href == null) {
      final coverId = _firstMatch(opf, r'<meta\b[^>]*name="cover"[^>]*content="([^"]+)"',
              caseSensitive: false) ??
          _firstMatch(opf, r'<meta\b[^>]*content="([^"]+)"[^>]*name="cover"',
              caseSensitive: false);
      if (coverId != null) {
        final pattern = RegExp(
          '<item\\b[^>]*id="${RegExp.escape(coverId)}"[^>]*>',
          caseSensitive: false,
        );
        final item = pattern.firstMatch(opf);
        if (item != null) href = _firstMatch(item.group(0)!, r'href="([^"]+)"');
      }
    }

    // 兜底：文件名里带 cover 的图片
    if (href == null) {
      for (final m in RegExp(r'<item\b[^>]*>', caseSensitive: false)
          .allMatches(opf)) {
        final tag = m.group(0)!;
        final h = _firstMatch(tag, r'href="([^"]+)"');
        if (h == null || !_isImage(h)) continue;
        if (h.toLowerCase().contains('cover')) {
          href = h;
          break;
        }
      }
    }

    if (href == null) return '';

    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/'))
        : '';
    final raw = Uri.decodeComponent(href);
    final full = opfDir.isEmpty ? raw : '$opfDir/$raw';
    final normalized = _normalize(full);

    final data = _readBytes(archive, normalized);
    if (data == null || data.isEmpty) return '';
    return 'data:${_mimeOf(normalized)};base64,${base64.encode(data)}';
  }

  static bool _isImage(String href) {
    final e = p.extension(href).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}.contains(e);
  }

  static String _mimeOf(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// 去掉 `a/../b` 这类相对路径段。
  static String _normalize(String path) {
    final parts = <String>[];
    for (final seg in path.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    return parts.join('/');
  }

  // ---- ZIP 读取 ----

  static ArchiveFile? _find(Archive archive, String name) {
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == name || f.name.endsWith('/$name')) return f;
    }
    return null;
  }

  static List<int>? _readBytes(Archive archive, String name) {
    final f = _find(archive, name);
    if (f == null) return null;
    final content = f.content;
    if (content == null) return null;
    return content is Uint8List ? content : Uint8List.fromList(content);
  }

  static String? _readText(Archive archive, String name) {
    final bytes = _readBytes(archive, name);
    if (bytes == null) return null;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ---- 文本工具 ----

  static String? _firstMatch(String text, String pattern,
      {bool caseSensitive = true}) {
    final m = RegExp(pattern, caseSensitive: caseSensitive).firstMatch(text);
    return m?.groupCount == 0 ? null : m?.group(1);
  }

  static String _decode(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ');
}
