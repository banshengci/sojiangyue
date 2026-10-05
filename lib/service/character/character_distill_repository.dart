import 'dart:io';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/epub_text_extractor.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把一本书的章节文本喂给蒸馏服务。
///
/// **TXT** 按章切分（中文网文最常见）；**EPUB** 经 `extractEpubChapters`
/// 解压后按 OPF 的 manifest/spine 取章节并清洗为纯文本。其他格式暂抛 [UnsupportedError]。
class CharacterDistillRepository {
  CharacterDistillRepository({required this.bookDao});

  final BookDao bookDao;

  static final RegExp _chapterRegex = RegExp(
    r'(?:^|\n)\s*(?:第[一二三四五六七八九十百千0-9]+[章回卷节部集篇]|Chapter\s*\d+|第\s*\d+\s*[章回卷节])\b',
    caseSensitive: false,
  );

  Future<List<BookChapter>> getChapters(int bookId) async {
    final book = await bookDao.selectBookById(bookId);
    final path = book.fileFullPath;
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('书籍文件不存在: $path');
    }
    if (path.toLowerCase().endsWith('.epub')) {
      return extractEpubChapters(path);
    }
    if (!path.toLowerCase().endsWith('.txt')) {
      throw UnsupportedError(
        '当前蒸馏切片仅支持 TXT 与 EPUB；其他格式暂不支持（见 P0 集成说明）。',
      );
    }
    final raw = await file.readAsString();
    return _splitTxt(raw);
  }

  List<BookChapter> _splitTxt(String text) {
    final matches = _chapterRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return [BookChapter(title: '全文', text: text)];
    }
    final chapters = <BookChapter>[];
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].start;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : text.length;
      final heading = text.substring(start, matches[i].end).trim();
      final body = text.substring(matches[i].end, end).trim();
      if (body.isNotEmpty) {
        chapters.add(BookChapter(title: heading, text: body));
      }
    }
    SjLog.info('CharacterDistill: 切出 ${chapters.length} 章');
    return chapters;
  }
}
