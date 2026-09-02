import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/chapter_draft.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/image_embed.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/xml_utils.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 Word (.docx) 文件转换为 EPUB。
///
/// DOCX 本质是 ZIP 包，核心内容在 `word/document.xml`（OOXML）。
/// 支持段落/表格/图片/粗体/斜体/下划线/有序与无序列表，
/// 并按 Heading 样式（或 `outlineLvl`）切分为多个章节生成目录。
/// 仅依赖 `archive`（项目已有）。
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

  final rels = _parseImageRelations(archive);
  final numbering = _parseNumbering(archive);

  final chapters = _buildChapters(xml, rels: rels, numbering: numbering);
  final htmlChapters = chapters
      .toHtmlChapters(decodeXmlEntities(title))
      .map((c) => c.copyWith(html: embedArchiveImages(c.html, archive)))
      .toList();

  // 抽取首张图片作为封面（word/media/*），提升书架观感
  final cover = archiveImageCover(
      firstImageInArchive(archive, prefixes: const ['word/media/']));

  AnxLog.info('Convert: DOCX 转换完成，书名=$title，章节数=${htmlChapters.length}');
  return buildEpubFromHtml(
    title: decodeXmlEntities(title),
    author: decodeXmlEntities(author),
    chapters: htmlChapters,
    tempDir: tempDir,
    coverBytes: cover?.bytes,
    coverMime: cover?.mime,
  );
}

/// 解析 `word/_rels/document.xml.rels`：关系 Id → 包内图片路径。
///
/// 只保留指向包内资源的图片关系（跳过 External 外链图片）。
Map<String, String> _parseImageRelations(Archive archive) {
  final relsFile = findArchiveFile(archive, 'word/_rels/document.xml.rels');
  if (relsFile == null) return const {};

  final xml = readArchiveFileUtf8(relsFile);
  final map = <String, String>{};
  final pattern = RegExp(r'<Relationship\b[^>]*>', dotAll: true);
  for (final m in pattern.allMatches(xml)) {
    final tag = m.group(0)!;
    if (tag.contains('TargetMode="External"')) continue;
    final id = _firstGroup(tag, RegExp(r'\bId="([^"]*)"'));
    final type = _firstGroup(tag, RegExp(r'\bType="([^"]*)"'));
    final target = _firstGroup(tag, RegExp(r'\bTarget="([^"]*)"'));
    if (id == null || target == null) continue;
    // 只关心图片关系，避免把样式/主题等关系误当图片
    if (type != null && !type.toLowerCase().endsWith('/image')) continue;
    map[id] = target;
  }
  return map;
}

/// 解析 `word/numbering.xml`：numId → 是否有序列表。
Map<String, bool> _parseNumbering(Archive archive) {
  final numFile = findArchiveFile(archive, 'word/numbering.xml');
  if (numFile == null) return const {};
  final xml = readArchiveFileUtf8(numFile);

  // abstractNumId -> 是否有序
  final abstractOrdered = <String, bool>{};
  for (final m in RegExp(
          r'<w:abstractNum\b[^>]*w:abstractNumId="(\d+)"[^>]*>(.*?)</w:abstractNum>',
          dotAll: true)
      .allMatches(xml)) {
    final fmt = _firstGroup(m.group(2) ?? '',
        RegExp(r'<w:numFmt\b[^>]*w:val="([^"]*)"'));
    abstractOrdered[m.group(1)!] =
        fmt != null && fmt != 'bullet' && fmt != 'none';
  }

  final result = <String, bool>{};
  for (final m in RegExp(
          r'<w:num\b[^>]*w:numId="(\d+)"[^>]*>(.*?)</w:num>', dotAll: true)
      .allMatches(xml)) {
    // 注意：<w:abstractNumId w:val="0"/> 的编号在 w:val 属性上
    final abstractId = _firstGroup(
        m.group(2) ?? '', RegExp(r'w:abstractNumId\b[^>]*w:val="(\d+)"'));
    if (abstractId == null) continue;
    result[m.group(1)!] = abstractOrdered[abstractId] ?? false;
  }
  return result;
}

String? _firstGroup(String src, RegExp reg) {
  final m = reg.firstMatch(src);
  return m?.group(1)?.trim();
}

/// 解析 w:body 内的段落与表格，按标题切分为多个章节。
List<ChapterDraft> _buildChapters(
  String xml, {
  required Map<String, String> rels,
  required Map<String, bool> numbering,
}) {
  final bodyMatch =
      RegExp(r'<w:body\b.*?(</w:body>|$)', dotAll: true).firstMatch(xml);
  final bodyXml = bodyMatch?.group(0) ?? xml;

  // 段落与表格按文档顺序出现
  final blockPattern = RegExp(r'<w:(p|tbl)\b.*?</w:\1>', dotAll: true);

  final blocks = <_Block>[];
  for (final bm in blockPattern.allMatches(bodyXml)) {
    final kind = bm.group(1)!;
    final raw = bm.group(0)!;

    if (kind == 'tbl') {
      blocks.add(_Block('table', _parseTable(raw, rels: rels)));
      continue;
    }

    final headingLevel = _headingLevelOf(raw);
    final listInfo = _listInfoOf(raw, numbering);
    final runs = _parseRuns(raw, rels: rels);

    if (runs.trim().isEmpty && headingLevel == null) {
      // 空段落跳过（列表项除外，避免破坏 <ul>/<ol> 结构）
      if (listInfo == null) continue;
    }

    if (headingLevel != null) {
      blocks.add(_Block('h', '<h$headingLevel>$runs</h$headingLevel>',
          level: headingLevel));
    } else if (listInfo != null) {
      blocks.add(_Block('li', '<li>$runs</li>', ordered: listInfo));
    } else {
      blocks.add(_Block('p', '<p>$runs</p>'));
    }
  }

  // 把连续的 <li> 合并进 <ul> / <ol>
  final merged = <_Block>[];
  _ListState? listState;
  for (final b in blocks) {
    if (b.kind == 'li') {
      final ordered = b.ordered;
      if (listState == null) {
        merged.add(_Block('list_open', ordered ? '<ol>' : '<ul>'));
        listState = _ListState(ordered);
      } else if (listState.ordered != ordered) {
        merged.add(_Block('list_close', listState.ordered ? '</ol>' : '</ul>'));
        merged.add(_Block('list_open', ordered ? '<ol>' : '<ul>'));
        listState = _ListState(ordered);
      }
      merged.add(b);
    } else {
      if (listState != null) {
        merged.add(_Block('list_close', listState.ordered ? '</ol>' : '</ul>'));
        listState = null;
      }
      merged.add(b);
    }
  }
  if (listState != null) {
    merged.add(_Block('list_close', listState.ordered ? '</ol>' : '</ul>'));
  }

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
      if (b.kind != 'list_open' && b.kind != 'list_close') hasContent = true;
    }
  }
  if (current.html.trim().isNotEmpty ||
      current.title.isNotEmpty ||
      chapters.isEmpty) {
    chapters.add(current);
  }
  return chapters;
}

class _ListState {
  _ListState(this.ordered);
  final bool ordered;
}

/// 标题层级：优先识别 Heading 样式，其次 `w:outlineLvl`。
int? _headingLevelOf(String paragraphXml) {
  final styleVal = _firstGroup(paragraphXml, RegExp(r'<w:pStyle[^>]*w:val="([^"]*)"'));
  if (styleVal != null) {
    final hm = RegExp(r'Heading\s*(\d)').firstMatch(styleVal);
    if (hm != null) return int.parse(hm.group(1)!);
    // 中文 Word 的样式名可能是「标题 1」
    final cn = RegExp(r'\u6807\u9898\s*(\d)').firstMatch(styleVal);
    if (cn != null) return int.parse(cn.group(1)!);
  }

  final outline =
      _firstGroup(paragraphXml, RegExp(r'<w:outlineLvl[^>]*w:val="(\d+)"'));
  if (outline != null) {
    final level = int.tryParse(outline);
    if (level != null && level >= 0 && level <= 5) return level + 1;
  }
  return null;
}

/// 列表信息：返回 true 表示有序列表，false 表示无序，null 表示不是列表项。
bool? _listInfoOf(String paragraphXml, Map<String, bool> numbering) {
  if (!paragraphXml.contains('<w:numPr')) return null;
  final numId =
      _firstGroup(paragraphXml, RegExp(r'<w:numId[^>]*w:val="(\d+)"'));
  if (numId == null) return false;
  return numbering[numId] ?? false;
}

/// 解析表格：`<w:tbl>` → `<table>`，首行含 `<w:tblHeader/>` 时输出 `<th>`。
String _parseTable(String tblXml, {required Map<String, String> rels}) {
  final rows = RegExp(r'<w:tr\b.*?</w:tr>', dotAll: true)
      .allMatches(tblXml)
      .toList();
  if (rows.isEmpty) return '';

  final buf = StringBuffer('<table>');
  for (var r = 0; r < rows.length; r++) {
    final rowXml = rows[r].group(0)!;
    final isHeaderRow = rowXml.contains('<w:tblHeader');
    final cells = RegExp(r'<w:tc\b.*?</w:tc>', dotAll: true)
        .allMatches(rowXml)
        .toList();

    buf.write('<tr>');
    for (final cm in cells) {
      final cellXml = cm.group(0)!;
      final inner = RegExp(r'<w:p\b.*?</w:p>', dotAll: true)
          .allMatches(cellXml)
          .map((pm) => _parseRuns(pm.group(0)!, rels: rels))
          .where((t) => t.trim().isNotEmpty)
          .join('<br/>');
      final tag = isHeaderRow ? 'th' : 'td';
      buf.write('<$tag>${inner.isEmpty ? '' : inner}</$tag>');
    }
    buf.write('</tr>');
  }
  buf.write('</table>');
  return buf.toString();
}

/// 解析段落内的 run：文本 + 粗/斜/下划线 + 内嵌图片。
String _parseRuns(String paragraphXml, {required Map<String, String> rels}) {
  final runMatches =
      RegExp(r'<w:r\b.*?</w:r>', dotAll: true).allMatches(paragraphXml);
  final buffer = StringBuffer();

  for (final rm in runMatches) {
    final run = rm.group(0)!;

    // 图片：<a:blip r:embed="rIdN"/>（DrawingML）或 <v:imagedata r:id="rIdN"/>（VML）
    final blip =
        RegExp(r'<a:blip\b[^>]*\br:embed="([^"]+)"').firstMatch(run);
    final pict =
        RegExp(r'<v:imagedata\b[^>]*\br:id="([^"]+)"').firstMatch(run);
    final embedId = blip?.group(1) ?? pict?.group(1);
    if (embedId != null) {
      final target = rels[embedId];
      if (target != null && target.isNotEmpty) {
        buffer.write('<img src="$target" alt=""/>');
        continue;
      }
    }

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
  _Block(this.kind, this.html, {this.level, this.ordered = false});
  final String kind; // 'h' | 'p' | 'li' | 'table' | 'list_open' | 'list_close'
  final String html;
  final int? level;
  final bool ordered;
}
