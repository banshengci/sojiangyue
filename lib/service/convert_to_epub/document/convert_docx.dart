import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/xml_utils.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 Word (.docx) 文件转换为 EPUB。
///
/// DOCX 本质是 ZIP 包，核心内容在 `word/document.xml`（OOXML）。
/// 这里解析段落/文本/粗体/斜体/下划线/列表/标题，重建为 HTML。
/// 仅依赖 `archive`（项目已有），不引入新依赖。
Future<File> convertDocxToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  final bytes = file.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  final docFile = findArchiveFile(archive, 'word/document.xml');
  if (docFile == null) {
    throw Exception('Convert: 不是有效的 DOCX 文件（缺少 word/document.xml）');
  }
  final xml = readArchiveFileUtf8(docFile);

  String title = filename;
  String author = 'Unknown';
  final core = findArchiveFile(archive, 'docProps/core.xml');
  if (core != null) {
    final coreXml = readArchiveFileUtf8(core);
    title = _firstGroup(coreXml, RegExp(r'<dc:title>([^<]*)</dc:title>')) ??
        filename;
    author = _firstGroup(coreXml, RegExp(r'<dc:creator>([^<]*)</dc:creator>')) ??
        'Unknown';
  }

  final body = _buildHtml(xml);

  AnxLog.info('Convert: DOCX 转换完成，书名=$title');
  return buildEpubFromHtml(
    title: decodeXmlEntities(title),
    author: decodeXmlEntities(author),
    chapters: [HtmlChapter(decodeXmlEntities(title), body)],
    tempDir: tempDir,
  );
}

String? _firstGroup(String src, RegExp reg) {
  final m = reg.firstMatch(src);
  return m?.group(1)?.trim();
}

String _buildHtml(String xml) {
  // 仅取 <w:body> 内的内容
  final bodyMatch = RegExp(r'<w:body\b.*?(</w:body>|$)', dotAll: true)
      .firstMatch(xml);
  final bodyXml = bodyMatch?.group(0) ?? xml;

  final paragraphs =
      RegExp(r'<w:p\b.*?</w:p>', dotAll: true).allMatches(bodyXml);
  final parts = <_Para>[];

  for (final pm in paragraphs) {
    final p = pm.group(0)!;

    // 标题层级：<w:pStyle w:val="Heading1"/> 等
    int? headingLevel;
    final styleVal =
        _firstGroup(p, RegExp(r'<w:pStyle[^>]*w:val="([^"]*)"'));
    if (styleVal != null) {
      final hm = RegExp(r'Heading(\d)').firstMatch(styleVal);
      if (hm != null) headingLevel = int.parse(hm.group(1)!);
    }

    final isList = p.contains('<w:numPr');

    final runs = _parseRuns(p);
    if (runs.trim().isEmpty && headingLevel == null) {
      // 空段落跳过（列表项除外，避免破坏 <ul> 结构）
      if (!isList) continue;
    }

    if (headingLevel != null) {
      parts.add(_Para('h', '<h$headingLevel>$runs</h$headingLevel>'));
    } else if (isList) {
      parts.add(_Para('li', '<li>$runs</li>'));
    } else {
      parts.add(_Para('p', '<p>$runs</p>'));
    }
  }

  // 把连续的 <li> 合并进 <ul>
  final out = StringBuffer();
  var inList = false;
  for (final part in parts) {
    if (part.kind == 'li') {
      if (!inList) {
        out.write('<ul>');
        inList = true;
      }
      out.write(part.html);
    } else {
      if (inList) {
        out.write('</ul>');
        inList = false;
      }
      out.write(part.html);
    }
  }
  if (inList) out.write('</ul>');

  final result = out.toString().trim();
  return result.isEmpty ? '<p></p>' : result;
}

String _parseRuns(String paragraphXml) {
  final runMatches =
      RegExp(r'<w:r\b.*?</w:r>', dotAll: true).allMatches(paragraphXml);
  final buffer = StringBuffer();

  for (final rm in runMatches) {
    final run = rm.group(0)!;

    final bold = RegExp(r'<w:rPr>.*?<w:b\b', dotAll: true).hasMatch(run);
    final italic = RegExp(r'<w:rPr>.*?<w:i\b', dotAll: true).hasMatch(run);
    final underline = RegExp(r'<w:rPr>.*?<w:u\b', dotAll: true).hasMatch(run);

    // 文本：<w:t> 以及 <w:tab/>、<w:br/>、<w:cr/>
    final texts = <String>[];
    for (final tm in RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true)
        .allMatches(run)) {
      texts.add(decodeXmlEntities(tm.group(1) ?? ''));
    }
    final hasTab = run.contains('<w:tab');
    final hasBreak =
        run.contains('<w:br') || run.contains('<w:cr');

    var text = texts.join('');
    if (hasTab) text = '\t$text';
    if (hasBreak) text = '$text\n';

    if (text.isEmpty && !bold && !italic && !underline) continue;

    var wrapped = escapeHtmlText(text);
    if (underline) wrapped = '<u>$wrapped</u>';
    if (italic) wrapped = '<em>$wrapped</em>';
    if (bold) wrapped = '<strong>$wrapped</strong>';

    buffer.write(wrapped);
  }

  return buffer.toString();
}

class _Para {
  _Para(this.kind, this.html);
  final String kind; // 'h' | 'p' | 'li'
  final String html;
}
