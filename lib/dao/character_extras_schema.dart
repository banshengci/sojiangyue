import 'package:sqflite/sqflite.dart';

/// 松江阅「造梦补齐」数据层：数据库第 13 版迁移新增的 4 张表。
///
///   - tb_self_cards       自设卡 / 开局模板（feature/cards）
///   - tb_crossover_scenes 穿越联动场景（feature/crossover）
///   - tb_knowledge_items  原著知识条目（feature/originalknowledge）
///   - tb_story_recaps     剧情回顾缓存（feature/storyrecap）
///
/// 集成方式（见 dao/database.dart）：
///  1) `const int currentDbVersion = 12;` → `13`
///  2) import 本文件
///  3) 在 case11 块末尾追加 `continue case12;`，再新增
///       case12:
///       case 12:
///         await applyCharacterExtrasSchema(db);

const createSelfCardSQL = '''
CREATE TABLE IF NOT EXISTS tb_self_cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  kind TEXT NOT NULL DEFAULT 'self',
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  tags TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createCrossoverSceneSQL = '''
CREATE TABLE IF NOT EXISTS tb_crossover_scenes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  members TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createKnowledgeItemSQL = '''
CREATE TABLE IF NOT EXISTS tb_knowledge_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  topic TEXT NOT NULL,
  summary TEXT NOT NULL,
  chapter TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createStoryRecapSQL = '''
CREATE TABLE IF NOT EXISTS tb_story_recaps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  chapter_index INTEGER NOT NULL,
  chapter_title TEXT,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
)
''';

const createCharacterExtrasIndexesSQL = '''
CREATE INDEX IF NOT EXISTS idx_self_card_book ON tb_self_cards(book_id, kind);
CREATE INDEX IF NOT EXISTS idx_knowledge_book ON tb_knowledge_items(book_id);
CREATE INDEX IF NOT EXISTS idx_recap_book ON tb_story_recaps(book_id, chapter_index);
''';

Future<void> applyCharacterExtrasSchema(Database db) async {
  await db.execute(createSelfCardSQL);
  await db.execute(createCrossoverSceneSQL);
  await db.execute(createKnowledgeItemSQL);
  await db.execute(createStoryRecapSQL);
  await db.execute(createCharacterExtrasIndexesSQL);
}
