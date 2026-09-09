import 'dart:io';

import 'package:flutter/foundation.dart';
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
/// 中文网文常见两种排版：
/// 1. 几乎无空行，每行即一段（硬段）——按行切 `<p>`；
/// 2. 有空行分段，段内可能软换行——按空行切块；块内若以全角/半角空格缩进
///    则缩进行视为新段，否则整块并为一段。
@visibleForTesting
List<String> buildEpubParagraphs(String content) {
  final lines = content.split('\n');
  final nonEmptyCount = lines.where((l) => l.trim().isNotEmpty).length;
  final blankCount = lines.length - nonEmptyCount;
  final blankRatio = lines.isEmpty ? 0.0 : blankCount / lines.length;

  // 空行极少：视为每行一段（网文硬换行）
  if (blankRatio < 0.08) {
    return lines
        .map(_trimLine)
        .where((line) => line.isNotEmpty)
        .map((line) => '    <p>${_escapeXml(line)}</p>')
        .toList();
  }

  final paragraphs = <String>[];
  for (final block in content.split(RegExp(r'\n[ \t　]*\n'))) {
    final rawLines = block.split('\n');
    final List<String> current = [];
    void flush() {
      if (current.isEmpty) return;
      paragraphs.add('    <p>${_escapeXml(current.join(' '))}</p>');
      current.clear();
    }

    for (final raw in rawLines) {
      final line = raw.replaceAll('　', ' ').trim();
      if (line.isEmpty) continue;
      // 全角空格 / 多个半角空格缩进 → 新段
      final wasIndented = raw.startsWith('　') ||
          raw.startsWith('  ') ||
          raw.startsWith('\t');
      if (wasIndented) {
        flush();
      }
      current.add(line);
    }
    flush();
  }
  return paragraphs;
}

Future<File> createEpub(
  String titleString,
  String authorString,
  // List<String> chapters,
  List<Section> sections, {
  Directory? tempDir,
}) async {
  // create epub
  final cacheDir = tempDir ?? await getSjTempDir();
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
  margin: 0;
  padding: 0;
}
p {
  margin: 0.45em 0;
  text-indent: 0;
}
h1, h2, h3, h4, h5, h6 {
  margin: 0.6em 0 0.4em;
  line-height: 1.4;
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

    final paragraphLines = buildEpubParagraphs(content);

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
    SjLog.severe('EPUB: ZIP compression failed: $e');
    rethrow;
  }

  epubDir.deleteSync(recursive: true);
  return zipFile;
}
