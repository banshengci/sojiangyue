import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// 在 ZIP 归档中按文件名（允许前导路径）查找文件。
ArchiveFile? findArchiveFile(Archive archive, String name) {
  for (final f in archive.files) {
    if (!f.isFile) continue;
    if (f.name == name || f.name.endsWith('/$name')) return f;
  }
  return null;
}

/// 以 UTF-8（兼容 BOM / 容错）读取归档内文本文件。
String readArchiveFileUtf8(ArchiveFile file) {
  final content = file.content;
  if (content == null) return '';
  final bytes =
      (content is Uint8List) ? content : Uint8List.fromList(content as List<int>);
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// 解码 XML 实体（命名 + 十进制/十六进制数字实体）。
String decodeXmlEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAllMapped(
        RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));

/// 仅在文本节点中转义 HTML 特殊字符（标签由我们自己注入）。
String escapeHtmlText(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
