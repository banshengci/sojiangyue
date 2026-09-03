import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/service/import_file_normalizer.dart';

/// 构造最小 EPUB 字节流。
///
/// EPUB 规范要求 mimetype 必须是 ZIP 的第一个条目，
/// 嗅探逻辑正是依赖这一点来区分 EPUB 与普通 ZIP（CBZ）。
Uint8List _buildEpubBytes() {
  final archive = Archive();
  final mime = utf8.encode('application/epub+zip');
  archive.addFile(ArchiveFile('mimetype', mime.length, mime));
  final container = utf8.encode('<?xml version="1.0"?><container/>');
  archive.addFile(
      ArchiveFile('META-INF/container.xml', container.length, container));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// 构造最小 ODT 字节流。
///
/// ODT 与 EPUB 一样要求 ZIP 首条目为 mimetype，区别只在内容：
/// ODT 是 application/vnd.oasis.opendocument.text。
Uint8List _buildOdtBytes() {
  final archive = Archive();
  final mime = utf8.encode('application/vnd.oasis.opendocument.text');
  archive.addFile(ArchiveFile.noCompress('mimetype', mime.length, mime));
  final content = utf8.encode('<?xml version="1.0"?><office:document/>');
  archive.addFile(ArchiveFile('content.xml', content.length, content));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// 构造最小 CBZ（漫画包）：同样是 ZIP，但没有 mimetype 条目。
Uint8List _buildCbzBytes() {
  final archive = Archive();
  final data = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
  archive.addFile(ArchiveFile('page1.jpg', data.length, data));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Directory _makeTempDir() => Directory.systemTemp.createTempSync('sj_import_');

File _writeFile(Directory dir, String name, List<int> bytes) {
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  f.writeAsBytesSync(bytes);
  return f;
}

void main() {
  group('导入文件格式嗅探', () {
    test('识别 EPUB（ZIP 首条目为 mimetype）', () {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = _writeFile(dir, 'book.epub', _buildEpubBytes());
      expect(sniffExtension(f.path), 'epub');
    });

    test('区分 EPUB 与 ODT（两者首条目都是 mimetype，靠内容区分）', () {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final epub = _writeFile(dir, 'a_no_ext', _buildEpubBytes());
      final odt = _writeFile(dir, 'b_no_ext', _buildOdtBytes());
      expect(sniffExtension(epub.path), 'epub');
      expect(sniffExtension(odt.path), 'odt');
    });

    test('识别 CBZ（ZIP 但无 mimetype 条目）', () {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = _writeFile(dir, 'comic.cbz', _buildCbzBytes());
      expect(sniffExtension(f.path), 'cbz');
    });

    test('识别 PDF（%PDF 魔数）', () {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = _writeFile(dir, 'doc.pdf', utf8.encode('%PDF-1.4\n%'));
      expect(sniffExtension(f.path), 'pdf');
    });

    test('识别 RTF（{\\rtf 开头）', () {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = _writeFile(dir, 'note.rtf', utf8.encode(r'{\rtf1\ansi}'));
      expect(sniffExtension(f.path), 'rtf');
    });

    test('识别纯文本为 txt', () {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = _writeFile(dir, 'novel.txt', utf8.encode('第一章 风雪惊变'));
      expect(sniffExtension(f.path), 'txt');
    });

    test('文件不存在时返回 null', () {
      expect(sniffExtension('/nonexistent/path/to/file.epub'), isNull);
    });
  });

  group('导入文件规范化', () {
    test('扩展名正常的文件原样保留，不做拷贝', () async {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = _writeFile(dir, 'book.epub', _buildEpubBytes());

      final result = await normalizeImportFiles([f], tempDir: dir);
      expect(result.length, 1);
      expect(result.first.path, f.path);
    });

    test('安卓系统分享产生的 .null 文件被修正为 .epub', () async {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      // 复刻 share_handler 安卓兜底分支的产物：MimeTypeMap 不认识 epub
      // 会得到 null 扩展名，最终文件名形如 FILE_1699000000.null
      final bad = _writeFile(dir, 'FILE_1699000000.null', _buildEpubBytes());

      final result = await normalizeImportFiles([bad], tempDir: dir);
      expect(result.length, 1);
      expect(result.first.path.toLowerCase(), endsWith('.epub'));
      // 内容与原文件一致
      expect(result.first.readAsBytesSync(), bad.readAsBytesSync());
    });

    test('无扩展名的 TXT 文件被修正为 .txt', () async {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = _writeFile(dir, 'novel_no_ext', utf8.encode('第一章'));

      final result = await normalizeImportFiles([bad], tempDir: dir);
      expect(result.length, 1);
      expect(result.first.path.toLowerCase(), endsWith('.txt'));
    });

    test('混合列表：正常文件保留、异常文件修正', () async {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final good = _writeFile(dir, 'good.epub', _buildEpubBytes());
      final bad = _writeFile(dir, 'shared.null', _buildEpubBytes());

      final result = await normalizeImportFiles([good, bad], tempDir: dir);
      expect(result.length, 2);
      expect(result.any((f) => f.path == good.path), isTrue);
      expect(result.any((f) => f.path.toLowerCase().endsWith('.epub') &&
          f.path != good.path), isTrue);
    });

    test('不存在的文件被跳过', () async {
      final dir = _makeTempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final missing = File('${dir.path}${Platform.pathSeparator}ghost.epub');

      final result = await normalizeImportFiles([missing], tempDir: dir);
      expect(result, isEmpty);
    });
  });
}
