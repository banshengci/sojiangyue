import 'package:sqflite/sqflite.dart';

/// 玩法对局状态表：数据库第 15 版迁移新增。
///
/// 集成方式（见 dao/database.dart）：
///  1) `currentDbVersion` 13 → 15
///  2) import 本文件
///  3) case13 末尾加 `continue case14;`，新增 case14 调 [applyGameplaySchema]
///  4) 同时把本表加进 `ensureSchemaIntegrity`（迁移中断兜底）

const createGameplaySessionSQL = '''
CREATE TABLE IF NOT EXISTS tb_gameplay_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_session_id INTEGER NOT NULL,
  mode_id TEXT NOT NULL,
  stats TEXT,
  turn INTEGER NOT NULL DEFAULT 0,
  phase_index INTEGER NOT NULL DEFAULT 0,
  secret TEXT,
  revealed INTEGER NOT NULL DEFAULT 0,
  ended INTEGER NOT NULL DEFAULT 0,
  log TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createGameplayIndexesSQL = '''
CREATE INDEX IF NOT EXISTS idx_gameplay_chat ON tb_gameplay_sessions(chat_session_id);
''';

Future<void> applyGameplaySchema(Database db) async {
  await db.execute(createGameplaySessionSQL);
  await db.execute(createGameplayIndexesSQL);
}
