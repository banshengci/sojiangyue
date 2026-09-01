import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/service/convert_to_epub/encoding_utils.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 Markdown 文件转换为 EPUB。
///
/// 支持标题、粗体、斜体、行内代码、代码块、有序/无序列表、引用、分割线、链接。
/// 编码探测复用 TXT 导入的 [readFileWithEncoding]（兼容 UTF-8 / GBK 等）。
Future<File> convertMarkdownToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  final raw = readFileWithEncoding(file);
  final html = _markdownToHtml(raw, fallbackTitle: filename);

  // 第一章标题作为书名（若有 H1）
  final firstH1 = RegExp(r'^#\s+(.*)$', multiLine: true).firstMatch(raw);
  final title = firstH1 != null
      ? _stripInline(firstH1.group(1)!.trim())
      : filename;

  AnxLog.info('Convert: Markdown 转换完成，书名=$title');
  return buildEpubFromHtml(
    title: title,
    author: 'Unknown',
    chapters: [HtmlChapter(title, html)],
    tempDir: tempDir,
  );
}

String _markdownToHtml(String md, {required String fallbackTitle}) {
  final lines = md
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');

  final blocks = <String>[];
  int i = 0;

  while (i < lines.length) {
    final line = lines[i];

    // 代码块 ```
    if (line.trim().startsWith('```')) {
      i++;
      final buf = <String>[];
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.add(lines[i]);
        i++;
      }
      i++; // 跳过结束的 ```
      blocks.add('<pre><code>${_escapeHtml(buf.join('\n'))}</code></pre>');
      continue;
    }

    // 标题
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (h != null) {
      final level = h.group(1)!.length;
      blocks.add('<h$level>${_inline(h.group(2)!.trim())}</h$level>');
      i++;
      continue;
    }

    // 分割线
    if (RegExp(r'^\s*([-*_])\1{2,}\s*$').hasMatch(line)) {
      blocks.add('<hr/>');
      i++;
      continue;
    }

    // 引用
    if (RegExp(r'^\s*>\s?').hasMatch(line)) {
      final buf = <String>[];
      while (i < lines.length && RegExp(r'^\s*>\s?').hasMatch(lines[i])) {
        buf.add(lines[i].replaceFirst(RegExp(r'^\s*>\s?'), ''));
        i++;
      }
      blocks.add('<blockquote>${_inline(buf.join(' ').trim())}</blockquote>');
      continue;
    }

    // 无序列表
    if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
      final buf = <String>[];
      while (i < lines.length &&
          RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i])) {
        buf.add(lines[i].replaceFirst(RegExp(r'^\s*[-*+]\s+'), ''));
        i++;
      }
      blocks.add(
          '<ul>${buf.map((e) => '<li>${_inline(e.trim())}</li>').join('')}</ul>');
      continue;
    }

    // 有序列表
    if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
      final buf = <String>[];
      while (i < lines.length &&
          RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
        buf.add(lines[i].replaceFirst(RegExp(r'^\s*\d+\.\s+'), ''));
        i++;
      }
      blocks.add(
          '<ol>${buf.map((e) => '<li>${_inline(e.trim())}</li>').join('')}</ol>');
      continue;
    }

    // 空行
    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    // 段落：收集到下一个空行或块级标记
    final buf = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !lines[i].trim().startsWith('```') &&
        !RegExp(r'^(#{1,6})\s').hasMatch(lines[i]) &&
        !RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i]) &&
        !RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i]) &&
        !RegExp(r'^\s*>\s?').hasMatch(lines[i]) &&
        !RegExp(r'^\s*([-*_])\1{2,}\s*$').hasMatch(lines[i])) {
      buf.add(lines[i]);
      i++;
    }
    blocks.add('<p>${_inline(buf.join(' ').trim())}</p>');
  }

  return blocks.join('\n');
}

String _inline(String text) {
  var s = _escapeHtml(text);
  s = s.replaceAllMapped(
      RegExp(r'`([^`]+)`'), (m) => '<code>${m.group(1)}</code>');
  s = s.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'),
      (m) => '<strong>${m.group(1)}</strong>');
  s = s.replaceAllMapped(
      RegExp(r'\*([^*]+)\*'), (m) => '<em>${m.group(1)}</em>');
  s = s.replaceAllMapped(
      RegExp(r'_([^_]+)_'), (m) => '<em>${m.group(1)}</em>');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (m) => '<a href="${m.group(2)}">${m.group(1)}</a>');
  return s;
}

String _escapeHtml(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _stripInline(String t) =>
    t.replaceAll(RegExp(r'[*`_#]'), '').trim();
