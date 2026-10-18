import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/dao/scene_card_schema.dart';
import 'package:songjiang_reader/models/scene_card.dart';

/// 场景卡的持久化访问层。
class SceneCardDao extends BaseDao {
  SceneCardDao();

  static const String table = 'tb_scene_cards';

  /// 列出可用场景：本书的 + 通用的（book_id 为 null）。
  ///
  /// 排序：先本书、后通用；同组内按更新时间倒序（最近用过的排在前面）。
  Future<List<SceneCard>> listForBook(int bookId) {
    return rawQueryList(
      'SELECT * FROM $table '
      'WHERE book_id = ? OR book_id IS NULL '
      'ORDER BY (book_id IS NULL) ASC, updated_at DESC',
      arguments: [bookId],
      mapper: SceneCard.fromMap,
    );
  }

  Future<SceneCard?> getById(int id) => querySingle(
        table,
        mapper: SceneCard.fromMap,
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> create({
    required String name,
    required String premise,
    int? bookId,
  }) async {
    final now = DateTime.now();
    return insert(
      table,
      SceneCard(
        bookId: bookId,
        name: name,
        premise: premise,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
  }

  /// 更新场景卡（改名字或情境）。
  Future<void> updateScene(SceneCard card) =>
      update(
        table,
        {
          'name': card.name,
          'premise': card.premise,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [card.id],
      );
  /// 删除一张场景卡。
  ///
  /// 不叫 `delete`：`BaseDao.delete(table, {where, whereArgs})` 已占用该名字，
  /// 同名不同参属于非法覆写。
  Future<void> deleteScene(int id) async {
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// 建表语句（供 `_ensureBaseTables` 自检补表使用）。
  static Future<void> ensureSchema(dynamic db) async {
    await db.execute(createSceneCardSQL);
    await db.execute(createSceneCardIndexSQL);
  }
}

final sceneCardDao = SceneCardDao();
