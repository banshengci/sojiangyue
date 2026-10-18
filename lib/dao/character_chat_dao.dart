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
    CharacterParticipation participation = CharacterParticipation.spectator,
    String? userPersona,
    String? title,
  }) async {
    final now = DateTime.now();
    return insert(
      tableSession,
      CharacterChatSession(
        bookId: bookId,
        characterName: characterName,
        mode: mode,
        participation: participation,
        userPersona: userPersona,
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
  /// 取 id 大于 [afterId] 的消息（升序），用于增量折叠记忆。
  ///
  /// 记忆是"压到某条消息为止"的：`memory_upto_message_id` 记录了上次压到哪，
  /// 下次只处理它之后的，避免把同一段对话反复压缩。
  Future<List<CharacterChatMessage>> listMessagesAfter(
    int sessionId, {
    int afterId = 0,
    int? limit,
  }) =>
      queryList(
        tableMessage,
        mapper: CharacterChatMessage.fromMap,
        where: 'session_id = ? AND id > ?',
        whereArgs: [sessionId, afterId],
        orderBy: 'id ASC',
        limit: limit,
      );

  /// 写入折叠后的记忆，以及"已压到哪条消息"。
  Future<void> updateMemory(
    int sessionId, {
    required String summary,
    required int uptoMessageId,
  }) =>
      update(
        tableSession,
        {
          'memory_summary': summary,
          'memory_upto_message_id': uptoMessageId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

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

  /// 从某个位置分出一个新会话（快照式分支）。
  ///
  /// 做成**快照**而不是消息树：改动集中、可回滚，先用最小代价把交互验证出来。
  /// 将来要升级成真正的分支树，迁移路径是给会话加 `parent_session_id` /
  /// `parent_message_id`，再把这里换成"只记录分叉点"。
  ///
  /// [atMessageId] 为空表示整段复制到当前末尾；否则只复制 id ≤ 它的消息。
  Future<int> forkSession(int sourceSessionId, {int? atMessageId}) async {
    final src = await getSession(sourceSessionId);
    if (src == null) {
      throw StateError('源会话不存在: $sourceSessionId');
    }

    final all = await listMessages(sourceSessionId);
    final kept = atMessageId == null
        ? all
        : all.where((m) => (m.id ?? 0) <= atMessageId).toList();

    final now = DateTime.now();
    // 记忆先不写：它的 memory_upto 指向的是**旧会话**的消息 id，
    // 必须等消息复制完、拿到新会话里的最后一条 id 再回填。
    final newSessionId = await insert(
      tableSession,
      CharacterChatSession(
        bookId: src.bookId,
        characterName: src.characterName,
        mode: src.mode,
        participation: src.participation,
        userPersona: src.userPersona,
        parentSessionId: sourceSessionId,
        title: '${src.displayTitle} · 分支',
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );

    int? newLastId;
    for (final m in kept) {
      newLastId = await insert(tableMessage, {
        'session_id': newSessionId,
        'role': m.role.code,
        'speaker': m.speaker,
        'content': m.content,
        'created_at': m.createdAt.toIso8601String(),
      });
    }

    final carried = memoryForFork(
      summary: src.memorySummary,
      upto: src.memoryUptoMessageId,
      atMessageId: atMessageId,
    );
    if (carried != null && newLastId != null) {
      await updateMemory(
        newSessionId,
        summary: carried,
        uptoMessageId: newLastId,
      );
    }

    return newSessionId;
  }

  /// 改姿态与身份（会话中途也能换"我在这一局的位置"）。
  Future<void> updateParticipation(
    int sessionId, {
    required CharacterParticipation participation,
    String? userPersona,
  }) =>
      update(
        tableSession,
        {
          'participation': participation.code,
          'user_persona': userPersona,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

  /// 从 [parentId] 分出去的会话（含多层分叉的直接子代）。
  Future<List<CharacterChatSession>> listBranches(int parentId) => queryList(
        tableSession,
        mapper: CharacterChatSession.fromMap,
        where: 'parent_session_id = ?',
        whereArgs: [parentId],
        orderBy: 'id ASC',
      );

  /// 一路向上找到主线（parent 为空的会话）。
  ///
  /// 多层分叉时「回到主线」必须跳到根，而不是只回上一层——
  /// 否则用户在 A→B→C 里点"回到主线"会停在 B，还是分支。
  Future<CharacterChatSession> rootOf(CharacterChatSession session) async {
    var current = session;
    // 防御成环：万一数据被写坏，最多走 64 层就停
    for (var i = 0; i < 64; i++) {
      final parentId = current.parentSessionId;
      if (parentId == null) return current;
      final parent = await getSession(parentId);
      if (parent == null) return current;
      current = parent;
    }
    return current;
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
