import 'package:sqflite/sqflite.dart';

/// 松江阅角色对话数据层：数据库第 12 版迁移新增的 2 张表。
///
/// 集成方式（见 dao/database.dart）：
///  1) `const int currentDbVersion = 11;` → `12`
///  2) import 本文件
///  3) 在 case10 块末尾追加 `continue case11;`，再新增
///       case11:
///       case 11:
///         await applyCharacterChatSchema(db);

const createCharacterChatSessionSQL = '''
CREATE TABLE IF NOT EXISTS tb_character_chat_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  book_id INTEGER NOT NULL,
  character_name TEXT NOT NULL,
  title TEXT,
  mode TEXT NOT NULL DEFAULT 'single',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const createCharacterChatMessageSQL = '''
CREATE TABLE IF NOT EXISTS tb_character_chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL,
  role TEXT NOT NULL,
  speaker TEXT,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL
)
''';

const createCharacterChatIndexesSQL = '''
CREATE INDEX IF NOT EXISTS idx_chat_session_book ON tb_character_chat_sessions(book_id);
CREATE INDEX IF NOT EXISTS idx_chat_session_updated ON tb_character_chat_sessions(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_msg_session ON tb_character_chat_messages(session_id);
''';

Future<void> applyCharacterChatSchema(Database db) async {
  await db.execute(createCharacterChatSessionSQL);
  await db.execute(createCharacterChatMessageSQL);
  await db.execute(createCharacterChatIndexesSQL);
}
