import 'package:sqflite/sqflite.dart';

import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/utils/log/common.dart';

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

  /// 批量删除人物（连同引用它们的关系一起清掉）。
  ///
  /// 用于「蒸馏后挑选」：一次抽出几百个龙套时，用户勾掉不要的，
  /// 关系表里指向这些人的连线也必须一起删，否则关系图会出现连不上人的孤立线。
  Future<void> deleteCharacters(int bookId, List<String> names) async {
    if (names.isEmpty) return;
    await transaction((txn) async {
      for (final name in names) {
        await txn.delete(
          tableCard,
          where: 'book_id = ? AND name = ?',
          whereArgs: [bookId, name],
        );
        await txn.delete(
          tableRelation,
          where: 'book_id = ? AND (source_name = ? OR target_name = ?)',
          whereArgs: [bookId, name, name],
        );
      }
    });
    SjLog.info('CharacterDao: 已删除 ${names.length} 个人物（含其关系）');
  }

  /// 保存人物卡，并在改名时同步所有「按姓名关联」的引用。
  ///
  /// 关系表（tb_character_relations）与对话会话（tb_character_chat_sessions）
  /// 都存在人物**姓名**而不是 id。用户在资料校对页改了名字，若不同步更新，
  /// 这个人物的全部关系会瞬间失联、已有对话也找不到对应人物。
  Future<void> saveCharacterWithRename({
    required CharacterCard card,
    required String previousName,
  }) async {
    final now = DateTime.now();
    final map = card.copyWith(updatedAt: now).toMap();
    final newName = card.name.trim();
    final oldName = previousName.trim();
    final renamed =
        oldName.isNotEmpty && newName.isNotEmpty && oldName != newName;

    await transaction((txn) async {
      if (card.id != null) {
        await txn.update(tableCard, map, where: 'id = ?', whereArgs: [card.id]);
      } else {
        await txn.insert(tableCard, map);
      }

      if (!renamed) return;

      await txn.update(
        tableRelation,
        {'source_name': newName},
        where: 'book_id = ? AND source_name = ?',
        whereArgs: [card.bookId, oldName],
      );
      await txn.update(
        tableRelation,
        {'target_name': newName},
        where: 'book_id = ? AND target_name = ?',
        whereArgs: [card.bookId, oldName],
      );
      // 单人会话标题跟着改；群聊/穿越会话存的是 "bookId:姓名" 串，不会被误伤。
      await txn.update(
        'tb_character_chat_sessions',
        {'character_name': newName},
        where: 'book_id = ? AND character_name = ?',
        whereArgs: [card.bookId, oldName],
      );
    });
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
