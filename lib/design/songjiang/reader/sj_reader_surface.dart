/// 松江阅 · 小说正文版式（微信读书风格）
///
/// 还原点：
///  - 章节序号小字 + 章节名大字，上方留白充足；
///  - 正文宋体、1.95 倍行高、两端对齐、首行缩进两字；
///  - 页面底部居中「↑ 上滑显示工具栏」，右侧页码「2 / 18602」。
///
/// 真机上正文由 foliate WebView 渲染，本组件用于设计预览与统一版式参数，
/// 字号 / 行高 / 缩进的取值与 WebView 侧 CSS 一一对应。
library;

import 'package:flutter/material.dart';

import 'sj_reader_tokens.dart';

/// 一章的展示数据。
@immutable
class SjReaderChapter {
  const SjReaderChapter({
    required this.title,
    required this.paragraphs,
    this.index,
    this.pageText = '',
  });

  /// 章节序号，如「第 1 章」。
  final String? index;

  /// 章节名。
  final String title;

  /// 正文段落。
  final List<String> paragraphs;

  /// 右下角页码文案，如「2 / 18602」。
  final String pageText;
}

/// 小说正文页。
class SjReaderSurface extends StatelessWidget {
  const SjReaderSurface({
    super.key,
    required this.palette,
    required this.chapter,
    this.fontSize = 19,
    this.showHint = true,
    this.indent = true,
    this.topPadding = 26,
    this.scrollController,
  });

  /// 当前阅读调色板。
  final SjReaderPalette palette;

  /// 章节内容。
  final SjReaderChapter chapter;

  /// 正文字号。
  final double fontSize;

  /// 是否显示底部「上滑显示工具栏」提示。
  final bool showHint;

  /// 是否首行缩进两字。
  final bool indent;

  /// 正文顶部留白（不含状态栏）。
  final double topPadding;

  /// 滚动控制器（预览用）。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = SjReaderText.body(palette.foreground, fontSize: fontSize);

    return Container(
      color: palette.background,
      child: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                SjReaderSize.textPadding,
                topPadding,
                SjReaderSize.textPadding,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (chapter.index != null)
                    Text(
                      chapter.index!,
                      style: SjReaderText.chapterNumber(palette.faint),
                    ),
                  if (chapter.index != null) const SizedBox(height: 14),
                  Text(
                    chapter.title,
                    style: SjReaderText.chapterTitle(palette.foreground),
                  ),
                  const SizedBox(height: 40),
                  for (final paragraph in chapter.paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        indent ? '\u3000\u3000$paragraph' : paragraph,
                        style: bodyStyle,
                        textAlign: TextAlign.justify,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _SurfaceFooter(
            palette: palette,
            pageText: chapter.pageText,
            showHint: showHint,
          ),
        ],
      ),
    );
  }
}

class _SurfaceFooter extends StatelessWidget {
  const _SurfaceFooter({
    required this.palette,
    required this.pageText,
    required this.showHint,
  });

  final SjReaderPalette palette;
  final String pageText;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final style = SjReaderText.footer(palette.faint);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SjReaderSize.textPadding,
        0,
        SjReaderSize.textPadding,
        10,
      ),
      child: SizedBox(
        height: 22,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (showHint)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 13,
                    color: palette.faint,
                  ),
                  const SizedBox(width: 2),
                  Text('上滑显示工具栏', style: style),
                ],
              ),
            if (pageText.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Text(pageText, style: style),
              ),
          ],
        ),
      ),
    );
  }
}
