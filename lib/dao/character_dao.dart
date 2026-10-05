import 'package:sqflite/sqflite.dart';

import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';

/// 角色卡 / 关系 / 世界观 / 时间线 的持久化访问层，对齐既有 BookDao / BaseDao 写法。
class CharacterDao extends BaseDao {
  CharacterDao();

  static const String tableCard = 'tb_character_cards';
  static const String tableRelation = 'tb_character_relations';
  static const String tableWorld = 'tb_world_settings';
  static const String tableTimeline = 'tb_timeline_events';

  // ---- characters ----

  Future<int> saveCharacter(CharacterCard card) async {
    final now = DateTime.now();
    if (card.id != null) {
      await update(
        tableCard,
        card.copyWith(updatedAt: now).toMap(),
        where: 'id = ?',
        whereArgs: [card.id],
      );
      return card.id!;
    }
    return insert(tableCard, card.copyWith(updatedAt: now).toMap());
  }

  Future<void> batchSaveCharacters(List<CharacterCard> cards) async {
    await transaction((txn) async {
      for (final c in cards) {
        await txn.insert(tableCard, c.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<CharacterCard>> getCharacters(int bookId) => queryList(
        tableCard,
        mapper: CharacterCard.fromMap,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'importance DESC, name ASC',
      );

  Future<CharacterCard?> getCharacter(int bookId, String name) => querySingle(
        tableCard,
        mapper: CharacterCard.fromMap,
        where: 'book_id = ? AND name = ?',
        whereArgs: [bookId, name],
      );

  // ---- relations ----

  Future<void> batchSaveRelations(List<CharacterRelation> relations) async {
    await transaction((txn) async {
      for (final r in relations) {
        await txn.insert(tableRelation, r.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<CharacterRelation>> getRelations(int bookId) => queryList(
        tableRelation,
        mapper: CharacterRelation.fromMap,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'abs(trust) + abs(affection) DESC',
      );

  Future<List<CharacterRelation>> getRelationsForCharacter(
    int bookId,
    String name,
  ) =>
      queryList(
        tableRelation,
        mapper: CharacterRelation.fromMap,
        where: 'book_id = ? AND (source_name = ? OR target_name = ?)',
        whereArgs: [bookId, name, name],
      );

  // ---- world settings ----

  Future<void> batchSaveWorldSettings(List<WorldSetting> settings) async {
    await transaction((txn) async {
      for (final s in settings) {
        await txn.insert(tableWorld, s.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<WorldSetting>> getWorldSettings(int bookId) => queryList(
        tableWorld,
        mapper: WorldSetting.fromMap,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'category ASC, name ASC',
      );

  // ---- timeline ----

  Future<void> batchSaveTimeline(List<TimelineEvent> events) async {
    await transaction((txn) async {
      for (final e in events) {
        await txn.insert(tableTimeline, e.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<TimelineEvent>> getTimeline(int bookId) => queryList(
        tableTimeline,
        mapper: TimelineEvent.fromMap,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'id ASC',
      );

  /// 重蒸馏时整图替换：在单个事务里清空旧图并写入新图，避免残留脏数据。
  Future<void> replaceBookGraph({
    required int bookId,
    required List<CharacterCard> characters,
    required List<CharacterRelation> relations,
    required List<WorldSetting> settings,
    required List<TimelineEvent> events,
  }) async {
    await transaction((txn) async {
      await txn.delete(tableCard, where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete(tableRelation, where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete(tableWorld, where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete(tableTimeline, where: 'book_id = ?', whereArgs: [bookId]);
      for (final c in characters) {
        await txn.insert(tableCard, c.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in relations) {
        await txn.insert(tableRelation, r.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final s in settings) {
        await txn.insert(tableWorld, s.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final e in events) {
        await txn.insert(tableTimeline, e.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteGraph(int bookId) async {
    await transaction((txn) async {
      await txn.delete(tableCard, where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete(tableRelation, where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete(tableWorld, where: 'book_id = ?', whereArgs: [bookId]);
      await txn.delete(tableTimeline, where: 'book_id = ?', whereArgs: [bookId]);
    });
  }
}

final characterDao = CharacterDao();
