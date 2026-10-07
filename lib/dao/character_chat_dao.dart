import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/character_chat.dart';

/// 角色对话会话 / 消息的持久化访问层，写法对齐 CharacterDao。
class CharacterChatDao extends BaseDao {
  CharacterChatDao();

  static const String tableSession = 'tb_character_chat_sessions';
  static const String tableMessage = 'tb_character_chat_messages';

  // ---- sessions ----

  Future<int> createSession({
    required int bookId,
    required String characterName,
    CharacterChatMode mode = CharacterChatMode.single,
    String? title,
  }) async {
    final now = DateTime.now();
    return insert(
      tableSession,
      CharacterChatSession(
        bookId: bookId,
        characterName: characterName,
        mode: mode,
        title: title,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
  }

  /// 某本书的会话，按最近更新在前。keyword 非空时按标题 / 人物名模糊搜索。
  Future<List<CharacterChatSession>> listSessions(
    int bookId, {
    String? keyword,
    int? limit,
  }) {
    final kw = keyword?.trim() ?? '';
    return queryList(
      tableSession,
      mapper: CharacterChatSession.fromMap,
      where: kw.isEmpty ? 'book_id = ?' : 'book_id = ? AND (title LIKE ? OR character_name LIKE ?)',
      whereArgs: kw.isEmpty ? [bookId] : [bookId, '%$kw%', '%$kw%'],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
  }

  Future<CharacterChatSession?> getSession(int id) async {
    final list = await queryList(
      tableSession,
      mapper: CharacterChatSession.fromMap,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  Future<void> updateSessionTitle(int id, String title) => update(
        tableSession,
        {'title': title, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// 刷新 updated_at（每轮对话后调用，让会话列表按活跃度排序）。
  Future<void> touchSession(int id) => update(
        tableSession,
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> deleteSession(int id) async {
    await transaction((txn) async {
      await txn.delete(
        tableMessage,
        where: 'session_id = ?',
        whereArgs: [id],
      );
      // 对局状态跟着对话一起删，否则会留下指向已删会话的孤儿记录
      await txn.delete(
        'tb_gameplay_sessions',
        where: 'chat_session_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        tableSession,
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> deleteSessions(List<int> ids) async {
    if (ids.isEmpty) return;
    await transaction((txn) async {
      for (final id in ids) {
        await txn.delete(
          tableMessage,
          where: 'session_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'tb_gameplay_sessions',
          where: 'chat_session_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          tableSession,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  // ---- messages ----

  Future<int> appendMessage({
    required int sessionId,
    required CharacterChatRole role,
    String? speaker,
    required String content,
  }) =>
      insert(
        tableMessage,
        CharacterChatMessage(
          sessionId: sessionId,
          role: role,
          speaker: speaker,
          content: content,
          createdAt: DateTime.now(),
        ).toMap(),
      );

  Future<List<CharacterChatMessage>> listMessages(int sessionId) => queryList(
        tableMessage,
        mapper: CharacterChatMessage.fromMap,
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'id ASC',
      );

  /// 供会话列表展示「最后一句话」。
  Future<CharacterChatMessage?> lastMessage(int sessionId) async {
    final list = await queryList(
      tableMessage,
      mapper: CharacterChatMessage.fromMap,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  Future<void> clearMessages(int sessionId) => delete(
        tableMessage,
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );

  /// 删除单条消息（重新生成时撤掉旧回答）。
  Future<void> deleteMessage(int id) =>
      delete(tableMessage, where: 'id = ?', whereArgs: [id]);
}

/// 全局单例（与 characterDao 一致）。
final characterChatDao = CharacterChatDao();
