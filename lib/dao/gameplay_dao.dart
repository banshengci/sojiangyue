import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';

/// 玩法对局状态访问层。
class GameplayDao extends BaseDao {
  GameplayDao();

  static const String table = 'tb_gameplay_sessions';

  Future<GameplaySession?> getByChatSession(int chatSessionId) async {
    final list = await queryList(
      table,
      mapper: GameplaySession.fromMap,
      where: 'chat_session_id = ?',
      whereArgs: [chatSessionId],
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  Future<int> save(GameplaySession session) async {
    final now = DateTime.now();
    final map = session.copyWith(updatedAt: now).toMap();
    if (session.id != null) {
      await update(table, map, where: 'id = ?', whereArgs: [session.id]);
      return session.id!;
    }
    return insert(table, map);
  }

  Future<void> deleteByChatSession(int chatSessionId) => delete(
        table,
        where: 'chat_session_id = ?',
        whereArgs: [chatSessionId],
      );
}

final gameplayDao = GameplayDao();
