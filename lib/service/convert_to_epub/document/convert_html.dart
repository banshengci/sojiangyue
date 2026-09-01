import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/service/convert_to_epub/encoding_utils.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 HTML / HTM 文件转换为 EPUB。
///
/// 提取 <title> 作为书名，按 h1~h3 切分章节，正文原样保留 XHTML 结构。
Future<File> convertHtmlToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  // 编码探测复用 TXT 导入逻辑，兼容 UTF-8 / GBK 等中文 HTML。
  final htmlString = readFileWithEncoding(file);

  final document = parse(htmlString);

  // 书名：优先 <title>，否则用文件名
  final title = document.querySelector('title')?.text.trim() ?? filename;
  final author = 'Unknown';

  // 取 body（没有则退化为整个文档）
  final root = document.querySelector('body') ?? document.documentElement;
  if (root == null) {
    throw Exception('Convert: HTML 解析失败，未找到可解析的内容');
  }

  // 移除脚本/样式等无关节点
  root
      .querySelectorAll('script, style, noscript, link, meta, head')
      .forEach((e) => e.remove());

  final chapters = <HtmlChapter>[];
  final buffer = StringBuffer();
  String currentTitle = filename;
  int currentLevel = 1;

  void flush() {
    final html = buffer.toString().trim();
    if (html.isNotEmpty) {
      chapters.add(HtmlChapter(currentTitle, html, currentLevel));
    }
    buffer.clear();
  }

  for (final node in root.children) {
    final tag = node.localName ?? '';
    final headingMatch = RegExp(r'^h([1-3])$').firstMatch(tag);
    if (headingMatch != null) {
      flush();
      currentTitle = node.text.trim().isNotEmpty ? node.text.trim() : filename;
      currentLevel = int.parse(headingMatch.group(1)!);
    }
    buffer.writeln(node.outerHtml);
  }
  flush();

  if (chapters.isEmpty) {
    // 兜底：整篇作为单章
    chapters.add(HtmlChapter(filename, root.innerHtml.trim()));
  }

  AnxLog.info('Convert: HTML 解析得到 ${chapters.length} 个章节');
  return buildEpubFromHtml(
    title: title,
    author: author,
    chapters: chapters,
    tempDir: tempDir,
  );
}
