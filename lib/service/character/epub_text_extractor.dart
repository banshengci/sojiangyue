// lib/service/character/epub_text_extractor.dart
//
// 从 EPUB 文件中抽取章节纯文本，供人物蒸馏使用。
// 仅依赖项目已有的 `archive` 包（与 convert_to_epub 同源 API：
// ZipDecoder().decodeBytes / findArchiveFile / readArchiveFileUtf8）。
// EPUB 内部结构（META-INF/container.xml → content.opf 的 manifest/spine）
// 用轻量正则解析，不引入额外 XML/HTML 依赖，避免重量级解析库。
//
// 章节标题：优先从导航文档解析真实标题——EPUB3 的 nav.xhtml
// （epub:type="toc"）或 EPUB2 的 toc.ncx（<navMap>）。解析失败时回退为
// 文件名（_chapterTitle），保证不破坏既有行为。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 在 ZIP 归档中按文件名（允许前导路径）查找文件。
ArchiveFile? _findArchiveFile(Archive archive, String name) {
  for (final f in archive.files) {
    if (!f.isFile) continue;
    if (f.name == name || f.name.endsWith('/$name')) return f;
  }
  return null;
}

/// 以 UTF-8（兼容 BOM / 容错）读取归档内文本文件。
String _readArchiveFileUtf8(ArchiveFile file) {
  final content = file.content;
  if (content == null) return '';
  final bytes =
      (content is Uint8List) ? content : Uint8List.fromList(content as List<int>);
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// 解码 XML / 常见 HTML 实体；无法识别的命名实体直接剥离，避免污染文本。
String _decodeEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&hellip;', '…')
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&lsquo;', '‘')
    .replaceAll('&rsquo;', '’')
    .replaceAll('&ldquo;', '“')
    .replaceAll('&rdquo;', '”')
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll(RegExp(r'&[a-zA-Z]+;'), '');

/// 把 XHTML/HTML 正文清洗为纯文本（保留段间换行）。
String _xhtmlToText(String html) {
  var s = html;
  // 去掉 head / script / style 块（含其内全部内容）
  s = s.replaceAllMapped(
    RegExp(r'<(head|script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
    (_) => '',
  );
  // 块级闭合标签 → 换行
  s = s.replaceAllMapped(
    RegExp(r'</(p|div|section|li|h[1-6]|tr|br)\b[^>]*>', caseSensitive: false),
    (_) => '\n',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  // 剥离剩余标签
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  // 实体解码
  s = _decodeEntities(s);
  // 合并多余空白
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n[ \t]+'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// 退化标题：当导航文档缺失或解析失败时，用文件名兜底。
String _chapterTitle(String href) {
  final name = href.split('/').last;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  return Uri.decodeComponent(base);
}

/// 从 META-INF/container.xml 取出 OPF 路径。
String? _extractOpfPath(String containerXml) {
  final m = RegExp(r'full-path="([^"]+)"').firstMatch(containerXml);
  return m?.group(1);
}

/// 在 OPF manifest 中定位导航文档：
/// 优先 EPUB3 的 `properties="nav"`（nav.xhtml），回退到 EPUB2 的
/// `media-type="application/x-dtbncx+xml"`（toc.ncx）。
String? _findNavHref(String opfXml) {
  // href 在前、properties 在后
  final a = RegExp(
    r'<item\b[^>]*\bhref="([^"]+)"[^>]*\bproperties="([^"]*)"',
    caseSensitive: false,
  ).firstMatch(opfXml);
  if (a != null && a.group(2)!.contains('nav')) return a.group(1);
  // properties 在前、href 在后
  final b = RegExp(
    r'<item\b[^>]*\bproperties="([^"]*)"[^>]*\bhref="([^"]+)"',
    caseSensitive: false,
  ).firstMatch(opfXml);
  if (b != null && b.group(1)!.contains('nav')) return b.group(2);
  // EPUB2 toc.ncx（href 在前）
  final c = RegExp(
    r'<item\b[^>]*\bhref="([^"]+)"[^>]*\bmedia-type="application/x-dtbncx\+xml"',
    caseSensitive: false,
  ).firstMatch(opfXml);
  if (c != null) return c.group(1);
  // EPUB2 toc.ncx（media-type 在前）
  final d = RegExp(
    r'<item\b[^>]*\bmedia-type="application/x-dtbncx\+xml"[^>]*\bhref="([^"]+)"',
    caseSensitive: false,
  ).firstMatch(opfXml);
  if (d != null) return d.group(1);
  return null;
}

/// EPUB3 导航：解析 `<nav epub:type="toc">` 下的 `<a href>标题</a>`。
///
/// 优先只取目录 nav 块；找不到 `epub:type="toc"` 时回退为整文档的所有
/// `<a href>`（best-effort）。返回 raw href（未规范化）到标题的映射。
Map<String, String> _extractNavXhtmlTitles(String navXml) {
  final map = <String, String>{};
  final tocBlock = RegExp(
    r'<nav\b[^>]*epub:type="toc"[^>]*>([\s\S]*?)</nav>',
    caseSensitive: false,
  ).firstMatch(navXml);
  final scope = tocBlock?.group(1) ?? navXml;

  final aRe = RegExp(
    r'<a\b[^>]*\bhref="([^"]+)"[^>]*>([\s\S]*?)</a>',
    caseSensitive: false,
  );
  for (final m in aRe.allMatches(scope)) {
    final href = m.group(1)!;
    if (href.startsWith('#')) continue; // 跳过页内锚点（页码/landmarks）
    final title = _decodeEntities(
      m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ' '),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isNotEmpty) map[href] = title;
  }
  return map;
}

/// EPUB2 导航：解析 toc.ncx 的
/// `<navPoint><navLabel><text>标题</text></navLabel><content src="href"/>
/// </navPoint>`。
///
/// 采用「content 向前取最近 `<text>`」的启发式：标准 ncx 规范里 navLabel
/// 总在 content 之前，对嵌套 navPoint（子章节）同样成立——父 content 前最近
/// 的 text 是其 navLabel，子 content 前最近的 text 是其 navLabel。
Map<String, String> _extractNcxTitles(String ncxXml) {
  final map = <String, String>{};
  final textRe = RegExp(r'<text>([\s\S]*?)</text>', caseSensitive: false);
  final textSpans = textRe.allMatches(ncxXml).toList();
  final contentRe = RegExp(
    r'<content\b[^>]*\bsrc="([^"]+)"',
    caseSensitive: false,
  );

  for (final cm in contentRe.allMatches(ncxXml)) {
    final src = cm.group(1)!;
    if (src.startsWith('#')) continue;
    String? title;
    for (final tm in textSpans) {
      if (tm.start < cm.start) {
        title = _decodeEntities(
          tm.group(1)!.replaceAll(RegExp(r'<[^>]+>'), ' '),
        ).replaceAll(RegExp(r'\s+'), ' ').trim();
      } else {
        break; // textSpans 有序，之后都不在 content 之前
      }
    }
    if (title != null && title.isNotEmpty) map[src] = title;
  }
  return map;
}

/// 解析导航文档，返回「章节文件名末段（小写，已解码）→ 真实标题」映射。
///
/// 该映射用于覆盖 `_chapterTitle` 的文件名兜底标题，使蒸馏拿到的章节标题
/// 形如「第一回 甄士隐梦幻识通灵」而非「part001.xhtml」。
Map<String, String> _extractNavTitles(
  Archive archive,
  String opfXml,
  String opfDir,
) {
  final navHref = _findNavHref(opfXml);
  if (navHref == null) return const {};
  final navFile = _findArchiveFile(archive, opfDir + navHref) ??
      _findArchiveFile(archive, Uri.decodeComponent(opfDir + navHref));
  if (navFile == null) return const {};

  final navXml = _readArchiveFileUtf8(navFile);
  final isNcx = navXml.contains('<ncx') || navXml.contains('<navMap');
  final raw = isNcx
      ? _extractNcxTitles(navXml)
      : _extractNavXhtmlTitles(navXml);

  final map = <String, String>{};
  for (final e in raw.entries) {
    final clean = e.key.split('#').first;
    final key = Uri.decodeComponent(clean.split('/').last).toLowerCase();
    if (key.isNotEmpty && e.value.trim().isNotEmpty) {
      map[key] = e.value.trim();
    }
  }
  return map;
}

/// 给定 epub 文件路径，返回按阅读顺序排列的章节（标题 + 纯文本）。
///
/// 解析链：META-INF/container.xml → content.opf 的 <manifest>(href) 与
/// <spine>(idref 顺序) → 依次读取每个 XHTML 章节并清洗为纯文本。
/// 若 OPF 无 spine，则退化为按 manifest 顺序读取全部 XHTML。
/// 章节标题优先取导航文档真实标题，缺失时回退文件名。
Future<List<BookChapter>> extractEpubChapters(String epubPath) async {
  final file = File(epubPath);
  if (!file.existsSync()) {
    throw StateError('EPUB 文件不存在: $epubPath');
  }
  final bytes = await file.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  final container = _findArchiveFile(archive, 'META-INF/container.xml');
  if (container == null) {
    throw StateError('非标准 EPUB：缺少 META-INF/container.xml');
  }
  final opfPath = _extractOpfPath(_readArchiveFileUtf8(container));
  if (opfPath == null || opfPath.isEmpty) {
    throw StateError('无法从 container.xml 解析 OPF 路径');
  }
  final opfDir = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';

  final opfFile = _findArchiveFile(archive, opfPath);
  if (opfFile == null) {
    throw StateError('OPF 文件缺失: $opfPath');
  }
  final opfXml = _readArchiveFileUtf8(opfFile);

  // manifest: <item id="x" href="a.xhtml" .../>
  final manifest = <String, String>{};
  final itemRe = RegExp(
    r'<item\b[^>]*\bid="([^"]+)"[^>]*\bhref="([^"]+)"',
    caseSensitive: false,
  );
  for (final m in itemRe.allMatches(opfXml)) {
    manifest[m.group(1)!] = m.group(2)!;
  }

  // spine: <itemref idref="x"/>（决定阅读顺序）
  final spine = <String>[];
  final spineRe = RegExp(
    r'<itemref\b[^>]*\bidref="([^"]+)"',
    caseSensitive: false,
  );
  for (final m in spineRe.allMatches(opfXml)) {
    spine.add(m.group(1)!);
  }

  final orderedHrefs = spine.isNotEmpty
      ? spine
          .where((id) => manifest.containsKey(id))
          .map((id) => manifest[id]!)
          .toList()
      : manifest.values.where((h) => _isReadableContent(h)).toList();

  // 导航文档真实标题（覆盖文件名兜底）
  final navTitles = _extractNavTitles(archive, opfXml, opfDir);

  final chapters = <BookChapter>[];
  for (final href in orderedHrefs) {
    final fullName = opfDir + href;
    final xhtml = _findArchiveFile(archive, fullName) ??
        _findArchiveFile(archive, Uri.decodeComponent(fullName));
    if (xhtml == null) continue;
    final rawXhtml = _readArchiveFileUtf8(xhtml);
    final text = _xhtmlToText(rawXhtml);
    if (text.isEmpty) continue;

    final baseHref = href.split('#').first;
    final key = Uri.decodeComponent(baseHref.split('/').last).toLowerCase();
    final title = navTitles[key] ??
        _extractFirstHeading(rawXhtml) ??
        _chapterTitle(href);
    chapters.add(BookChapter(title: title, text: text));
  }

  if (chapters.isEmpty) {
    throw StateError('EPUB 未解析出任何正文章节');
  }
  SjLog.info('EpubTextExtractor: 切出 ${chapters.length} 章'
      '（其中 ${navTitles.length} 个命中导航标题）');
  return chapters;
}

/// 兜底标题：当导航文档缺失或某章节未命中时，取 XHTML 正文第一个
/// <h1>/<h2>/<h3> 的文本内容。很多网文 EPUB 没有正式 nav，但章节开头常以
/// 标题起头；找不到时返回 null，由调用方回退到文件名。
String? _extractFirstHeading(String xhtml) {
  final m = RegExp(
    r'<h([1-3])\b[^>]*>([\s\S]*?)</h\1>',
    caseSensitive: false,
  ).firstMatch(xhtml);
  if (m == null) return null;
  final t = _decodeEntities(
    m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ' '),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? null : t;
}

/// 退化模式下，只取 XHTML/HTML 正文（排除 css/ncx/img/svg 等资源）。
bool _isReadableContent(String href) {
  final lower = href.toLowerCase();
  if (lower.endsWith('.css') ||
      lower.endsWith('.ncx') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.svg')) {
    return false;
  }
  return lower.endsWith('.xhtml') ||
      lower.endsWith('.html') ||
      lower.endsWith('.htm');
}
