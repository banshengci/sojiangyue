import 'package:sqflite/sqflite.dart';

import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/character_profile_event.dart';

/// 贡献账本访问层（主库 `tb_character_profile_events`）。
///
/// 一局一条，按 `gameplay_session_id` 幂等 upsert（UNIQUE 索引），
/// 是整套结算幂等的根基，也是「羁绊一经获得即保留」的真源。
///
/// 事务提示（§7.3）：结算时本表写入与档案聚合重算须在同一事务内，
/// 用 [upsertInTx] 在 `transaction((txn) => ...)` 内直接调用，避免复入取库锁。
class CharacterProfileEventDao extends BaseDao {
  CharacterProfileEventDao();

  static const String table = 'tb_character_profile_events';

  /// 该对局是否已结算过（幂等判定的读路径）。
  Future<bool> hasEvent(int gameplaySessionId) async {
    final rows = await rawQueryList<int>(
      'SELECT id FROM $table WHERE gameplay_session_id = ? LIMIT 1',
      arguments: [gameplaySessionId],
      mapper: (row) => (row['id'] as num?)?.toInt() ?? 0,
    );
    return rows.isNotEmpty;
  }

  /// 某角色的全部账本行，最近的在前。
  Future<List<CharacterProfileEvent>> listByCharacter(String name) => queryList(
        table,
        mapper: CharacterProfileEvent.fromMap,
        where: 'character_name = ?',
        whereArgs: [name],
        orderBy: 'settled_at DESC, id DESC',
      );

  /// UPSERT：按 `gameplay_session_id` 冲突则覆盖。
  ///
  /// 用显式 `ON CONFLICT(gameplay_session_id) DO UPDATE`，**不要**用
  /// `ConflictAlgorithm.replace`——后者会换掉自增 `id`（§7.1）。
  /// `created_at` 不在更新列里，故重复结算只覆盖业务字段、保留首次入库时间。
  Future<int> upsert(CharacterProfileEvent e) async =>
      upsertInTx(await database, e);

  /// [upsert] 的事务版本：在给定事务 / 数据库上执行。
  Future<int> upsertInTx(DatabaseExecutor executor, CharacterProfileEvent e) {
    return executor.rawInsert(
      '''
      INSERT INTO $table (
        gameplay_session_id, character_name, book_id, book_title, mode_id,
        affection_delta, turn_count, settled_at, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(gameplay_session_id) DO UPDATE SET
        affection_delta = excluded.affection_delta,
        turn_count      = excluded.turn_count,
        settled_at      = excluded.settled_at,
        book_id         = excluded.book_id,
        book_title      = excluded.book_title,
        mode_id         = excluded.mode_id
      ''',
      [
        e.gameplaySessionId,
        e.characterName,
        e.bookId,
        e.bookTitle,
        e.modeId,
        e.affectionDelta,
        e.turnCount,
        e.settledAt.toIso8601String(),
        e.createdAt.toIso8601String(),
      ],
    );
  }
}

/// 全局单例（与 characterDao 一致）。
final characterProfileEventDao = CharacterProfileEventDao();
