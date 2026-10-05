import 'package:sqflite/sqflite.dart';

/// 松江阅 P0 角色 / 关系 / 设定数据层：数据库第 11 版迁移新增的 4 张表。
///
/// 集成方式（见 README）：
///  1) 修改 dao/database.dart：`const int currentDbVersion = 10;` → `11`
///  2) 在 database.dart 顶部的 import 中加入本文件
///  3) 在 onUpgradeDatabase 的 `case 9:` 块末尾追加：
///       continue case10;
///     case10:
///     case 10:
///       await applyCharacterSchema(db);
/// 新建库在 case0 级联到 case10 时会自动建表；老用户从 v10 升级时也只跑 case10。

const createCharacterCardSQL = '''
CREATE TABLE IF NOT EXISTS tb_character_cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  aliases TEXT,
  gender TEXT,
  role TEXT,
  importance INTEGER NOT NULL DEFAULT 50,
  personality TEXT,
  background TEXT,
  motivation TEXT,
  appearance TEXT,
  first_appearance_chapter TEXT,
  description TEXT,
  source TEXT NOT NULL DEFAULT 'ai_distill',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createCharacterRelationSQL = '''
CREATE TABLE IF NOT EXISTS tb_character_relations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  source_name TEXT NOT NULL,
  target_name TEXT NOT NULL,
  relation_type TEXT,
  trust INTEGER NOT NULL DEFAULT 0,
  affection INTEGER NOT NULL DEFAULT 0,
  power_gap INTEGER NOT NULL DEFAULT 0,
  conflict_point TEXT,
  hidden_attitude TEXT,
  note TEXT,
  source TEXT NOT NULL DEFAULT 'ai_distill',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createWorldSettingSQL = '''
CREATE TABLE IF NOT EXISTS tb_world_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  source TEXT NOT NULL DEFAULT 'ai_distill',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createTimelineEventSQL = '''
CREATE TABLE IF NOT EXISTS tb_timeline_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  chapter TEXT,
  title TEXT NOT NULL,
  description TEXT,
  time_note TEXT,
  source TEXT NOT NULL DEFAULT 'ai_distill',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createCharacterIndexesSQL = '''
CREATE INDEX IF NOT EXISTS idx_char_card_book ON tb_character_cards(book_id);
CREATE INDEX IF NOT EXISTS idx_char_card_name ON tb_character_cards(book_id, name);
CREATE INDEX IF NOT EXISTS idx_char_rel_book ON tb_character_relations(book_id);
CREATE INDEX IF NOT EXISTS idx_char_rel_pair ON tb_character_relations(book_id, source_name, target_name);
CREATE INDEX IF NOT EXISTS idx_world_book ON tb_world_settings(book_id);
CREATE INDEX IF NOT EXISTS idx_timeline_book ON tb_timeline_events(book_id);
''';

Future<void> applyCharacterSchema(Database db) async {
  await db.execute(createCharacterCardSQL);
  await db.execute(createCharacterRelationSQL);
  await db.execute(createWorldSettingSQL);
  await db.execute(createTimelineEventSQL);
  await db.execute(createCharacterIndexesSQL);
}
