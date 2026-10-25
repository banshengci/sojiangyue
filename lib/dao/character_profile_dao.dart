import 'package:sqflite/sqflite.dart';

import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/character_profile.dart';

/// 角色养成档案访问层（主库 `tb_character_profile`）。
///
/// 档案值是**聚合结果**，真源是贡献账本 `tb_character_profile_events`。
/// [aggregateFromEvents] 只算不写；由 service 决定是否落库（§3.4）。
///
/// 事务提示（§7.3）：结算涉及「写账本 + 聚合重算 + 写档案」三件事，必须在
/// **单个事务**内完成。为此提供 `*InTx` 变体，供 service 在
/// `transaction((txn) => ...)` 内直接用 `txn` 调用，避免中途再用 DAO 取库
/// 而形成嵌套事务。
class CharacterProfileDao extends BaseDao {
  CharacterProfileDao();

  static const String table = 'tb_character_profile';

  Future<CharacterProfile?> getByName(String name) async {
    final list = await queryList(
      table,
      mapper: CharacterProfile.fromMap,
      where: 'character_name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  /// 全部档案，羁绊高的在前（用于档案页列表）。
  Future<List<CharacterProfile>> listAll() => queryList(
        table,
        mapper: CharacterProfile.fromMap,
        orderBy: 'affection_total DESC, updated_at DESC',
      );

  Future<void> deleteByName(String name) => delete(
        table,
        where: 'character_name = ?',
        whereArgs: [name],
      );

  /// UPSERT：按 `character_name` 冲突则覆盖。
  ///
  /// 用显式 `ON CONFLICT(character_name) DO UPDATE` 而非
  /// `ConflictAlgorithm.replace`——后者会换掉自增 `id`（§7.1）。
  /// `created_at` 不在更新列里，故冲突时保留首次写入值。
  Future<int> upsert(CharacterProfile p) async =>
      upsertInTx(await database, p);

  /// [upsert] 的事务版本：在给定事务 / 数据库上执行，避免复入取库锁。
  Future<int> upsertInTx(DatabaseExecutor executor, CharacterProfile p) {
    final milestones = p.toMap()['milestones'];
    return executor.rawInsert(
      '''
      INSERT INTO $table (
        character_name, book_id, book_title, bond_level, affection_total,
        session_count, turn_count, last_played_at, milestones, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(character_name) DO UPDATE SET
        book_id         = excluded.book_id,
        book_title      = excluded.book_title,
        bond_level      = excluded.bond_level,
        affection_total = excluded.affection_total,
        session_count   = excluded.session_count,
        turn_count      = excluded.turn_count,
        last_played_at  = excluded.last_played_at,
        milestones      = excluded.milestones,
        updated_at      = excluded.updated_at
      ''',
      [
        p.characterName,
        p.bookId,
        p.bookTitle,
        p.bondLevel,
        p.affectionTotal,
        p.sessionCount,
        p.turnCount,
        p.lastPlayedAt?.toIso8601String(),
        milestones,
        p.createdAt.toIso8601String(),
        p.updatedAt.toIso8601String(),
      ],
    );
  }

  /// 从账本聚合出整行档案的**计算结果**（不落库，由 service 决定是否写）。
  ///
  /// 聚合口径（§1.5）：
  ///   `affection_total = Σ affection_delta`（账本里恒 ≥ 0）
  ///   `session_count   = COUNT(*)`
  ///   `turn_count      = Σ turn_count`
  ///   `last_played_at  = MAX(settled_at)`
  /// `bond_level` / `milestones` 由上面的 `affection_total` 现算（与档位表同构）；
  /// `book_id` / `book_title` 取最近一次结算所在的书（仅展示用）。
  Future<CharacterProfile> aggregateFromEvents(String name) async =>
      aggregateFromEventsInTx(await database, name);

  /// [aggregateFromEvents] 的事务版本：在给定事务 / 数据库上执行。
  Future<CharacterProfile> aggregateFromEventsInTx(
    DatabaseExecutor executor,
    String name,
  ) async {
    final aggRows = await executor.rawQuery(
      '''
      SELECT
        COALESCE(SUM(affection_delta), 0) AS affection_total,
        COUNT(*)                          AS session_count,
        COALESCE(SUM(turn_count), 0)      AS turn_count,
        MAX(settled_at)                   AS last_played_at
      FROM $table
      WHERE character_name = ?
      ''',
      [name],
    );
    final agg = aggRows.isEmpty
        ? const <String, Object?>{}
        : aggRows.first;

    final affectionTotal = (agg['affection_total'] as num?)?.toInt() ?? 0;
    final sessionCount = (agg['session_count'] as num?)?.toInt() ?? 0;
    final turnCount = (agg['turn_count'] as num?)?.toInt() ?? 0;
    final lastPlayedAt =
        DateTime.tryParse(agg['last_played_at'] as String? ?? '');

    int? bookId;
    String? bookTitle;
    if (sessionCount > 0) {
      final latest = await executor.rawQuery(
        '''
        SELECT book_id, book_title
        FROM $table
        WHERE character_name = ?
        ORDER BY settled_at DESC, id DESC
        LIMIT 1
        ''',
        [name],
      );
      if (latest.isNotEmpty) {
        bookId = (latest.first['book_id'] as num?)?.toInt();
        bookTitle = latest.first['book_title'] as String?;
      }
    }

    final now = DateTime.now();
    return CharacterProfile(
      characterName: name,
      bookId: bookId,
      bookTitle: bookTitle,
      bondLevel: CharacterProfile.bondLevelOf(affectionTotal),
      affectionTotal: affectionTotal,
      sessionCount: sessionCount,
      turnCount: turnCount,
      lastPlayedAt: lastPlayedAt,
      milestones: BondMilestone.milestonesOf(affectionTotal, lastPlayedAt),
      createdAt: now,
      updatedAt: lastPlayedAt ?? now,
    );
  }
}

/// 全局单例（与 characterDao 一致）。
final characterProfileDao = CharacterProfileDao();
