import 'package:sqflite/sqflite.dart';

/// 场景卡表（造梦「场景」的持久化）。
///
/// 走「自检补表」而不是新增数据库版本：`_ensureBaseTables` 每次打开都会执行
/// 这里的 `IF NOT EXISTS` 语句，老库自然长出这张表，不必顶 currentDbVersion
/// （顶版本会牵动 DatabaseSyncManager 的版本比较，见 database.dart 里的说明）。
const createSceneCardSQL = '''
CREATE TABLE IF NOT EXISTS tb_scene_cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER,
  name TEXT NOT NULL,
  premise TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createSceneCardIndexSQL = '''
CREATE INDEX IF NOT EXISTS idx_scene_card_book ON tb_scene_cards(book_id);
''';

Future<void> applySceneCardSchema(Database db) async {
  await db.execute(createSceneCardSQL);
  await db.execute(createSceneCardIndexSQL);
}
