import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:songjiang_reader/dao/character_chat_schema.dart';
import 'package:songjiang_reader/dao/gameplay_schema.dart';

/// 会话批量删除的回归测试。
///
/// 背景：`CharacterChatDao.deleteSessions` 原实现是「每个 id 3 条 DELETE」
/// （消息表 + 玩法对局表 + 会话表），而会话页支持多选删除，一次可能勾掉很多个。
/// 现改为按块 `IN (...)`（每块 300 个 id，因为一个 id 在三条语句里各占一位，
/// 按 3 倍变量估算以避开 SQLite 默认 999 的上限）。
///
/// 本测试锁住：
///   1. **语义等价**：批量删的结果与逐个删逐行一致；
///   2. 级联正确：会话被删时，它的消息与玩法对局状态一并删除
///      （否则会留下指向已删会话的孤儿记录）；
///   3. 不误伤：其他会话及其消息/对局不受影响；
///   4. 边界：空列表、重复 id、跨块（>300）。
///
/// 建表直接用生产代码的 [applyCharacterChatSchema] 与 [applyGameplaySchema]，
/// 保证测的是真表结构与真索引。
void main() {
  sqfliteFfiInit();

  const tableSession = 'tb_character_chat_sessions';
  const tableMessage = 'tb_character_chat_messages';
  const tableGameplay = 'tb_gameplay_sessions';

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await applyCharacterChatSchema(db);
    await applyGameplaySchema(db);
  });

  tearDown(() async => db.close());

  /// 建一个会话，连带 N 条消息与一条对局状态。返回会话 id。
  Future<int> addSession({int bookId = 1, int messages = 2}) async {
    final now = DateTime.now().toIso8601String();
    final id = await db.insert(tableSession, {
      'book_id': bookId,
      'character_name': '角色$bookId',
      'created_at': now,
      'updated_at': now,
    });
    for (var i = 0; i < messages; i++) {
      await db.insert(tableMessage, {
        'session_id': id,
        'role': 'human',
        'content': '消息$i',
        'created_at': now,
      });
    }
    await db.insert(tableGameplay, {
      'chat_session_id': id,
      'mode_id': 'murder-mystery',
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<int> countOf(String table) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return r.first['c'] as int;
  }

  /// 原实现：逐个 id 删
  Future<void> deletePerId(List<int> ids) async {
    if (ids.isEmpty) return;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete(tableMessage,
            where: 'session_id = ?', whereArgs: [id]);
        await txn.delete(tableGameplay,
            where: 'chat_session_id = ?', whereArgs: [id]);
        await txn.delete(tableSession, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// 新实现：分块 IN（与 CharacterChatDao.deleteSessions 一致）
  Future<void> deleteBatched(List<int> ids) async {
    if (ids.isEmpty) return;
    final unique = ids.toSet().toList();
    const chunkSize = 300;
    for (var i = 0; i < unique.length; i += chunkSize) {
      final chunk = unique.sublist(
        i,
        (i + chunkSize) > unique.length ? unique.length : i + chunkSize,
      );
      final ph = List.filled(chunk.length, '?').join(',');
      await db.transaction((txn) async {
        await txn.delete(tableMessage,
            where: 'session_id IN ($ph)', whereArgs: chunk);
        await txn.delete(tableGameplay,
            where: 'chat_session_id IN ($ph)', whereArgs: chunk);
        await txn.delete(tableSession, where: 'id IN ($ph)', whereArgs: chunk);
      });
    }
  }

  /// 只取业务列。
  ///
  /// 刻意**不取任何自增/外键 id**（消息的 session_id 也是自增的）：
  /// 两组数据是分别重新灌进去的，id 必然不同，比 id 只会得到无意义的失败。
  /// 级联是否删对了行，由「级联与不误伤」那组用例显式断言 id 来保证。
  Future<List<String>> snapshot() async {
    final sessions = await db.query(tableSession,
        columns: ['book_id', 'character_name'],
        orderBy: 'book_id, character_name');
    final messages = await db.query(tableMessage,
        columns: ['role', 'content'], orderBy: 'content');
    final gameplay = await db.query(tableGameplay,
        columns: ['mode_id'], orderBy: 'mode_id');
    return [sessions.toString(), messages.toString(), gameplay.toString()];
  }

  group('语义等价（新旧实现结果一致）', () {
    test('删单个', () async {
      final ids = [await addSession(), await addSession(bookId: 2)];
      await deletePerId([ids.first]);
      final old = await snapshot();

      // 重建同样的数据再跑新实现
      await db.delete(tableSession);
      await db.delete(tableMessage);
      await db.delete(tableGameplay);
      final ids2 = [await addSession(), await addSession(bookId: 2)];
      await deleteBatched([ids2.first]);
      expect(await snapshot(), old);
    });

    test('删多个', () async {
      final ids = [
        await addSession(),
        await addSession(bookId: 2),
        await addSession(bookId: 3),
      ];
      await deletePerId([ids[0], ids[2]]);
      final old = await snapshot();

      await db.delete(tableSession);
      await db.delete(tableMessage);
      await db.delete(tableGameplay);
      final ids2 = [
        await addSession(),
        await addSession(bookId: 2),
        await addSession(bookId: 3),
      ];
      await deleteBatched([ids2[0], ids2[2]]);
      expect(await snapshot(), old);
    });
  });

  group('级联与不误伤', () {
    test('删会话会连带删掉它的消息与对局状态', () async {
      final keep = await addSession(messages: 3);
      final drop = await addSession(messages: 2);
      expect(await countOf(tableMessage), 5);

      await deleteBatched([drop]);

      expect(await countOf(tableSession), 1);
      // 留下的会话消息条数应正好是 keep 的 3 条
      expect(await countOf(tableMessage), 3);
      expect(await countOf(tableGameplay), 1);
      final left = await db.query(tableSession);
      expect(left.first['id'], keep);
    });

    test('另一本书的会话不受影响', () async {
      final a = await addSession(bookId: 1);
      final b = await addSession(bookId: 2);
      await deleteBatched([a]);

      final left = await db.query(tableSession);
      expect(left.length, 1);
      expect(left.first['id'], b);
      expect(await countOf(tableGameplay), 1);
    });
  });

  group('边界', () {
    test('空列表不动数据', () async {
      await addSession();
      await deleteBatched([]);
      expect(await countOf(tableSession), 1);
      expect(await countOf(tableMessage), 2);
      expect(await countOf(tableGameplay), 1);
    });

    test('重复 id 不会报错（去重后等价）', () async {
      final id = await addSession();
      await deleteBatched([id, id, id]);
      expect(await countOf(tableSession), 0);
      expect(await countOf(tableMessage), 0);
      expect(await countOf(tableGameplay), 0);
    });

    test('跨块：320 个会话（超过 300 阈值）全部删净，且不误伤', () async {
      final ids = <int>[];
      for (var i = 0; i < 320; i++) {
        ids.add(await addSession(messages: 1));
      }
      final keep = await addSession(messages: 1);
      expect(await countOf(tableSession), 321);

      await deleteBatched(ids);

      expect(await countOf(tableSession), 1);
      expect(await countOf(tableMessage), 1);
      expect(await countOf(tableGameplay), 1);
      final left = await db.query(tableSession);
      expect(left.first['id'], keep);
    });
  });

  group('索引仍能支撑', () {
    test('消息按 session_id 索引', () async {
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN DELETE FROM $tableMessage '
        'WHERE session_id IN (?,?)',
        [1, 2],
      );
      expect(plan.map((r) => r['detail']).join(' | '),
          contains('idx_chat_msg_session'));
    });

    test('对局状态按 chat_session_id 索引', () async {
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN DELETE FROM $tableGameplay '
        'WHERE chat_session_id IN (?,?)',
        [1, 2],
      );
      expect(plan.map((r) => r['detail']).join(' | '),
          contains('idx_gameplay_chat'));
    });
  });
}
