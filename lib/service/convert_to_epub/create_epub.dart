import 'dart:io';

import 'package:songjiang_reader/service/convert_to_epub/generate_toc.dart';
import 'package:songjiang_reader/service/convert_to_epub/section.dart';
import 'package:songjiang_reader/utils/get_path/get_temp_dir.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:archive/archive_io.dart';
import 'package:uuid/uuid.dart';

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// 去掉行首行尾的半角与全角空格（中文 TXT 常用全角空格缩进）。
String _trimLine(String s) {
  var t = s.trim();
  while (t.startsWith('　')) {
    t = t.substring(1);
  }
  while (t.endsWith('　')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// 把章节纯文本切分为 `<p>` 段落。
///
/// 优先按空行分段：若正文里存在空行间隔，则相邻的连续行视为同一段的回行，
/// 合并成一个 `<p>`（段内以空格连接），更符合小说阅读习惯；
/// 若不存在空行（连续排版的 TXT 小说），则每行作为一个独立段落。
List<String> _buildParagraphs(String content) {
  final hasBlankLineSep = content.contains(RegExp(r'\n[ \t　]*\n'));
  if (hasBlankLineSep) {
    final paragraphs = <String>[];
    for (final block in content.split(RegExp(r'\n[ \t　]*\n'))) {
      final lines = block
          .split('\n')
          .map(_trimLine)
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;
      paragraphs.add('    <p>${_escapeXml(lines.join(' '))}</p>');
    }
    return paragraphs;
  }
  return content
      .split('\n')
      .map(_trimLine)
      .where((line) => line.isNotEmpty)
      .map((line) => '    <p>${_escapeXml(line)}</p>')
      .toList();
}

Future<File> createEpub(
  String titleString,
  String authorString,
  // List<String> chapters,
  List<Section> sections, {
  Directory? tempDir,
}) async {
  // create epub
  final cacheDir = tempDir ?? await getAnxTempDir();
  final epubDir = Directory('${cacheDir.path}/$titleString');
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
  final containerFile = File('${epubDir.path}/META-INF/container.xml');
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

  // content.opf
  final contentFile = File('${oebpsDir.path}/content.opf');
  contentFile.createSync();
  final manifestItems = List.generate(
          sections.length,
          (index) =>
              '    <item id="item$index" href="xhtml/$index.xhtml" media-type="application/xhtml+xml"/>')
      .join('\n');
  final spineItems = List.generate(
          sections.length, (index) => '    <itemref idref="item$index"/>')
      .join('\n');

  contentFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>${_escapeXml(titleString)}</dc:title>
    <dc:creator>${_escapeXml(authorString)}</dc:creator>
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
    <meta name="dtb:totalPageCount" content="${sections.length}"/>
  </head>
  <docTitle>
    <text>${_escapeXml(titleString)}</text>
  </docTitle>
  <navMap>
    ${generateNestedToc(sections)}
  </navMap>
</ncx>''');

  // style.css
  final styleFile = File('${oebpsDir.path}/style.css');
  styleFile.createSync();
  styleFile.writeAsStringSync('''body {

}
''');
  // xhtml
  final xhtmlDir = Directory('${oebpsDir.path}/xhtml');
  xhtmlDir.createSync();
  for (var i = 0; i < sections.length; i++) {
    final xhtmlFile = File('${xhtmlDir.path}/$i.xhtml');
    xhtmlFile.createSync();

    final rawTitle = sections[i].title.trim();
    final level = sections[i].level.clamp(1, 6);
    final content = sections[i].content;

    final heading = rawTitle.isEmpty
        ? ''
        : '    <h$level>${_escapeXml(rawTitle)}</h$level>';

    final paragraphLines = _buildParagraphs(content);

    final bodyBuffer = StringBuffer();
    if (heading.isNotEmpty) {
      bodyBuffer.writeln(heading);
    }
    for (final line in paragraphLines) {
      bodyBuffer.writeln(line);
    }

    final bodyContent = bodyBuffer.toString().trimRight();

    xhtmlFile.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <title>${_escapeXml(rawTitle.isEmpty ? titleString : rawTitle)}</title>
  </head>
  <body>
${bodyContent.isEmpty ? '' : '$bodyContent\n'}
  </body>
</html>''');
  }

  // zip
  final zipFile = File('${cacheDir.path}/$titleString.epub');
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
