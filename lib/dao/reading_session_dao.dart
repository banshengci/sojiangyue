import 'package:songjiang_reader/dao/local_cache_dao.dart';
import 'package:songjiang_reader/models/reading_session.dart';

/// 阅读会话访问层（本地库 `tb_reading_sessions`）。
///
/// 继承 [LocalCacheDao]，全部读写落在 `local_cache.db`，永不参与 WebDAV 同步。
class ReadingSessionDao extends LocalCacheDao {
  ReadingSessionDao();

  static const String table = 'tb_reading_sessions';

  /// 该书最近一次会话（按 `started_at DESC` 取 1）。
  Future<ReadingSession?> lastForBook(int bookId) async {
    final list = await queryList(
      table,
      mapper: ReadingSession.fromMap,
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'started_at DESC, id DESC',
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  /// 续接或新建一条会话。
  ///
  /// 语义：取该书最后一条会话，若本次 [s] 的 `startedAt` 距上一条 `endedAt`
  /// 不超过 [threshold]（即同属一次连续阅读，含负间隔的时钟回拨情形），
  /// 则把既有行的 `endedAt` 顺延、`durationSeconds` 累加、`endPercentage` 覆盖，
  /// 返回既有 id；否则 insert 新行并返回新 id。
  ///
  /// 阈值由调用方传入（产品决策 #4 = 15 分钟，常量在
  /// `ReadingSessionTracker.kContinueThreshold`），本层不硬编码。
  Future<int> upsertContinueOrCreate(
    ReadingSession s,
    Duration threshold,
  ) async {
    final last = await lastForBook(s.bookId);
    if (last != null &&
        last.id != null &&
        s.startedAt.difference(last.endedAt) <= threshold) {
      final merged = last.copyWith(
        // 起点保持既有会话的 started_at（整段连续阅读算一条）
        endedAt: s.endedAt,
        durationSeconds: last.durationSeconds + s.durationSeconds,
        endPercentage: s.endPercentage ?? last.endPercentage,
        chapterTitle: s.chapterTitle ?? last.chapterTitle,
      );
      await update(
        table,
        merged.toMap(),
        where: 'id = ?',
        whereArgs: [last.id],
      );
      return last.id!;
    }

    return insert(table, s.toMap());
  }

  /// 某本书的会话，最近的在前，最多 [limit] 条。
  Future<List<ReadingSession>> listByBook(int bookId, int limit) => queryList(
        table,
        mapper: ReadingSession.fromMap,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'started_at DESC',
        limit: limit,
      );

  /// [from]（含）之后的全部会话，按时间升序（供节律 / 速度聚合）。
  Future<List<ReadingSession>> listSince(DateTime from) => queryList(
        table,
        mapper: ReadingSession.fromMap,
        where: 'started_at >= ?',
        whereArgs: [from.toIso8601String()],
        orderBy: 'started_at ASC',
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
final readingSessionDao = ReadingSessionDao();
