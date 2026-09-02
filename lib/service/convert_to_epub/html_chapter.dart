/// 一个 EPUB 章节：标题 + 已经过处理、可直接写入 XHTML 的 HTML 正文片段。
///
/// 与 [Section]（纯文本，会被转义后按行包成 `<p>`）不同，
/// [HtmlChapter] 的 [html] 字段已经是合法的 XHTML 片段，
/// 构建器会原样写入，不做额外转义（标题仍会被转义）。
class HtmlChapter {
  final String title;

  /// XHTML 正文片段（不含 `<body>` 外壳），可包含 p/h/strong/em/img 等标签。
  final String html;

  /// 标题层级 1~6，用于生成目录（navMap）。
  final int level;

  HtmlChapter(this.title, this.html, [this.level = 1]);

  /// 返回替换了部分字段的副本（例如图片内嵌后替换正文）。
  HtmlChapter copyWith({String? title, String? html, int? level}) =>
      HtmlChapter(title ?? this.title, html ?? this.html, level ?? this.level);

  @override
  String toString() => '${'#' * level} $title';
}
