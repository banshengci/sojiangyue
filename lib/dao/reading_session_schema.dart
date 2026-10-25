import 'package:sqflite/sqflite.dart';

/// 阅读会话表（本地库 `local_cache.db`，第 1 版）。
///
/// 一次「坐下来连续读一段」= 一条会话。它补的是 `tb_reading_time` 缺的那半张版图：
/// 主库只记「哪本书 × 哪天 × 多少秒」，没有会话粒度、没有进度区间，
/// 因此算不出「每小时读多少页」「通常几点读」「卡住的书」这类洞察。
///
/// 为什么不进主库：这张表是**本设备**的行为数据，且产品决策 #3 要求不随
/// WebDAV 同步。它和 `tb_deep_read_artifacts` 同住在永不参与同步的本地库里。
///
/// 集成方式：由 `local_cache_database.dart` 建库时调用 [applyReadingSessionSchema]。

const createReadingSessionSQL = '''
CREATE TABLE IF NOT EXISTS tb_reading_sessions (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id          INTEGER NOT NULL,
  started_at       TEXT    NOT NULL,
  ended_at         TEXT    NOT NULL,
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  start_percentage REAL,
  end_percentage   REAL,
  chapter_title    TEXT,
  created_at       TEXT    NOT NULL
)
''';

const createReadingSessionIndexesSQL = '''
CREATE INDEX IF NOT EXISTS idx_rs_book_time
  ON tb_reading_sessions(book_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_rs_started
  ON tb_reading_sessions(started_at);
''';

Future<void> applyReadingSessionSchema(Database db) async {
  await db.execute(createReadingSessionSQL);
  await db.execute(createReadingSessionIndexesSQL);
}
