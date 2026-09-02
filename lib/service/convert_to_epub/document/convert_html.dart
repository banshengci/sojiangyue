import 'dart:io';

import 'package:html/parser.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/image_embed.dart';
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';
import 'package:songjiang_reader/service/convert_to_epub/encoding_utils.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 HTML / HTM / XHTML 文件转换为 EPUB。
///
/// 提取 `<title>` 作为书名、`<meta name="author">` 作为作者，按 h1~h3 切分章节，
/// 正文原样保留 XHTML 结构；同目录下的相对路径图片会内嵌为 data URI。
Future<File> convertHtmlToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  // 编码探测复用 TXT 导入逻辑，兼容 UTF-8 / GBK 等中文 HTML。
  final htmlString = readFileWithEncoding(file);

  final document = parse(htmlString);

  // 书名：优先 <title>，否则用文件名
  final title = document.querySelector('title')?.text.trim() ?? filename;

  // 作者：meta[name=author] / meta[property=article:author]
  String author = 'Unknown';
  for (final meta in document.querySelectorAll('meta')) {
    final name = (meta.attributes['name'] ?? '').toLowerCase();
    final property = (meta.attributes['property'] ?? '').toLowerCase();
    final content = meta.attributes['content']?.trim() ?? '';
    if (content.isEmpty) continue;
    if (name == 'author' || property == 'article:author') {
      author = content;
      break;
    }
  }

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

  // 相对路径图片内嵌为 data URI，脱离原目录后仍可显示
  final baseDir = file.parent;
  // 封面需在图片内嵌前抽取（内嵌后 src 变为 data URI，无法再定位本地路径）
  List<int>? coverBytes;
  String? coverMime;
  for (final c in chapters) {
    final src = firstLocalImageSrc(c.html);
    if (src != null) {
      final bytes = readLocalImageBytes(baseDir, src);
      if (bytes != null) {
        coverBytes = bytes;
        coverMime = guessMimeType(src);
        break;
      }
    }
  }
  final embedded = chapters
      .map((c) => c.copyWith(html: embedLocalImages(c.html, baseDir)))
      .toList();

  AnxLog.info('Convert: HTML 解析得到 ${embedded.length} 个章节');
  return buildEpubFromHtml(
    title: title,
    author: author,
    chapters: embedded,
    tempDir: tempDir,
    coverBytes: coverBytes,
    coverMime: coverMime,
  );
}
