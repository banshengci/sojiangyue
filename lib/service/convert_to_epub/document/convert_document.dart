import 'dart:io';

import 'package:songjiang_reader/service/convert_to_epub/document/convert_docx.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_markdown.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_odt.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_rtf.dart';

/// 根据扩展名把文档转换为 EPUB，返回转换后的临时 .epub 文件。
///
/// 支持的格式：
/// - html / htm：直接解析 HTML（按 h1~h3 切分章节）
/// - md：Markdown 轻量转换（按 #/## 切分章节）
/// - docx：Word OOXML（按 Heading 样式切分章节）
/// - odt：OpenDocument Text（按标题样式切分章节）
/// - rtf：富文本格式（按样式表中的标题样式切分章节）
///
/// 长文档会被切成多个章节并生成目录；转换后的 EPUB 走与 TXT 转换相同的导入/元数据/入库流程。
Future<File> convertDocumentToEpub(File file, {Directory? tempDir}) async {
  final ext = file.path.split('.').last.toLowerCase();

  switch (ext) {
    case 'html':
    case 'htm':
      return convertHtmlToEpub(file, tempDir: tempDir);
    case 'md':
      return convertMarkdownToEpub(file, tempDir: tempDir);
    case 'docx':
      return convertDocxToEpub(file, tempDir: tempDir);
    case 'odt':
      return convertOdtToEpub(file, tempDir: tempDir);
    case 'rtf':
      return convertRtfToEpub(file, tempDir: tempDir);
    default:
      throw Exception('Convert: 不支持的文档格式转换：$ext');
  }
}
