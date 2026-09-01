/// 文档转换过程中累积的一个章节草稿：标题 + 层级 + 原始 XHTML 片段。
///
/// 各文档转换器（DOCX/ODT/Markdown/RTF）先产出 [ChapterDraft] 列表，
/// 再经 [toHtmlChapters] 统一转换成 [HtmlChapter]，从而复用同一套
/// EPUB 构建与嵌套目录逻辑，并保证「无内容时也有占位章节」等边界一致。
import 'package:songjiang_reader/service/convert_to_epub/html_chapter.dart';

class ChapterDraft {
  ChapterDraft({this.title = '', this.level = 1, this.html = ''});

  /// 章节标题（用于目录 navMap）。空字符串表示沿用文档标题。
  String title;

  /// 标题层级 1~6，用于生成嵌套目录。
  int level;

  /// XHTML 正文片段（不含 `<body>` 外壳），可含 p/h/strong/em 等标签。
  String html;
}

extension ChapterDraftList on List<ChapterDraft> {
  /// 把草稿列表转换成 [HtmlChapter]；标题为空时回退到 [fallbackTitle]，
  /// 空章节正文回退到 `<p></p>`，列表为空时给出单个占位章节，避免构建非法 EPUB。
  List<HtmlChapter> toHtmlChapters(String fallbackTitle) {
    if (isEmpty) {
      return [HtmlChapter(fallbackTitle, '<p></p>', 1)];
    }
    return map((c) {
      final title = c.title.trim().isNotEmpty ? c.title.trim() : fallbackTitle;
      final html = c.html.trim().isEmpty ? '<p></p>' : c.html.trim();
      return HtmlChapter(title, html, c.level);
    }).toList();
  }
}
