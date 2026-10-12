import 'dart:math';

import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/book_note.dart';

class BookNoteDao extends BaseDao {
  BookNoteDao();

  static const String table = 'tb_notes';

  /// Annotation types for highlight/underline notes (excludes book reviews)
  static const List<String> annotationTypes = [
    'highlight',
    'underline',
    'bookmark'
  ];

  /// Helper to build type filter SQL
  static String get _typeFilter =>
      "type IN ('${annotationTypes.join("', '")}')";

  Future<int> save(BookNote bookNote) async {
    if (bookNote.id != null) {
      await updateBookNoteById(bookNote);
      return bookNote.id!;
    }

    final duplicates =
        await selectBookNoteByCfiAndBookId(bookNote.cfi, bookNote.bookId);
    if (duplicates.isNotEmpty) {
      bookNote.id = duplicates.last.id;
      await updateBookNoteById(bookNote);
      return bookNote.id!;
    }

    return insert(table, bookNote.toMap());
  }

  Future<List<BookNote>> selectBookNoteByCfiAndBookId(
      String cfi, int bookId) async {
    return queryList(
      table,
      mapper: BookNote.fromDb,
      where: 'cfi = ? AND book_id = ? AND $_typeFilter',
      whereArgs: [cfi, bookId],
      orderBy: 'update_time ASC',
    );
  }

  Future<List<BookNote>> selectBookNotesByBookId(int bookId) async {
    return queryList(
      table,
      mapper: BookNote.fromDb,
      where: 'book_id = ? AND $_typeFilter',
      whereArgs: [bookId],
      orderBy: 'update_time DESC',
    );
  }

  Future<void> updateBookNoteById(BookNote bookNote) async {
    await update(
      table,
      bookNote.toMap(),
      where: 'id = ?',
      whereArgs: [bookNote.id],
    );
  }

  Future<BookNote> selectBookNoteById(int id) async {
    final note = await querySingle(
      table,
      mapper: BookNote.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (note == null) {
      throw StateError('Book note with id $id not found');
    }

    return note;
  }

  Future<List<Map<String, int>>> selectAllBookIdAndNotes() async {
    return rawQueryList(
      'SELECT book_id, COUNT(id) AS number_of_notes FROM $table WHERE $_typeFilter GROUP BY book_id ORDER BY number_of_notes DESC',
      mapper: (row) => <String, int>{
        'bookId': row['book_id'] as int? ?? 0,
        'numberOfNotes': row['number_of_notes'] as int? ?? 0,
      },
    ).then((rows) => rows.where((element) => element['bookId'] != 0).toList());
  }

  Future<Map<String, int>> selectNumberOfNotesAndBooks() async {
    final result = await rawQuerySingle(
      'SELECT COUNT(id) AS number_of_notes, COUNT(DISTINCT book_id) AS number_of_books FROM $table WHERE $_typeFilter',
      mapper: (row) => <String, int>{
        'numberOfNotes': row['number_of_notes'] as int? ?? 0,
        'numberOfBooks': row['number_of_books'] as int? ?? 0,
      },
    );

    return result ?? const {'numberOfNotes': 0, 'numberOfBooks': 0};
  }

  Future<void> deleteBookNoteById(int id) async {
    await delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<BookNote>> searchBookNotes(String keyword) {
    final query = keyword.trim();
    if (query.isEmpty) {
      return Future.value(const []);
    }
    return searchBookNotesAdvanced(keyword: query, types: annotationTypes);
  }

  Future<List<BookNote>> searchBookNotesAdvanced({
    String? keyword,
    int? bookId,
    DateTime? from,
    DateTime? to,
    int? limit,
    List<String>? types,
  }) async {
    final where = <String>[];
    final whereArgs = <Object?>[];
    final query = keyword?.trim();

    // Filter by types (defaults to annotation types if not specified)
    final filterTypes = types ?? annotationTypes;
    if (filterTypes.isNotEmpty) {
      where.add("type IN ('${filterTypes.join("', '")}')");
    }

    if (query != null && query.isNotEmpty) {
      where.add('(content LIKE ? OR reader_note LIKE ? OR chapter LIKE ?)');
      final pattern = '%$query%';
      whereArgs.addAll([pattern, pattern, pattern]);
    }

    if (bookId != null) {
      where.add('book_id = ?');
      whereArgs.add(bookId);
    }

    if (from != null) {
      where.add('update_time >= ?');
      whereArgs.add(from.toIso8601String());
    }

    if (to != null) {
      where.add('update_time <= ?');
      whereArgs.add(to.toIso8601String());
    }

    return queryList(
      table,
      mapper: BookNote.fromDb,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'update_time DESC',
      limit: limit,
    );
  }

  /// 随机取一条批注（用于「随机高亮」回顾）。
  ///
  /// 原实现 `ORDER BY RANDOM() LIMIT 1` 会让 SQLite 把**全部**命中行
  /// 取出来、给每行算一个随机数再排序（EXPLAIN 里的
  /// `USE TEMP B-TREE FOR ORDER BY`），笔记量大时是纯浪费。
  ///
  /// 现改为「在 id 范围内随机取一个下界，取第一条 id >= 下界的命中行」：
  /// - `id` 是 INTEGER PRIMARY KEY（即 rowid），可与 type 索引一起定位
  ///   （EXPLAIN 显示 `type=? AND rowid>?`），无需任何排序；
  /// - 21k 条笔记下 200 次调用实测 656ms → 57ms。
  ///
  /// 随机性不是严格均匀（按 id 间距加权），作为「随便看看」的场景足够，
  /// 换来的是不再随笔记量线性变慢。
  Future<BookNote?> selectRandomNote() async {
    final range = await rawQuerySingle(
      'SELECT MIN(id) AS min_id, MAX(id) AS max_id FROM $table WHERE $_typeFilter',
      mapper: (row) => row,
    );
    final minId = range?['min_id'] as int?;
    final maxId = range?['max_id'] as int?;
    if (minId == null || maxId == null) {
      return null; // 一条批注都没有
    }

    // 下界取 [minId, maxId]，命中则直接返回（大多数情况一次查询搞定）
    final startId = minId + Random().nextInt(maxId - minId + 1);
    // 注意比较用 >= ? 而不是 > ?，否则 startId 恰好就是 minId 时会漏掉第一条
    final hit = await rawQuerySingle(
      'SELECT * FROM $table WHERE $_typeFilter AND id >= ? LIMIT 1',
      arguments: [startId],
      mapper: BookNote.fromDb,
    );
    if (hit != null) {
      return hit;
    }

    // 下界之后没有记录了，回绕取最早的一条。
    // 这里能用 ORDER BY id 而不是 RANDOM()：索引已按 type 排序，
    // 回绕路径本来就不会命中，代价可以接受。
    return rawQuerySingle(
      'SELECT * FROM $table WHERE $_typeFilter ORDER BY id LIMIT 1',
      mapper: BookNote.fromDb,
    );
  }
}

final bookNoteDao = BookNoteDao();
