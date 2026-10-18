import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:songjiang_reader/dao/character_chat_dao.dart';
import 'package:songjiang_reader/dao/character_chat_schema.dart';
import 'package:songjiang_reader/models/character_chat.dart';

/// DAO 层的真实读写测试（内存库）。
///
/// 补这组测试的直接原因：上一轮给 `forkSession` 加 `parentSessionId` 时，
/// 字符串替换静默失配，**父指针根本没写进去**，而当时的 314 个用例全绿——
/// 因为它们只覆盖模型的序列化往返，没有任何一条真的把数据写进库里再读回来。
///
/// 这个文件把 DAO 指到内存库（`BaseDao.useDatabaseForTest`），
/// 让"写入是否真的发生"变成可断言的事实。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await applyCharacterChatSchema(db);
    characterChatDao.useDatabaseForTest(db);
  });

  tearDown(() async {
    characterChatDao.clearDatabaseOverride();
    await db.close();
  });

  Future<int> newSession({
    CharacterParticipation participation = CharacterParticipation.spectator,
    String? userPersona,
    String name = '林黛玉',
  }) =>
      characterChatDao.createSession(
        bookId: 1,
        characterName: name,
        participation: participation,
        userPersona: userPersona,
      );

  Future<int> talk(int sessionId, {String? speaker, String text = '嗯'}) =>
      characterChatDao.appendMessage(
        sessionId: sessionId,
        role: CharacterChatRole.character,
        speaker: speaker ?? '林黛玉',
        content: text,
      );

  group('创建与读取', () {
    test('姿态与身份真的落库', () async {
      final id = await newSession(
        participation: CharacterParticipation.join,
        userPersona: '阿舟',
      );
      final s = await characterChatDao.getSession(id);
      expect(s, isNotNull);
      expect(s!.participation, CharacterParticipation.join);
      expect(s.userPersona, '阿舟');
    });

    test('默认姿态是旁观', () async {
      final s = await characterChatDao.getSession(await newSession());
      expect(s!.participation, CharacterParticipation.spectator);
      expect(s.parentSessionId, isNull);
    });
  });

  group('姿态可中途修改', () {
    test('updateParticipation 写库并保留旧身份以外的字段', () async {
      final id = await newSession();
      await characterChatDao.updateParticipation(
        id,
        participation: CharacterParticipation.roleplay,
        userPersona: '贾宝玉',
      );
      final s = await characterChatDao.getSession(id);
      expect(s!.participation, CharacterParticipation.roleplay);
      expect(s.userPersona, '贾宝玉');
      expect(s.characterName, '林黛玉');
    });
  });

  group('分叉（forkSession）', () {
    test('新会话记录父会话 —— 这正是上一轮漏写的地方', () async {
      final src = await newSession();
      final forked = await characterChatDao.forkSession(src);
      final s = await characterChatDao.getSession(forked);
      expect(s!.parentSessionId, src);
      expect(s.title, contains('分支'));
    });

    test('消息被复制，且可只复制到指定消息', () async {
      final src = await newSession();
      await talk(src, text: '第一句');
      final second = await talk(src, text: '第二句');
      await talk(src, text: '第三句');

      final all = await characterChatDao.forkSession(src);
      expect((await characterChatDao.listMessages(all)).length, 3);

      final partial =
          await characterChatDao.forkSession(src, atMessageId: second);
      final kept = await characterChatDao.listMessages(partial);
      expect(kept.length, 2);
      expect(kept.last.content, '第二句');
    });

    test('listBranches 只返回直接子代', () async {
      final src = await newSession();
      final a = await characterChatDao.forkSession(src);
      final b = await characterChatDao.forkSession(src);
      final branches = await characterChatDao.listBranches(src);
      expect(branches.map((e) => e.id).toSet(), {a, b});
    });

    test('rootOf 一路走到主线（多层分叉也回得到根）', () async {
      final root = await newSession();
      final mid = await characterChatDao.forkSession(root);
      final leaf = await characterChatDao.forkSession(mid);
      final leafSession = await characterChatDao.getSession(leaf);
      final found = await characterChatDao.rootOf(leafSession!);
      expect(found.id, root);
    });
  });

  group('记忆', () {
    test('updateMemory 写库', () async {
      final id = await newSession();
      final m1 = await talk(id, text: '甲');
      await characterChatDao.updateMemory(
        id,
        summary: '我记得甲。',
        uptoMessageId: m1,
      );
      final s = await characterChatDao.getSession(id);
      expect(s!.memorySummary, '我记得甲。');
      expect(s.memoryUptoMessageId, m1);
    });

    test('分叉点早于已压范围时丢弃记忆，晚于则沿用', () async {
      final src = await newSession();
      final m1 = await talk(src, text: '甲');
      final m2 = await talk(src, text: '乙');
      await characterChatDao.updateMemory(
        src,
        summary: '我记得甲乙。',
        uptoMessageId: m2,
      );

      // 早于已压范围 → 丢弃
      final early = await characterChatDao.forkSession(src, atMessageId: m1);
      expect((await characterChatDao.getSession(early))!.memorySummary, isNull);

      // 晚于等于已压范围 → 沿用，且进度指向新会话的最后一条
      final late = await characterChatDao.forkSession(src, atMessageId: m2);
      final lateSession = await characterChatDao.getSession(late);
      expect(lateSession!.memorySummary, '我记得甲乙。');
      final lateMsgs = await characterChatDao.listMessages(late);
      expect(lateSession.memoryUptoMessageId, lateMsgs.last.id);
    });
  });

  group('listMessagesAfter（增量折叠用）', () {
    test('只返回指定 id 之后的消息', () async {
      final id = await newSession();
      final m1 = await talk(id, text: '一');
      await talk(id, text: '二');
      await talk(id, text: '三');
      final after = await characterChatDao.listMessagesAfter(id, afterId: m1);
      expect(after.length, 2);
      expect(after.first.content, '二');
    });
  });
}
