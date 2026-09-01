import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/chapter_draft.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/xml_utils.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 OpenDocument Text (.odt) 文件转换为 EPUB。
///
/// ODT 是 ZIP 包，正文在 `content.xml`，元数据在 `meta.xml`，样式在 `styles.xml`。
/// 解析段落/标题/粗体/斜体/列表结构，重建为 HTML。
Future<File> convertOdtToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  final bytes = file.readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  final content = findArchiveFile(archive, 'content.xml');
  if (content == null) {
    throw Exception('Convert: 不是有效的 ODT 文件（缺少 content.xml）');
  }
  final xml = readArchiveFileUtf8(content);

  String title = filename;
  String author = 'Unknown';
  final meta = findArchiveFile(archive, 'meta.xml');
  if (meta != null) {
    final metaXml = readArchiveFileUtf8(meta);
    title = _firstGroup(metaXml, RegExp(r'<dc:title>([^<]*)</dc:title>')) ??
        filename;
    author = _firstGroup(metaXml, RegExp(r'<dc:creator>([^<]*)</dc:creator>')) ??
        'Unknown';
  }

  // 样式表：style:name -> 是否粗体/斜体
  final styleMap = <String, _StyleFmt>{};
  final stylesXml = findArchiveFile(archive, 'styles.xml') != null
      ? readArchiveFileUtf8(findArchiveFile(archive, 'styles.xml')!)
      : '';
  _collectStyles('$xml\n$stylesXml', styleMap);

  final parts = _buildParts(xml, styleMap);
  final chapters = _splitChapters(parts);
  final htmlChapters = chapters.toHtmlChapters(decodeXmlEntities(title));

  AnxLog.info('Convert: ODT 转换完成，书名=$title，章节数=${htmlChapters.length}');
  return buildEpubFromHtml(
    title: decodeXmlEntities(title),
    author: decodeXmlEntities(author),
    chapters: htmlChapters,
    tempDir: tempDir,
  );
}

void _collectStyles(String xml, Map<String, _StyleFmt> styleMap) {
  final re = RegExp(
      r'<style:style\b[^>]*style:name="([^"]+)"[^>]*>(.*?)</style:style>',
      dotAll: true);
  for (final m in re.allMatches(xml)) {
    final name = m.group(1)!;
    final body = m.group(2) ?? '';
    final bold = RegExp(r'fo:font-weight="(bold|[5-9]00)"').hasMatch(body);
    final italic = RegExp(r'fo:font-style="italic"').hasMatch(body);
    styleMap[name] = _StyleFmt(bold: bold, italic: italic);
  }
}

List<_Para> _buildParts(String xml, Map<String, _StyleFmt> styleMap) {
  // 仅取 <office:text> 内的段落
  final textMatch =
      RegExp(r'<office:text\b.*?(</office:text>|$)', dotAll: true)
          .firstMatch(xml);
  final textXml = textMatch?.group(0) ?? xml;

  final parts = <_Para>[];
  final paraRe = RegExp(r'<text:(p|h)\b([^>]*)>(.*?)</text:\1>',
      dotAll: true);

  for (final m in paraRe.allMatches(textXml)) {
    final tag = m.group(1)!;
    final attrs = m.group(2)!;
    final inner = m.group(3) ?? '';

    if (tag == 'h') {
      final level = int.tryParse(
              _attr(attrs, 'text:level') ?? '') ??
          1;
      final html =
          '<h$level>${_processInline(inner, styleMap)}</h$level>';
      parts.add(_Para('h', html, level));
    } else {
      final html = '<p>${_processInline(inner, styleMap)}</p>';
      parts.add(_Para('p', html, null));
    }
  }
  return parts;
}

/// 把段落列表按标题切分为多个章节（标题作为章节名并保留于正文）。
List<ChapterDraft> _splitChapters(List<_Para> parts) {
  final chapters = <ChapterDraft>[];
  var current = ChapterDraft(level: 1);
  var hasContent = false;

  for (final part in parts) {
    if (part.kind == 'h') {
      if (hasContent || current.title.isNotEmpty) chapters.add(current);
      current = ChapterDraft(
        title: _stripTags(part.html),
        level: part.level ?? 1,
        html: part.html,
      );
      hasContent = false;
    } else {
      current.html += part.html;
      hasContent = true;
    }
  }
  if (current.html.trim().isNotEmpty ||
      current.title.isNotEmpty ||
      chapters.isEmpty) {
    chapters.add(current);
  }
  return chapters;
}

/// 处理段落内部 XML：行分隔、span 样式、去除其余 ODT 标签。
String _processInline(String xml, Map<String, _StyleFmt> styleMap) {
  var s = xml;
  s = s.replaceAll(RegExp(r'<text:line-break\s*/?>'), '<br/>');
  s = s.replaceAll(RegExp(r'<text:tab\s*/?>'), ' ');
  s = s.replaceAll(RegExp(r'<text:s\s*/?>'), ' ');

  // 由内向外处理 span
  final spanRe =
      RegExp(r'<text:span\b([^>]*)>(.*?)</text:span>', dotAll: true);
  while (true) {
    final m = spanRe.firstMatch(s);
    if (m == null) break;
    final attrs = m.group(1)!;
    final inner = m.group(2)!;
    final styleName = _attr(attrs, 'text:style-name');
    final fmt = styleMap[styleName] ?? _StyleFmt();
    var innerHtml = _processInline(inner, styleMap);
    if (fmt.italic) innerHtml = '<em>$innerHtml</em>';
    if (fmt.bold) innerHtml = '<strong>$innerHtml</strong>';
    s = s.replaceRange(m.start, m.end, innerHtml);
  }

  // 去掉剩余 ODT 标签，保留文本与已注入的 HTML 标签
  s = s.replaceAll(RegExp(r'</?text:[^>]*>'), '');
  s = s.replaceAll(RegExp(r'</?office:[^>]*>'), '');
  return s;
}

String? _firstGroup(String src, RegExp reg) {
  final m = reg.firstMatch(src);
  return m?.group(1)?.trim();
}

String? _attr(String attrs, String name) {
  final m = RegExp('$name="([^"]*)"').firstMatch(attrs);
  return m?.group(1);
}

class _StyleFmt {
  const _StyleFmt({this.bold = false, this.italic = false});
  final bool bold;
  final bool italic;
}

class _Para {
  _Para(this.kind, this.html, this.level);
  final String kind; // 'h' | 'p'
  final String html;
  final int? level;
}

String _stripTags(String html) =>
    html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&[a-zA-Z]+;', ' ').trim();
