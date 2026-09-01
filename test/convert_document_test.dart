import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/service/convert_to_epub/document/convert_docx.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_markdown.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_odt.dart';

/// 判断 EPUB（ZIP）任意条目是否包含指定文本。
bool _epubContains(File epub, String needle) {
  final bytes = epub.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final content = f.content;
    if (content == null) continue;
    final data =
        (content is Uint8List) ? content : Uint8List.fromList(content as List<int>);
    final text = utf8.decode(data, allowMalformed: true);
    if (text.contains(needle)) return true;
  }
  return false;
}

List<int> _buildZip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    archive.addFile(
        ArchiveFile(name, content.length, utf8.encode(content)));
  });
  return ZipEncoder().encode(archive)!;
}

File _writeTemp(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('songjiang_conv_');
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file;
}

void main() {
  group('文档格式转换', () {
    test('DOCX -> EPUB 保留文本与样式', () async {
      final docx = _buildZip({
        'word/document.xml': '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>My Book</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Hello World</w:t></w:r></w:p>
  </w:body>
</w:document>''',
        'docProps/core.xml': '''
<cp:coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>My Book</dc:title>
  <dc:creator>Tester</dc:creator>
</cp:coreProperties>''',
      });
      final file = _writeTemp('sample.docx', docx);
      final epub = await convertDocxToEpub(file);
      expect(epub.existsSync(), isTrue);
      expect(epub.path.endsWith('.epub'), isTrue);
      expect(_epubContains(epub, 'Hello World'), isTrue);
      expect(_epubContains(epub, 'My Book'), isTrue);
      // 粗体应被转换为 <strong>
      expect(_epubContains(epub, '<strong>'), isTrue);
    });

    test('ODT -> EPUB 保留文本', () async {
      final odt = _buildZip({
        'mimetype': 'application/vnd.oasis.opendocument.text',
        'content.xml': '''
<office:document-content xmlns:office="http://openoffice.org/2000/office" xmlns:text="http://openoffice.org/2000/text">
  <office:body>
    <office:text>
      <text:h text:level="1">ODT Title</text:h>
      <text:p>Hello ODT</text:p>
    </office:text>
  </office:body>
</office:document-content>''',
        'meta.xml': '''
<office:document-meta xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>ODT Book</dc:title>
  <dc:creator>Tester</dc:creator>
</office:document-meta>''',
      });
      final file = _writeTemp('sample.odt', odt);
      final epub = await convertOdtToEpub(file);
      expect(epub.existsSync(), isTrue);
      expect(_epubContains(epub, 'Hello ODT'), isTrue);
      expect(_epubContains(epub, 'ODT Book'), isTrue);
    });

    test('HTML -> EPUB 切分章节', () async {
      final file = _writeTemp(
          'sample.html',
          utf8.encode('<html><head><title>HTML Book</title></head>'
              '<body><h1>Chapter One</h1><p>Hello HTML</p></body></html>'));
      final epub = await convertHtmlToEpub(file);
      expect(epub.existsSync(), isTrue);
      expect(_epubContains(epub, 'Hello HTML'), isTrue);
      expect(_epubContains(epub, 'HTML Book'), isTrue);
      // 应生成导航目录
      expect(_epubContains(epub, 'Chapter One'), isTrue);
    });

    test('Markdown -> EPUB 转换粗体', () async {
      final file = _writeTemp('sample.md',
          utf8.encode('# MD Title\n\nHello **Markdown** world.\n\n- item one\n- item two\n'));
      final epub = await convertMarkdownToEpub(file);
      expect(epub.existsSync(), isTrue);
      expect(_epubContains(epub, 'Hello'), isTrue);
      expect(_epubContains(epub, '<strong>Markdown</strong>'), isTrue);
      expect(_epubContains(epub, '<ul>'), isTrue);
    });
  });
}
