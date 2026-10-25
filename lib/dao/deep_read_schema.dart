import 'package:sqflite/sqflite.dart';

/// AI 深读产物表（本地库 `local_cache.db`，第 1 版）。
///
/// 为什么放在独立的本地库而不是主库 `app_database.db`：
/// WebDAV 同步是**整库文件快照替换**（`prepareUploadSnapshot()` 用 `VACUUM INTO`
/// 打包整个 `app_database.db`，下载侧原子替换整个库文件），`lib/service/sync/**`
/// 里没有任何按表 SQL。也就是说只要这张表进主库，就一定会被同步并在对端覆盖。
/// 产品决策 #3 要求「AI 深读产物不同步、仅端内缓存」，因此单独放一个永不参与
/// 同步的本地库，同时让 sync 代码保持一行不改。
///
/// 集成方式：由 `local_cache_database.dart` 建库时调用 [applyDeepReadSchema]。

const createDeepReadArtifactSQL = '''
CREATE TABLE IF NOT EXISTS tb_deep_read_artifacts (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id       INTEGER NOT NULL,
  chapter_href  TEXT    NOT NULL DEFAULT '',
  chapter_title TEXT,
  kind          TEXT    NOT NULL,
  format        TEXT    NOT NULL DEFAULT 'markdown',
  content       TEXT    NOT NULL,
  model         TEXT,
  score         INTEGER,
  total         INTEGER,
  answered_at   TEXT,
  created_at    TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL
)
''';

/// `idx_deep_read_key` 是 UNIQUE：唯一键 = 书 × 章节 × 类型。
/// 这是「第二次点导读不再请求模型」的缓存命中前提。
const createDeepReadIndexesSQL = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_deep_read_key
  ON tb_deep_read_artifacts(book_id, chapter_href, kind);
CREATE INDEX IF NOT EXISTS idx_deep_read_book
  ON tb_deep_read_artifacts(book_id);
''';

Future<void> applyDeepReadSchema(Database db) async {
  await db.execute(createDeepReadArtifactSQL);
  await db.execute(createDeepReadIndexesSQL);
}
