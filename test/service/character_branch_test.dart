import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_chat.dart';

/// 分支的父指针。
///
/// 快照式分叉只复制数据，不会自动记录"从哪来的"。没有 `parentSessionId`，
/// 就无法回答「回到主线」和「还有哪些同源分支」——那正是用户要的两件事。
void main() {
  CharacterChatSession session({
    int? id,
    int? parentSessionId,
    String name = '林黛玉',
  }) =>
      CharacterChatSession(
        id: id,
        bookId: 1,
        characterName: name,
        parentSessionId: parentSessionId,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  test('主线没有父会话', () {
    expect(session().parentSessionId, isNull);
  });

  test('toMap / fromMap 往返不丢父指针', () {
    final s = session(id: 5, parentSessionId: 3);
    final back = CharacterChatSession.fromMap(s.toMap());
    expect(back.parentSessionId, 3);
  });

  test('copyWith 能改父指针（分叉时用）', () {
    final s = session(id: 5);
    final forked = s.copyWith(parentSessionId: 9);
    expect(forked.parentSessionId, 9);
    // 其余字段不变
    expect(forked.id, 5);
    expect(forked.characterName, '林黛玉');
  });

  test('旧数据没有该列时按主线处理，不抛异常', () {
    final map = session(id: 1).toMap()..remove('parent_session_id');
    expect(CharacterChatSession.fromMap(map).parentSessionId, isNull);
  });
}
