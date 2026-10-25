import 'package:sqflite/sqflite.dart';

/// 角色养成档案 + 贡献账本：数据库第 16 版迁移新增。
///
/// 为什么是「两张表」而不是一张：
/// `tb_character_profile` 是展示用的聚合结果，`tb_character_profile_events`
/// 是每局结算的贡献账本。**删角色对话会连带删掉 `tb_gameplay_sessions` 行**
/// （见 `character_chat_dao.dart` 的 `deleteSession` / `deleteSessions` 事务级联），
/// 若档案直接从对局表重算，用户仅仅「清理聊天记录」就会导致羁绊静默回退。
/// 账本刻意**不对 `gameplay_session_id` 建外键**，因此能活得比对局行更久 ——
/// 这是产品裁定「羁绊一经获得即保留」的唯一可靠地基。
///
/// 集成方式（见 dao/database.dart）：
///  1) `currentDbVersion` 15 → 16
///  2) import 本文件
///  3) case14 末尾加 `continue case15;`，新增 case15 调 [applyCharacterProfileSchema]
///  4) 同时把它加进 `ensureSchemaIntegrity`（迁移中断兜底）

const createCharacterProfileSQL = '''
CREATE TABLE IF NOT EXISTS tb_character_profile (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  character_name  TEXT    NOT NULL,
  book_id         INTEGER,
  book_title      TEXT,
  bond_level      INTEGER NOT NULL DEFAULT 1,
  affection_total INTEGER NOT NULL DEFAULT 0,
  session_count   INTEGER NOT NULL DEFAULT 0,
  turn_count      INTEGER NOT NULL DEFAULT 0,
  last_played_at  TEXT,
  milestones      TEXT,
  created_at      TEXT    NOT NULL,
  updated_at      TEXT    NOT NULL
)
''';

/// 一局一条的贡献账本（不建外键，见文件头说明）。
const createCharacterProfileEventSQL = '''
CREATE TABLE IF NOT EXISTS tb_character_profile_events (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  gameplay_session_id INTEGER NOT NULL,
  character_name      TEXT    NOT NULL,
  book_id             INTEGER,
  book_title          TEXT,
  mode_id             TEXT,
  affection_delta     INTEGER NOT NULL DEFAULT 0,
  turn_count          INTEGER NOT NULL DEFAULT 0,
  settled_at          TEXT    NOT NULL,
  created_at          TEXT    NOT NULL
)
''';

/// 索引全部 IF NOT EXISTS，便于每次开库幂等自检。
///
/// `idx_char_profile_name` 是 UNIQUE：产品决策 #1 明确档案作用域是
/// 「读者 × 角色」全局共享，同一人物在跨书茶馆与多本书里共用一条羁绊。
/// `idx_char_event_session` 是 UNIQUE：重复结算同一个 session 只覆盖不追加，
/// 这是整套结算幂等的根基。
const createCharacterProfileIndexesSQL = '''
CREATE UNIQUE INDEX IF NOT EXISTS idx_char_profile_name
  ON tb_character_profile(character_name);
CREATE INDEX IF NOT EXISTS idx_char_profile_affection
  ON tb_character_profile(affection_total DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_char_event_session
  ON tb_character_profile_events(gameplay_session_id);
CREATE INDEX IF NOT EXISTS idx_char_event_name
  ON tb_character_profile_events(character_name);
''';

Future<void> applyCharacterProfileSchema(Database db) async {
  await db.execute(createCharacterProfileSQL);
  await db.execute(createCharacterProfileEventSQL);
  await db.execute(createCharacterProfileIndexesSQL);
}
