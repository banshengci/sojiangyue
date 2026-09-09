import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/chapter_draft.dart';
import 'package:songjiang_reader/service/convert_to_epub/encoding_utils.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/image_embed.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 Markdown 文件转换为 EPUB。
///
/// 支持的语法：
/// - 标题：`#`~`######` ATX 标题、Setext 标题（`===` / `---`）
/// - 强调：`**粗体**`、`*斜体*`、`***粗斜体***`、`_斜体_`、`~~删除线~~`
/// - 代码：行内 `` `code` `` 与 ``` 围栏代码块
/// - 列表：有序 / 无序 / **嵌套** / 任务列表（`- [x]`）
/// - 引用：`>` 块引用（内部继续按 Markdown 解析）
/// - 表格：GFM 表格（含对齐冒号）
/// - 图片：`![alt](path)`（本地相对路径会内嵌为 data URI）
/// - 链接：`[text](url)`、`<https://...>` 自动链接
/// - YAML front matter：`title` / `author`
/// - 硬换行：行尾两个空格 → `<br/>`
///
/// 按 `#`(H1) / `##`(H2) 标题切分为多个章节（生成嵌套目录）。
/// 编码探测复用 TXT 导入的 [readFileWithEncoding]（兼容 UTF-8 / GBK 等）。
Future<File> convertMarkdownToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  final raw = readFileWithEncoding(file);

  final frontMatter = _parseFrontMatter(raw);
  final blocks = _parseBlocks(frontMatter.body);

  // 书名优先级：front matter > 首个 H1 > 文件名
  String? firstH1;
  for (final b in blocks) {
    if (b.tag == 'h1') {
      firstH1 = _stripInline(b.text);
      break;
    }
  }
  final title = frontMatter.title ?? firstH1 ?? filename;
  final author = frontMatter.author ?? 'Unknown';

  final chapters = _blocksToChapters(blocks);
  final htmlChapters = chapters
      .toHtmlChapters(title)
      .map((c) => HtmlChapter(
            c.title,
            // 相对路径的图片内嵌为 data URI，避免导入后图片丢失
            embedLocalImages(c.html, file.parent),
            c.level,
          ))
      .toList();

  SjLog.info('Convert: Markdown 转换完成，书名=$title，章节数=${htmlChapters.length}');
  return buildEpubFromHtml(
    title: title,
    author: author,
    chapters: htmlChapters,
    tempDir: tempDir,
  );
}

// ---------------------------------------------------------------------------
// front matter
// ---------------------------------------------------------------------------

class _FrontMatter {
  _FrontMatter(this.body, {this.title, this.author});
  final String body;
  final String? title;
  final String? author;
}

/// 解析文档开头的 YAML front matter（仅取 title / author 两个字段）。
_FrontMatter _parseFrontMatter(String raw) {
  final lines = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'^\uFEFF'), '')
      .split('\n');

  var i = 0;
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  if (i >= lines.length || lines[i].trim() != '---') {
    return _FrontMatter(raw);
  }

  final end = lines.indexWhere(
      (l) => l.trim() == '---' || l.trim() == '...', i + 1);
  if (end <= i) return _FrontMatter(raw);

  String? title;
  String? author;
  for (var k = i + 1; k < end; k++) {
    final m = RegExp(r'^\s*([A-Za-z_][\w-]*)\s*:\s*(.*)$').firstMatch(lines[k]);
    if (m == null) continue;
    final key = m.group(1)!.toLowerCase();
    var value = m.group(2)!.trim();
    if (value.length >= 2) {
      final quote = value[0];
      if ((quote == '"' || quote == "'") && value.endsWith(quote)) {
        value = value.substring(1, value.length - 1).trim();
      }
    }
    if (value.isEmpty) continue;
    if (key == 'title') title = value;
    if (key == 'author' || key == 'authors' || key == 'creator') {
      author = value;
    }
  }

  return _FrontMatter(lines.sublist(end + 1).join('\n'),
      title: title, author: author);
}

// ---------------------------------------------------------------------------
// 块级解析
// ---------------------------------------------------------------------------

class _MdBlock {
  _MdBlock(this.tag, this.text, this.html);
  final String tag; // h1..h6 | p | ul | ol | blockquote | pre | table | hr
  final String text; // 标题原始文本（用于章节名）
  final String html;
}

List<_MdBlock> _parseBlocks(String md) {
  final lines = md
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'^\uFEFF'), '')
      .split('\n');

  final blocks = <_MdBlock>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    // 围栏代码块
    if (line.trimLeft().startsWith('```') || line.trimLeft().startsWith('~~~')) {
      final fence = line.trimLeft().substring(0, 3);
      i++;
      final buf = <String>[];
      while (i < lines.length && !lines[i].trimLeft().startsWith(fence)) {
        buf.add(lines[i]);
        i++;
      }
      i++; // 跳过结束围栏
      blocks.add(_MdBlock('pre', '',
          '<pre><code>${_escapeHtml(buf.join('\n'))}</code></pre>'));
      continue;
    }

    // 空行
    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    // ATX 标题
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (h != null) {
      final level = h.group(1)!.length;
      final text = _stripAtxSuffix(h.group(2)!.trim());
      blocks.add(
          _MdBlock('h$level', text, '<h$level>${_inline(text)}</h$level>'));
      i++;
      continue;
    }

    // Setext 标题（在 hr 之前判断，避免 `---` 被当成分割线）
    if (i + 1 < lines.length) {
      final next = lines[i + 1];
      if (RegExp(r'^=+\s*$').hasMatch(next)) {
        final text = line.trim();
        blocks.add(_MdBlock('h1', text, '<h1>${_inline(text)}</h1>'));
        i += 2;
        continue;
      }
      if (RegExp(r'^-+\s*$').hasMatch(next)) {
        final text = line.trim();
        blocks.add(_MdBlock('h2', text, '<h2>${_inline(text)}</h2>'));
        i += 2;
        continue;
      }
    }

    // 分割线
    if (RegExp(r'^\s*([-*_])\s*(?:\1\s*){2,}$').hasMatch(line)) {
      blocks.add(_MdBlock('hr', '', '<hr/>'));
      i++;
      continue;
    }

    // GFM 表格
    final tableEnd = _tryParseTable(lines, i);
    if (tableEnd != null) {
      blocks.add(_MdBlock('table', '', _tableToHtml(lines.sublist(i, tableEnd))));
      i = tableEnd;
      continue;
    }

    // 引用
    if (RegExp(r'^\s{0,3}>\s?').hasMatch(line)) {
      final buf = <String>[];
      while (i < lines.length && RegExp(r'^\s{0,3}>\s?').hasMatch(lines[i])) {
        buf.add(lines[i].replaceFirst(RegExp(r'^\s{0,3}>\s?'), ''));
        i++;
      }
      final inner = _parseBlocks(buf.join('\n'))
          .map((b) => b.html)
          .join('\n');
      blocks.add(_MdBlock('blockquote', '', '<blockquote>$inner</blockquote>'));
      continue;
    }

    // 列表（含嵌套）
    if (_isListLine(line)) {
      final entries = <_ListEntry>[];
      i = _collectListEntries(lines, i, entries);
      if (entries.isNotEmpty) {
        final cursor = _Cursor();
        final html = _renderList(entries, cursor, entries.first.indent,
            entries.first.ordered);
        blocks.add(
            _MdBlock(entries.first.ordered ? 'ol' : 'ul', '', html));
        continue;
      }
    }

    // 段落
    final buf = <String>[];
    while (i < lines.length && !_endsParagraph(lines, i)) {
      buf.add(lines[i]);
      i++;
    }
    if (buf.isNotEmpty) {
      blocks.add(_MdBlock('p', '', '<p>${_paragraph(buf)}</p>'));
    }
  }

  return blocks;
}

/// 当前行是否终止一个段落。
bool _endsParagraph(List<String> lines, int i) {
  final line = lines[i];
  if (line.trim().isEmpty) return true;
  if (line.trimLeft().startsWith('```') || line.trimLeft().startsWith('~~~')) {
    return true;
  }
  if (RegExp(r'^#{1,6}\s').hasMatch(line)) return true;
  if (RegExp(r'^\s*([-*_])\s*(?:\1\s*){2,}$').hasMatch(line)) return true;
  if (RegExp(r'^\s{0,3}>\s?').hasMatch(line)) return true;
  if (_isListLine(line)) return true;
  if (line.trimLeft().startsWith('|') && _tryParseTable(lines, i) != null) {
    return true;
  }
  // Setext 标题的下划线行
  if (RegExp(r'^=+\s*$').hasMatch(line) || RegExp(r'^-+\s*$').hasMatch(line)) {
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// 列表
// ---------------------------------------------------------------------------

bool _isListLine(String line) =>
    RegExp(r'^(\s*)[-*+]\s+').hasMatch(line) ||
    RegExp(r'^(\s*)\d+[.)]\s+').hasMatch(line);

class _ListEntry {
  _ListEntry({
    required this.indent,
    required this.ordered,
    required this.marker,
    required this.text,
    required this.isTask,
    required this.taskDone,
  });
  final int indent;
  final bool ordered;

  /// 列表标记：无序为 `-`/`*`/`+`，有序为 `.`/`)`。
  /// 标记或有序性变化时，视为另一个列表（符合 CommonMark）。
  final String marker;
  String text;
  final bool isTask;
  final bool taskDone;
}

class _Cursor {
  int pos = 0;
}

/// 从 [start] 开始收集属于同一列表块的条目，返回结束下标。
int _collectListEntries(List<String> lines, int start, List<_ListEntry> out) {
  var i = start;
  while (i < lines.length) {
    final line = lines[i];

    if (_isListLine(line)) {
      final indent = _indentOf(line);
      final ulMatch = RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(line);
      String body;
      bool ordered;
      String marker;
      if (ulMatch != null) {
        ordered = false;
        marker = ulMatch.group(2)!;
        body = ulMatch.group(3)!;
      } else {
        final olMatch = RegExp(r'^(\s*)\d+([.)])\s+(.*)$').firstMatch(line)!;
        ordered = true;
        marker = olMatch.group(2)!;
        body = olMatch.group(3)!;
      }

      // 同层级上换了标记或有序性 → 结束当前列表，交由外层开启新列表
      if (out.isNotEmpty &&
          indent <= out.first.indent &&
          (ordered != out.first.ordered || marker != out.first.marker)) {
        return i;
      }

      bool isTask = false;
      bool taskDone = false;
      final taskMatch = RegExp(r'^\[([ xX])\]\s+(.*)$').firstMatch(body);
      if (taskMatch != null) {
        isTask = true;
        taskDone = taskMatch.group(1)!.toLowerCase() == 'x';
        body = taskMatch.group(2)!;
      }

      out.add(_ListEntry(
        indent: indent,
        ordered: ordered,
        marker: marker,
        text: body.trim(),
        isTask: isTask,
        taskDone: taskDone,
      ));
      i++;
      continue;
    }

    // 空行：只有后面还跟着列表项时才继续（松散列表）
    if (line.trim().isEmpty) {
      var k = i + 1;
      while (k < lines.length && lines[k].trim().isEmpty) {
        k++;
      }
      if (k < lines.length && _isListLine(lines[k])) {
        i = k;
        continue;
      }
      break;
    }

    // 缩进的续行：并入上一个条目
    if (out.isNotEmpty && _indentOf(line) >= 2) {
      out.last.text = '${out.last.text} ${line.trim()}';
      i++;
      continue;
    }

    break;
  }
  return i;
}

int _indentOf(String line) => line.length - line.trimLeft().length;

/// 递归渲染列表：[indent] 为当前层级的缩进量。
String _renderList(List<_ListEntry> entries, _Cursor cur, int indent,
    bool ordered) {
  final buf = StringBuffer();
  buf.write(ordered ? '<ol>' : '<ul>');

  while (cur.pos < entries.length) {
    final e = entries[cur.pos];
    if (e.indent < indent) break;
    if (e.indent > indent) {
      // 更深的层级：作为当前项的嵌套列表继续处理
      final child = _Cursor()..pos = cur.pos;
      final nested = _renderList(entries, child, e.indent, e.ordered);
      cur.pos = child.pos;
      buf.write(nested);
      continue;
    }

    cur.pos++;
    final children = <_ListEntry>[];
    while (cur.pos < entries.length && entries[cur.pos].indent > indent) {
      children.add(entries[cur.pos]);
      cur.pos++;
    }

    var inner = _inline(e.text);
    if (children.isNotEmpty) {
      final child = _Cursor();
      inner += _renderList(
          children, child, children.first.indent, children.first.ordered);
    }

    buf.write('<li>');
    if (e.isTask) buf.write(e.taskDone ? '\u2611 ' : '\u2610 ');
    buf.write(inner);
    buf.write('</li>');
  }

  buf.write(ordered ? '</ol>' : '</ul>');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// 表格
// ---------------------------------------------------------------------------

/// 若 [i] 处是 GFM 表格，返回表格结束后的行号，否则返回 null。
int? _tryParseTable(List<String> lines, int i) {
  if (i + 1 >= lines.length) return null;
  final header = lines[i];
  if (!header.trimLeft().startsWith('|')) return null;

  final delimiter = lines[i + 1];
  if (!delimiter.contains('-')) return null;
  if (!RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$')
      .hasMatch(delimiter)) {
    return null;
  }

  var j = i + 2;
  while (j < lines.length &&
      lines[j].trimLeft().startsWith('|') &&
      lines[j].trim().isNotEmpty) {
    j++;
  }
  return j;
}

String _tableToHtml(List<String> rows) {
  final header = _splitRow(rows[0]);
  final aligns = _splitRow(rows[1])
      .map((c) => _alignOf(c))
      .toList();
  final bodyRows = rows.skip(2).map(_splitRow).toList();

  final buf = StringBuffer('<table>');

  buf.write('<thead><tr>');
  for (var c = 0; c < header.length; c++) {
    buf.write('<th${_alignAttr(c, aligns)}>${_inline(header[c].trim())}</th>');
  }
  buf.write('</tr></thead>');

  if (bodyRows.isNotEmpty) {
    buf.write('<tbody>');
    for (final row in bodyRows) {
      buf.write('<tr>');
      for (var c = 0; c < header.length; c++) {
        final cell = c < row.length ? row[c].trim() : '';
        buf.write('<td${_alignAttr(c, aligns)}>${_inline(cell)}</td>');
      }
      buf.write('</tr>');
    }
    buf.write('</tbody>');
  }

  buf.write('</table>');
  return buf.toString();
}

List<String> _splitRow(String row) {
  var s = row.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith(r'\|')) {
    s = s.substring(0, s.length - 1);
  }
  return s.split('|').map((c) => c.replaceAll(r'\|', '|')).toList();
}

String _alignOf(String cell) {
  final c = cell.trim();
  final left = c.startsWith(':');
  final right = c.endsWith(':');
  if (left && right) return 'center';
  if (right) return 'right';
  if (left) return 'left';
  return '';
}

String _alignAttr(int column, List<String> aligns) {
  if (column >= aligns.length) return '';
  final a = aligns[column];
  return a.isEmpty ? '' : ' style="text-align:$a"';
}

// ---------------------------------------------------------------------------
// 章节切分
// ---------------------------------------------------------------------------

List<ChapterDraft> _blocksToChapters(List<_MdBlock> blocks) {
  final chapters = <ChapterDraft>[];
  var current = ChapterDraft(level: 1);
  var hasContent = false;

  for (final b in blocks) {
    if (b.tag == 'h1' || b.tag == 'h2') {
      if (hasContent || current.title.isNotEmpty) chapters.add(current);
      current = ChapterDraft(
        title: _stripInline(b.text),
        level: b.tag == 'h1' ? 1 : 2,
        html: b.html,
      );
      hasContent = false;
    } else {
      current.html += '\n${b.html}';
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

// ---------------------------------------------------------------------------
// 行内
// ---------------------------------------------------------------------------

/// 把段落若干行合并为一段 HTML：行尾两个空格视为硬换行。
String _paragraph(List<String> lines) {
  final parts = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final hard = RegExp(r'\s{2,}$').hasMatch(line);
    parts.add(_inline(line.trim()));
    if (hard && i < lines.length - 1) parts.add('<br/>');
  }

  // 英文之间补空格，中文之间不补（避免 CJK 正文出现多余空隙）
  final buf = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part == '<br/>') {
      buf.write(part);
      continue;
    }
    if (i > 0 && parts[i - 1] != '<br/>') {
      if (_needsSpace(parts[i - 1], part)) buf.write(' ');
    }
    buf.write(part);
  }
  return buf.toString().trim();
}

bool _needsSpace(String prev, String next) {
  if (prev.isEmpty || next.isEmpty) return false;
  final a = prev[prev.length - 1];
  final b = next[0];
  return _isAsciiWord(a) && _isAsciiWord(b);
}

bool _isAsciiWord(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x30 && code <= 0x39);
}

/// 行内语法解析：代码/链接/图片先用占位符保护，再做强调等替换。
String _inline(String text) {
  var s = _escapeHtml(text);
  final slots = <String>[];

  String slot(String value) {
    slots.add(value);
    return '\u0000${slots.length - 1}\u0000';
  }

  // 行内代码
  s = s.replaceAllMapped(RegExp(r'(`+)([^`]+?)\1'),
      (m) => slot('<code>${m.group(2)}</code>'));

  // 图片
  s = s.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(\s*([^\s)]+)(?:\s+"([^"]*)")?\s*\)'), (m) {
    final alt = m.group(1) ?? '';
    final src = m.group(2) ?? '';
    final title = m.group(3);
    final attr = title == null ? '' : ' title="$title"';
    return slot('<img src="$src" alt="$alt"$attr/>');
  });

  // 链接
  s = s.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\(\s*([^\s)]+)(?:\s+"([^"]*)")?\s*\)'), (m) {
    final label = m.group(1) ?? '';
    final href = m.group(2) ?? '';
    final title = m.group(3);
    final attr = title == null ? '' : ' title="$title"';
    return slot('<a href="$href"$attr>${label.isEmpty ? href : label}</a>');
  });

  // 自动链接 <https://...>
  s = s.replaceAllMapped(RegExp(r'&lt;((?:https?|mailto):[^\s&]+)&gt;'),
      (m) => slot('<a href="${m.group(1)}">${m.group(1)}</a>'));

  // 强调
  s = s.replaceAllMapped(RegExp(r'\*\*\*([^*]+)\*\*\*'),
      (m) => '<strong><em>${m.group(1)}</em></strong>');
  s = s.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'), (m) => '<strong>${m.group(1)}</strong>');
  s = s.replaceAllMapped(
      RegExp(r'\*([^*\n]+)\*'), (m) => '<em>${m.group(1)}</em>');
  s = s.replaceAllMapped(RegExp(r'___([^_]+)___'),
      (m) => '<strong><em>${m.group(1)}</em></strong>');
  s = s.replaceAllMapped(
      RegExp(r'__([^_]+)__'), (m) => '<strong>${m.group(1)}</strong>');
  s = s.replaceAllMapped(
      RegExp(r'_([^_\n]+)_'), (m) => '<em>${m.group(1)}</em>');
  s = s.replaceAllMapped(
      RegExp(r'~~([^~]+)~~'), (m) => '<del>${m.group(1)}</del>');

  // 还原占位符
  s = s.replaceAllMapped(RegExp('\u0000(\\d+)\u0000'),
      (m) => slots[int.parse(m.group(1)!)]);

  return s;
}

String _escapeHtml(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// 去掉 ATX 标题末尾的可选 `#`。
String _stripAtxSuffix(String text) =>
    text.replaceAll(RegExp(r'\s+#+\s*$'), '').trim();

String _stripInline(String t) =>
    t.replaceAll(RegExp(r'[*`_~#]'), '').trim();
