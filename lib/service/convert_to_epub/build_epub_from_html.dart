import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:uuid/uuid.dart';

import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/utils/get_path/get_temp_dir.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 创建 EPUB 时使用的临时目录。
/// 传入 [tempDir] 可绕过对 Flutter `path_provider` 的依赖，便于在纯 Dart 环境下测试。
Future<Directory> _resolveTempDir(Directory? tempDir) async =>
    tempDir ?? await getAnxTempDir();

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// 把文件名/目录名中的非法字符替换掉，避免路径出错。
String _safeForPath(String value) =>
    value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').replaceAll('\n', '').trim();

/// 为 [HtmlChapter] 列表生成 EPUB navMap（与 TXT 转换保持相同结构）。
String _generateNestedToc(List<HtmlChapter> chapters) {
  if (chapters.isEmpty) return '';

  final items = List.generate(chapters.length, (index) {
    final ch = chapters[index];
    final title =
        ch.title.trim().isNotEmpty ? ch.title.trim() : 'Section ${index + 1}';
    final level = ch.level < 1 ? 1 : ch.level;
    return _TocItem(title: title, index: index, level: level);
  });

  final positiveLevels = items.map((e) => e.level).toList();
  final baseLevel = positiveLevels.reduce(math.min);
  for (final item in items) {
    item.level = item.level - baseLevel + 1;
  }

  final buffer = StringBuffer();
  final levelStack = <int>[];
  var playOrder = 1;

  String indent(int level) => '  ' * (level + 1);

  for (final item in items) {
    final level = item.level.clamp(1, 6);

    while (levelStack.isNotEmpty && level <= levelStack.last) {
      final closingLevel = levelStack.removeLast();
      buffer.writeln('${indent(closingLevel)}</navPoint>');
    }

    buffer.write(indent(level));
    buffer.writeln(
        '<navPoint id="navPoint-${item.index}" playOrder="$playOrder">');
    buffer.write(indent(level));
    buffer.writeln(
        '  <navLabel><text>${_escapeXml(item.title)}</text></navLabel>');
    buffer.write(indent(level));
    buffer.writeln('  <content src="xhtml/${item.index}.xhtml"/>');
    levelStack.add(level);
    playOrder += 1;
  }

  while (levelStack.isNotEmpty) {
    final closingLevel = levelStack.removeLast();
    buffer.writeln('${indent(closingLevel)}</navPoint>');
  }

  return buffer.toString();
}

/// 用一组「标题 + HTML 正文」章节构建一个合法 EPUB（与 [createEpub] 同构，
/// 但正文是原始 XHTML，不会被转义）。返回临时目录下的 .epub 文件。
Future<File> buildEpubFromHtml({
  required String title,
  required String author,
  required List<HtmlChapter> chapters,
  Directory? tempDir,
}) async {
  final safeTitle = _safeForPath(title.isEmpty ? 'document' : title);
  final cacheDir = await _resolveTempDir(tempDir);
  final epubDir = Directory('${cacheDir.path}/$safeTitle');
  if (epubDir.existsSync()) {
    epubDir.deleteSync(recursive: true);
  }
  epubDir.createSync();

  // mimetype
  final mimetypeFile = File('${epubDir.path}/mimetype');
  mimetypeFile.createSync();
  mimetypeFile.writeAsStringSync('application/epub+zip');

  // META-INF/container.xml
  final metainfDir = Directory('${epubDir.path}/META-INF');
  metainfDir.createSync();
  final containerFile = File('${metainfDir.path}/container.xml');
  containerFile.createSync();
  containerFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');

  // OEBPS
  final oebpsDir = Directory('${epubDir.path}/OEBPS');
  oebpsDir.createSync();

  final safeAuthor = author.isEmpty ? 'Unknown' : author;

  // content.opf
  final contentFile = File('${oebpsDir.path}/content.opf');
  contentFile.createSync();
  final manifestItems = List.generate(
    chapters.length,
    (index) =>
        '    <item id="item$index" href="xhtml/$index.xhtml" media-type="application/xhtml+xml"/>',
  ).join('\n');
  final spineItems = List.generate(
    chapters.length,
    (index) => '    <itemref idref="item$index"/>',
  ).join('\n');

  contentFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>${_escapeXml(safeTitle)}</dc:title>
    <dc:creator>${_escapeXml(safeAuthor)}</dc:creator>
    <dc:identifier id="pub-id">urn:uuid:${const Uuid().v4()}</dc:identifier>
  </metadata>

  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
    $manifestItems
  </manifest>

  <spine toc="ncx">
    $spineItems
  </spine>
</package>''');

  // toc.ncx
  final tocFile = File('${oebpsDir.path}/toc.ncx');
  tocFile.createSync();
  tocFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="zh-CN">
  <head>
    <meta name="dtb:uid" content="urn:uuid:${const Uuid().v4()}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="${chapters.length}"/>
  </head>
  <docTitle>
    <text>${_escapeXml(safeTitle)}</text>
  </docTitle>
  <navMap>
    ${_generateNestedToc(chapters)}
  </navMap>
</ncx>''');

  // style.css
  final styleFile = File('${oebpsDir.path}/style.css');
  styleFile.createSync();
  styleFile.writeAsStringSync('''body {
  line-height: 1.6;
}
img {
  max-width: 100%;
  height: auto;
}
''');

  // xhtml chapters
  final xhtmlDir = Directory('${oebpsDir.path}/xhtml');
  xhtmlDir.createSync();
  for (var i = 0; i < chapters.length; i++) {
    final xhtmlFile = File('${xhtmlDir.path}/$i.xhtml');
    xhtmlFile.createSync();

    final rawTitle = chapters[i].title.trim();
    final bodyContent = chapters[i].html.trim();

    xhtmlFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <title>${_escapeXml(rawTitle.isEmpty ? safeTitle : rawTitle)}</title>
  </head>
  <body>
${bodyContent.isEmpty ? '    <p></p>' : bodyContent}
  </body>
</html>''');
  }

  // zip
  final zipFile = File('${cacheDir.path}/$safeTitle.epub');
  zipFile.createSync();

  try {
    final encoder = ZipFileEncoder();
    encoder.create(zipFile.path);
    await encoder.addFile(mimetypeFile);
    await encoder.addDirectory(metainfDir);
    await encoder.addDirectory(oebpsDir);
    await encoder.close();
  } catch (e) {
    AnxLog.severe('EPUB: ZIP compression failed: $e');
    rethrow;
  }

  epubDir.deleteSync(recursive: true);
  return zipFile;
}

class _TocItem {
  _TocItem({
    required this.title,
    required this.index,
    required this.level,
  });

  final String title;
  final int index;
  int level;
}
