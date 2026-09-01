import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/chapter_draft.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/xml_utils.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 Word (.docx) 文件转换为 EPUB。
///
/// DOCX 本质是 ZIP 包，核心内容在 `word/document.xml`（OOXML）。
/// 这里解析段落/文本/粗体/斜体/下划线/列表/标题，重建为 HTML，
/// 并按 Heading 样式切分为多个章节（生成目录）。仅依赖 `archive`（项目已有）。
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

  final chapters = _buildChapters(xml);
  final htmlChapters = chapters.toHtmlChapters(decodeXmlEntities(title));

  AnxLog.info('Convert: DOCX 转换完成，书名=$title，章节数=${htmlChapters.length}');
  return buildEpubFromHtml(
    title: decodeXmlEntities(title),
    author: decodeXmlEntities(author),
    chapters: htmlChapters,
    tempDir: tempDir,
  );
}

String? _firstGroup(String src, RegExp reg) {
  final m = reg.firstMatch(src);
  return m?.group(1)?.trim();
}

/// 解析 <w:body> 内的段落，按 Heading 样式切分为多个章节。
List<ChapterDraft> _buildChapters(String xml) {
  final bodyMatch =
      RegExp(r'<w:body\b.*?(</w:body>|$)', dotAll: true).firstMatch(xml);
  final bodyXml = bodyMatch?.group(0) ?? xml;

  final paragraphs =
      RegExp(r'<w:p\b.*?</w:p>', dotAll: true).allMatches(bodyXml);

  final blocks = <_Block>[];
  for (final pm in paragraphs) {
    final p = pm.group(0)!;

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
      blocks.add(_Block('h', '<h$headingLevel>$runs</h$headingLevel>',
          level: headingLevel));
    } else if (isList) {
      blocks.add(_Block('li', '<li>$runs</li>'));
    } else {
      blocks.add(_Block('p', '<p>$runs</p>'));
    }
  }

  // 把连续的 <li> 合并进 <ul>
  final merged = <_Block>[];
  var inList = false;
  for (final b in blocks) {
    if (b.kind == 'li') {
      if (!inList) {
        merged.add(_Block('ul_open', '<ul>'));
        inList = true;
      }
      merged.add(b);
    } else {
      if (inList) {
        merged.add(_Block('ul_close', '</ul>'));
        inList = false;
      }
      merged.add(b);
    }
  }
  if (inList) merged.add(_Block('ul_close', '</ul>'));

  // 按标题切分章节
  final chapters = <ChapterDraft>[];
  var current = ChapterDraft(level: 1);
  var hasContent = false;
  for (final b in merged) {
    if (b.kind == 'h') {
      if (hasContent || current.title.isNotEmpty) chapters.add(current);
      current = ChapterDraft(
        title: _stripTags(b.html),
        level: b.level ?? 1,
        html: b.html,
      );
      hasContent = false;
    } else {
      current.html += b.html;
      if (b.kind != 'ul_open' && b.kind != 'ul_close') hasContent = true;
    }
  }
  if (current.html.trim().isNotEmpty ||
      current.title.isNotEmpty ||
      chapters.isEmpty) {
    chapters.add(current);
  }
  return chapters;
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
    final hasBreak = run.contains('<w:br') || run.contains('<w:cr');

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

String _stripTags(String html) =>
    html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&[a-zA-Z]+;', ' ').trim();

class _Block {
  _Block(this.kind, this.html, {this.level});
  final String kind; // 'h' | 'p' | 'li' | 'ul_open' | 'ul_close'
  final String html;
  final int? level;
}
