import 'package:songjiang_reader/dao/local_cache_dao.dart';
import 'package:songjiang_reader/models/deep_read_artifact.dart';

/// AI 深读产物访问层（本地库 `tb_deep_read_artifacts`）。
///
/// 继承 [LocalCacheDao]，全部读写落在 `local_cache.db`，永不参与 WebDAV 同步。
class DeepReadDao extends LocalCacheDao {
  DeepReadDao();

  static const String table = 'tb_deep_read_artifacts';

  /// 按唯一键（书 × 章节 × 类型）取一条产物。
  Future<DeepReadArtifact?> getByKey(
    int bookId,
    String chapterHref,
    DeepReadKind kind,
  ) async {
    final list = await queryList(
      table,
      mapper: DeepReadArtifact.fromMap,
      where: 'book_id = ? AND chapter_href = ? AND kind = ?',
      whereArgs: [bookId, chapterHref, kind.name],
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  /// UPSERT：按 `(book_id, chapter_href, kind)` 冲突则覆盖，并更新 `updated_at`。
  ///
  /// 用显式 `ON CONFLICT(...) DO UPDATE`，避免 `ConflictAlgorithm.replace` 换掉 `id`。
  /// `created_at` 不在更新列里，故覆盖时保留首次生成时间。
  Future<int> upsert(DeepReadArtifact a) async {
    final database = await this.database;
    return database.rawInsert(
      '''
      INSERT INTO $table (
        book_id, chapter_href, chapter_title, kind, format, content, model,
        score, total, answered_at, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(book_id, chapter_href, kind) DO UPDATE SET
        chapter_title = excluded.chapter_title,
        format        = excluded.format,
        content       = excluded.content,
        model         = excluded.model,
        score         = excluded.score,
        total         = excluded.total,
        answered_at   = excluded.answered_at,
        updated_at    = excluded.updated_at
      ''',
      [
        a.bookId,
        a.chapterHref,
        a.chapterTitle,
        a.kind.name,
        a.format,
        a.content,
        a.model,
        a.score,
        a.total,
        a.answeredAt?.toIso8601String(),
        a.createdAt.toIso8601String(),
        a.updatedAt.toIso8601String(),
      ],
    );
  }

  /// 某本书的全部产物，最近的在前。
  Future<List<DeepReadArtifact>> listByBook(int bookId) => queryList(
        table,
        mapper: DeepReadArtifact.fromMap,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'updated_at DESC',
      );

  /// 按书批量清理（删书级联，见 §7.4）。
  ///
  /// 空列表直接返回——不能拼出 `IN ()` 这种非法 SQL。
  Future<void> deleteByBookIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    await delete(
      table,
      where: 'book_id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}

/// 全局单例（与 characterDao 一致）。
final deepReadDao = DeepReadDao();
