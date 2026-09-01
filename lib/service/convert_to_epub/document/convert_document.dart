import 'dart:io';

import 'package:songjiang_reader/service/convert_to_epub/document/convert_docx.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_markdown.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/convert_odt.dart';

/// 根据扩展名把文档转换为 EPUB，返回转换后的临时 .epub 文件。
///
/// 支持的格式：
/// - html / htm：直接解析 HTML
/// - md：Markdown 轻量转换
/// - docx：Word OOXML
/// - odt：OpenDocument Text
///
/// 转换后的 EPUB 走与 TXT 转换相同的导入/元数据/入库流程。
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
    default:
      throw Exception('Convert: 不支持的文档格式转换：$ext');
  }
}
