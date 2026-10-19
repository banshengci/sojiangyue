import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_modes.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';

/// 玩法状态按成员区分。
///
/// 起因：好感、信任这类值是「对谁」的。群聊里两个角色共用一个数，
/// 等于宝玉夸了黛玉一句，宝钗的好感也跟着涨——这在恋爱模拟里是硬伤。
///
/// 做法：`GameplayStatDef.perMember` 标记这类状态，状态块里写成
/// `"好感|林黛玉": 5` 形式；线索、神志等集体状态保持共享。
void main() {
  final dating = kBuiltinGameplayModes.firstWhere((m) => m.id == 'dating-sim');

  GameplaySession fresh() => GameplaySession(
        chatSessionId: 1,
        modeId: dating.id,
        stats: {for (final d in dating.stats) d.key: d.initial},
      );

  test('恋爱模拟的好感与信任都标记为按成员', () {
    final affection =
        dating.stats.firstWhere((d) => d.key == 'affection');
    final trust = dating.stats.firstWhere((d) => d.key == 'trust');
    expect(affection.perMember, isTrue, reason: '好感是「对谁」的值');
    expect(trust.perMember, isTrue, reason: '信任同样是「对谁」的值');
  });

  test('集体型状态没有被误标为按成员', () {
    final horror = kBuiltinGameplayModes.firstWhere(
      (m) => m.id == 'horror-rule',
    );
    for (final d in horror.stats) {
      expect(d.perMember, isFalse, reason: '${d.name} 是全场共享的');
    }
  });

  test('「好感|林黛玉」只改黛玉，不动集体值', () {
    final next = GameplayRuntime.apply(
      mode: dating,
      session: fresh(),
      turn: const GameplayTurn(
        displayText: '',
        deltas: {'好感|林黛玉': 5},
      ),
    ).session;
    expect(next.memberStats['affection']?['林黛玉'], 15); // 初始 10 + 5
    expect(next.stats['affection'], 10, reason: '集体值不该被改');
    expect(next.memberStats['affection']?['贾宝玉'], isNull);
  });

  test('两个人分别累积，互不影响', () {
    var s = GameplayRuntime.apply(
      mode: dating,
      session: fresh(),
      turn: const GameplayTurn(displayText: '', deltas: {'好感|林黛玉': 5}),
    ).session;
    s = GameplayRuntime.apply(
      mode: dating,
      session: s,
      turn: const GameplayTurn(displayText: '', deltas: {'好感|贾宝玉': 12}),
    ).session;
    expect(s.memberStats['affection']?['林黛玉'], 15);
    expect(s.memberStats['affection']?['贾宝玉'], 22);
  });

  test('按成员的值同样受上下限约束', () {
    final next = GameplayRuntime.apply(
      mode: dating,
      session: fresh(),
      turn: const GameplayTurn(displayText: '', deltas: {'好感|林黛玉': 999}),
    ).session;
    expect(next.memberStats['affection']?['林黛玉'], dating.stats
        .firstWhere((d) => d.key == 'affection')
        .max);
  });

  test('perMember 状态写了成员以外的名字，也记到那个人名下', () {
    final next = GameplayRuntime.apply(
      mode: dating,
      session: fresh(),
      turn: const GameplayTurn(displayText: '', deltas: {'好感|王熙凤': -5}),
    ).session;
    expect(next.memberStats['affection']?['王熙凤'], 5);
  });

  test('没写成员的「好感」退回集体值（不丢数据）', () {
    final next = GameplayRuntime.apply(
      mode: dating,
      session: fresh(),
      turn: const GameplayTurn(displayText: '', deltas: {'好感': 7}),
    ).session;
    expect(next.stats['affection'], 17);
    expect(next.memberStats['affection'], isNull);
  });

  test('规则文本按人展示当前值，并说明键格式', () {
    final text = GameplayRuntime.buildDirective(
      mode: dating,
      session: fresh(),
      members: const ['林黛玉', '贾宝玉'],
    );
    expect(text, contains('按人分别记'));
    expect(text, contains('林黛玉 10'));
    expect(text, contains('贾宝玉 10'));
    expect(text, contains('好感|林黛玉'));
  });

  test('单人（不传成员）时不出现按人字样', () {
    final text = GameplayRuntime.buildDirective(
      mode: dating,
      session: fresh(),
    );
    expect(text, isNot(contains('按人分别记')));
  });

  test('memberStats 能持久化往返', () {
    final s = fresh().copyWith(
      memberStats: {
        'affection': {'林黛玉': 15},
      },
    );
    final back = GameplaySession.fromMap({'id': 1, ...s.toMap()});
    expect(back.memberStats['affection']?['林黛玉'], 15);
  });
}
