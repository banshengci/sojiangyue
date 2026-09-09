import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/models/vocab_item.dart';

class VocabDao {
  static const String table = 'tb_vocab_items';

  /// 保存生词/难句；相同 term+bookId 去重。
  Future<int> save(VocabItem item) async {
    final db = await DBHelper().database;
    final existing = await db.query(
      table,
      where: 'term = ? AND IFNULL(book_id, -1) = ?',
      whereArgs: [item.term, item.bookId ?? -1],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    return db.insert(table, item.toMap());
  }

  Future<List<VocabItem>> selectAll({String? keyword}) async {
    final db = await DBHelper().database;
    final List<Map<String, dynamic>> maps;
    if (keyword == null || keyword.trim().isEmpty) {
      maps = await db.query(table, orderBy: 'create_time DESC');
    } else {
      final like = '%${keyword.trim()}%';
      maps = await db.query(
        table,
        where: 'term LIKE ? OR IFNULL(gloss, "") LIKE ? OR IFNULL(chapter, "") LIKE ?',
        whereArgs: [like, like, like],
        orderBy: 'create_time DESC',
      );
    }
    return maps.map(VocabItem.fromMap).toList();
  }

  Future<void> markReviewed(int id) async {
    final db = await DBHelper().database;
    await db.rawUpdate(
      '''
      UPDATE $table
      SET review_count = review_count + 1,
          last_review_time = ?
      WHERE id = ?
      ''',
      [DateTime.now().toIso8601String(), id],
    );
  }

  Future<void> delete(int id) async {
    final db = await DBHelper().database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await DBHelper().database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (result.first['c'] as int?) ?? 0;
  }
}

final VocabDao vocabDao = VocabDao();
