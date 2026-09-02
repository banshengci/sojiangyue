import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/service/convert_to_epub/create_epub.dart';
import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_docx.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_markdown.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_odt.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_rtf.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/image_embed.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/xhtml_utils.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/service/convert_to_epub/section.dart';

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

List<int> _buildZipWithBytes(Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive)!;
}

/// 统计 EPUB 内 xhtml 章节文件数量（用于验证多章节切分）。
int _chapterCount(File epub) {
  final bytes = epub.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  return archive.files
      .where((f) => f.isFile && RegExp(r'xhtml/\d+\.xhtml$').hasMatch(f.name))
      .length;
}

/// 把 EPUB 内所有章节正文拼接成一个字符串（便于一次性断言多个片段）。
String _chaptersText(File epub) {
  final bytes = epub.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  final buffer = StringBuffer();
  for (final f in archive.files) {
    if (!f.isFile) continue;
    if (!RegExp(r'xhtml/\d+\.xhtml$').hasMatch(f.name)) continue;
    final content = f.content;
    if (content == null) continue;
    final data = (content is Uint8List)
        ? content
        : Uint8List.fromList(content as List<int>);
    buffer.writeln(utf8.decode(data, allowMalformed: true));
  }
  return buffer.toString();
}

/// 在临时目录里放一份主文件 + 若干同名目录的兄弟文件（用于图片内嵌测试）。
File _writeTempWithSiblings(
  String name,
  List<int> bytes,
  Map<String, List<int>> siblings,
) {
  final dir = Directory.systemTemp.createTempSync('songjiang_conv_');
  siblings.forEach((siblingName, data) {
    File('${dir.path}/$siblingName').writeAsBytesSync(data);
  });
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file;
}

/// 1x1 PNG，用于验证图片内嵌。
const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  // 显式注入临时目录：避免走 path_provider 通道（纯 Dart 环境下不可用）。
  final tempDir = Directory.systemTemp.createTempSync('songjiang_epub_');

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
      final epub = await convertDocxToEpub(file, tempDir: tempDir);
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
      final epub = await convertOdtToEpub(file, tempDir: tempDir);
      expect(epub.existsSync(), isTrue);
      expect(_epubContains(epub, 'Hello ODT'), isTrue);
      expect(_epubContains(epub, 'ODT Book'), isTrue);
    });

    test('HTML -> EPUB 切分章节', () async {
      final file = _writeTemp(
          'sample.html',
          utf8.encode('<html><head><title>HTML Book</title></head>'
              '<body><h1>Chapter One</h1><p>Hello HTML</p></body></html>'));
      final epub = await convertHtmlToEpub(file, tempDir: tempDir);
      expect(epub.existsSync(), isTrue);
      expect(_epubContains(epub, 'Hello HTML'), isTrue);
      expect(_epubContains(epub, 'HTML Book'), isTrue);
      // 应生成导航目录
      expect(_epubContains(epub, 'Chapter One'), isTrue);
    });

    test('Markdown -> EPUB 转换粗体', () async {
      final file = _writeTemp('sample.md',
          utf8.encode('# MD Title\n\nHello **Markdown** world.\n\n- item one\n- item two\n'));
      final epub = await convertMarkdownToEpub(file, tempDir: tempDir);
      expect(epub.existsSync(), isTrue);
      expect(_epubContains(epub, 'Hello'), isTrue);
      expect(_epubContains(epub, '<strong>Markdown</strong>'), isTrue);
      expect(_epubContains(epub, '<ul>'), isTrue);
    });

    test('DOCX 多标题切分为多个章节', () async {
      final docx = _buildZip({
        'word/document.xml': '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Chapter A</w:t></w:r></w:p>
    <w:p><w:r><w:t>Body A</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Chapter B</w:t></w:r></w:p>
    <w:p><w:r><w:t>Body B</w:t></w:r></w:p>
  </w:body>
</w:document>''',
      });
      final file = _writeTemp('multi.docx', docx);
      final epub = await convertDocxToEpub(file, tempDir: tempDir);
      expect(_chapterCount(epub), greaterThanOrEqualTo(2));
      expect(_epubContains(epub, 'Chapter A'), isTrue);
      expect(_epubContains(epub, 'Chapter B'), isTrue);
      expect(_epubContains(epub, 'Body A'), isTrue);
    });

    test('RTF -> EPUB 支持粗体/斜体/Unicode/多章节', () async {
      final rtf = utf8.encode('''{\\rtf1\\ansi\\ansicpg1252
{\\stylesheet{\\s1 Heading 1;}{\\s2 Heading 2;}}
\\pard\\s1\\b Hello\\b0 World\\par
\\pard\\s2 This is \\i italic\\i0 text.\\par
\\pard Plain with \\u23383\\par
}''');
      final file = _writeTemp('sample.rtf', rtf);
      final epub = await convertRtfToEpub(file, tempDir: tempDir);
      expect(epub.existsSync(), isTrue);
      expect(epub.path.endsWith('.epub'), isTrue);
      expect(_epubContains(epub, '<strong>Hello</strong>'), isTrue);
      expect(_epubContains(epub, 'World'), isTrue);
      expect(_epubContains(epub, '<em>italic</em>'), isTrue);
      expect(_epubContains(epub, '字'), isTrue); // \\u23383 = U+5B57
      // 两个标题切分为多个章节（末尾无标题正文归入最后一章）
      expect(_chapterCount(epub), greaterThanOrEqualTo(2));
    });

    test('Markdown 支持 front matter / 表格 / 任务列表 / 嵌套列表', () async {
      final file = _writeTemp(
        'full.md',
        utf8.encode('''---
title: 我的书
author: 张三
---

# 第一章

这是**粗体**、*斜体*、~~删除线~~与`代码`。

- 项目一
- 项目二
  - 子项二一
  - 子项二二
- [x] 已完成任务
- [ ] 未完成任务

1. 第一
2. 第二

| 列A | 列B |
|:---|---:|
| 1  | 2  |

> 引用内容

行尾两空格\u0020\u0020
换行了

## 第二章

正文结束。
'''),
      );
      final epub = await convertMarkdownToEpub(file, tempDir: tempDir);
      final text = _chaptersText(epub);

      expect(_epubContains(epub, '我的书'), isTrue);
      expect(_epubContains(epub, '张三'), isTrue);
      expect(text, contains('<strong>粗体</strong>'));
      expect(text, contains('<del>删除线</del>'));
      expect(text, contains('<code>代码</code>'));
      expect(
          text,
          contains(
              '<li>项目二<ul><li>子项二一</li><li>子项二二</li></ul></li>'));
      expect(text, contains('\u2611 已完成任务'));
      expect(text, contains('\u2610 未完成任务'));
      expect(text, contains('<ol><li>第一</li>'));
      expect(text, contains('<th style="text-align:left">列A</th>'));
      expect(text, contains('<th style="text-align:right">列B</th>'));
      expect(text, contains('<td style="text-align:left">1</td>'));
      expect(text, contains('<blockquote><p>引用内容</p></blockquote>'));
      expect(text, contains('行尾两空格<br/>换行了'));
      expect(_chapterCount(epub), 2);
    });

    test('Markdown 内嵌同目录相对路径图片', () async {
      final file = _writeTempWithSiblings(
        'pic.md',
        utf8.encode('# 图\n\n![示意图](pic.png)\n'),
        {'pic.png': base64Decode(_tinyPngBase64)},
      );
      final epub = await convertMarkdownToEpub(file, tempDir: tempDir);
      expect(_chaptersText(epub), contains('src="data:image/png;base64,'));
    });

    test('HTML 提取 meta 作者、内嵌图片并规范化 XHTML', () async {
      final file = _writeTempWithSiblings(
        'page.html',
        utf8.encode('<html><head><title>HTML 书名</title>'
            '<meta name="author" content="李四"></head><body>'
            '<h1>第一章</h1>'
            '<p>空格&nbsp;实体 a & b</p>'
            '<img src="pic.png">'
            '<p>结尾</p>'
            '</body></html>'),
        {'pic.png': base64Decode(_tinyPngBase64)},
      );
      final epub = await convertHtmlToEpub(file, tempDir: tempDir);
      final text = _chaptersText(epub);

      expect(_epubContains(epub, 'HTML 书名'), isTrue);
      expect(_epubContains(epub, '李四'), isTrue);
      // 命名实体必须转成数字引用，否则 XHTML 解析失败
      expect(text, contains('&#160;'));
      // 裸 & 必须转义，未闭合的 img 必须自闭合
      expect(text, contains('a &amp; b'));
      expect(text, contains('<img src="data:image/png;base64,'));
      expect(text, isNot(contains('<img src="pic.png">')));
    });

    test('DOCX 支持表格与有序/无序列表', () async {
      final docx = _buildZipWithBytes({
        'word/document.xml': utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>标题一</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>无序项</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:numId w:val="2"/></w:numPr></w:pPr><w:r><w:t>有序项</w:t></w:r></w:p>
    <w:tbl>
      <w:tr><w:trPr><w:tblHeader/></w:trPr>
        <w:tc><w:p><w:r><w:t>表头A</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>单元格1</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
  </w:body>
</w:document>'''),
        'word/numbering.xml': utf8.encode('''
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>
  <w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>'''),
      });
      final file = _writeTemp('list.docx', docx);
      final epub = await convertDocxToEpub(file, tempDir: tempDir);
      final text = _chaptersText(epub);
      expect(text, contains('<ul><li>无序项</li></ul>'));
      expect(text, contains('<ol><li>有序项</li></ol>'));
      expect(text, contains('<th>表头A</th>'));
      expect(text, contains('<td>单元格1</td>'));
    });

    test('DOCX 内嵌 word/media 内的图片', () async {
      final docx = _buildZipWithBytes({
        'word/document.xml': utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:p><w:r><w:drawing><a:blip r:embed="rId4"/></w:drawing></w:r></w:p>
  </w:body>
</w:document>'''),
        'word/_rels/document.xml.rels': utf8.encode('''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
</Relationships>'''),
        'word/media/image1.png': base64Decode(_tinyPngBase64),
      });
      final file = _writeTemp('image.docx', docx);
      final epub = await convertDocxToEpub(file, tempDir: tempDir);
      expect(_chaptersText(epub), contains('src="data:image/png;base64,'));
    });

    test('XHTML 规范化：void 元素、命名实体、裸 &', () {
      expect(normalizeXhtmlFragment('<p>a<img src="x"></p>'),
          '<p>a<img src="x"/></p>');
      expect(normalizeXhtmlFragment('<br/>'), '<br/>');
      expect(normalizeXhtmlFragment('&nbsp;&mdash;'), '&#160;&#8212;');
      // XML 预定义实体保持原样
      expect(normalizeXhtmlFragment('&amp;&lt;'), '&amp;&lt;');
      expect(normalizeXhtmlFragment('a & b'), 'a &amp; b');
      // 未知实体降级为字面文本，避免 XHTML 解析失败
      expect(normalizeXhtmlFragment('&foobar;'), '&amp;foobar;');
    });

    test('TXT 段落按空行归并、连续行各成一段', () async {
      // 含空行：相邻连续行合并为一个段落
      final withBlanks = await createEpub(
        '书',
        '作者',
        [Section('第一章', '第一行\n第二行\n\n第三行\n第四行', 1)],
        tempDir: tempDir,
      );
      final wb = _chaptersText(withBlanks);
      expect(wb, contains('<p>第一行 第二行</p>'));
      expect(wb, contains('<p>第三行 第四行</p>'));

      // 无空行（连续排版）：每行独立成段
      final noBlanks = await createEpub(
        '书',
        '作者',
        [Section('第一章', '甲\n乙\n丙', 1)],
        tempDir: tempDir,
      );
      final nb = _chaptersText(noBlanks);
      expect(nb, contains('<p>甲</p>'));
      expect(nb, contains('<p>乙</p>'));
      expect(nb, contains('<p>丙</p>'));
    });

    test('RTF 多语言标题（法文 Titre）切分章节', () async {
      // 注意：RTF 按 Latin-1 读取字节，重音字符须用 \'xx 转义；这里用 ASCII 标题验证样式名识别。
      final rtf = utf8.encode('''{\\rtf1\\ansi\\ansicpg1252
{\\stylesheet{\\s1 Titre 1;}{\\s2 Titre 2;}}
\\pard\\s1 Chapitre Un\\par
\\pard Corps A\\par
\\pard\\s2 Sous Section\\par
\\pard Corps B\\par
}''');
      final file = _writeTemp('fr.rtf', rtf);
      final epub = await convertRtfToEpub(file, tempDir: tempDir);
      expect(_chapterCount(epub), greaterThanOrEqualTo(2));
      expect(_epubContains(epub, 'Chapitre Un'), isTrue);
      expect(_epubContains(epub, 'Sous Section'), isTrue);
    });

    test('buildEpubFromHtml 生成封面并声明 cover-image', () async {
      final cover = base64Decode(_tinyPngBase64);
      final epub = await buildEpubFromHtml(
        title: '带封面',
        author: '作者',
        chapters: [HtmlChapter('第一章', '<p>正文</p>', 1)],
        tempDir: tempDir,
        coverBytes: cover,
        coverMime: 'image/png',
      );
      expect(_epubContains(epub, 'id="cover-image"'), isTrue);
      expect(_epubContains(epub, 'properties="cover-image"'), isTrue);
      expect(
          _epubContains(epub, '<meta name="cover" content="cover-image"/>'),
          isTrue);
      final bytes = epub.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.any((f) => f.name == 'OEBPS/cover.png'), isTrue);
    });

    test('DOCX 抽取 word/media 首图作为封面', () async {
      final docx = _buildZipWithBytes({
        'word/document.xml': utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>内容</w:t></w:r></w:p></w:body>
</w:document>'''),
        'word/media/image1.png': base64Decode(_tinyPngBase64),
      });
      final file = _writeTemp('cover.docx', docx);
      final epub = await convertDocxToEpub(file, tempDir: tempDir);
      expect(_epubContains(epub, 'id="cover-image"'), isTrue);
    });

    test('ODT 抽取 Pictures 首图作为封面', () async {
      final odt = _buildZipWithBytes({
        'mimetype': utf8.encode('application/vnd.oasis.opendocument.text'),
        'content.xml': utf8.encode('''
<office:document-content xmlns:office="http://openoffice.org/2000/office" xmlns:text="http://openoffice.org/2000/text">
  <office:body><office:text><text:p>内容</text:p></office:text></office:body>
</office:document-content>'''),
        'Pictures/image1.png': base64Decode(_tinyPngBase64),
      });
      final file = _writeTemp('cover.odt', odt);
      final epub = await convertOdtToEpub(file, tempDir: tempDir);
      expect(_epubContains(epub, 'id="cover-image"'), isTrue);
    });

    test('HTML 抽取首个本地图片作为封面', () async {
      final file = _writeTempWithSiblings(
        'cover.html',
        utf8.encode('<html><head><title>封面书</title></head>'
            '<body><h1>第一章</h1><p>正文</p><img src="pic.png"></body></html>'),
        {'pic.png': base64Decode(_tinyPngBase64)},
      );
      final epub = await convertHtmlToEpub(file, tempDir: tempDir);
      expect(_epubContains(epub, 'id="cover-image"'), isTrue);
    });

    test('image_embed 封面辅助：首个本地图 / 归档首图', () {
      expect(firstLocalImageSrc('<p><img src="a.png"></p><img src="data:x">'),
          'a.png');
      expect(firstLocalImageSrc('<img src="http://x/y.png">'), isNull);
      final archive = ZipDecoder().decodeBytes(_buildZipWithBytes({
        'word/media/pic.png': base64Decode(_tinyPngBase64),
        'word/document.xml': utf8.encode('<x/>'),
      }));
      final img = firstImageInArchive(archive, prefixes: ['word/media/']);
      expect(img, isNotNull);
      final cover = archiveImageCover(img);
      expect(cover, isNotNull);
      expect(cover!.mime, 'image/png');
    });
  });
}
