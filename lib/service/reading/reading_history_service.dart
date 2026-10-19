// lib/service/reading/reading_history_service.dart
//
// 阅读面板要用的两个数：这本书读了多久、记了多少条笔记。
//
// 为什么单独放在 service 层：`widgets/` 直接 import `dao/` 违反分层规则 R1
// （见 docs/DEVELOPMENT.md 与 tool/layer_gate.py，CI 上会直接拦下来）。
// 这两个查询原先就写在面板里，属于历史遗留；挪到这里，UI 只认识 service。

import 'package:songjiang_reader/dao/book_note.dart';
import 'package:songjiang_reader/dao/reading_time.dart';
import 'package:songjiang_reader/models/book_note.dart';

/// 这本书累计阅读了多少秒（统计失败时由调用方兜底）。
Future<int> totalReadingSecondsOf(int bookId) =>
    readingTimeDao.selectTotalReadingTimeByBookId(bookId);

/// 这本书的全部笔记（导出与计数共用同一次查询）。
Future<List<BookNote>> bookNotesOf(int bookId) =>
    bookNoteDao.selectBookNotesByBookId(bookId);
