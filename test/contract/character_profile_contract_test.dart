import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_profile.dart';
import 'package:songjiang_reader/models/character_profile_event.dart';

/// 角色养成档案 / 贡献账本 契约测试（T01）。
///
/// 覆盖：`fromMap → toMap` 往返幂等、缺字段容错、档位推导。
void main() {
  group('CharacterProfile', () {
    test('fromMap → toMap 往返一致', () {
      final now = DateTime(2026, 10, 7, 12, 0, 0);
      final milestonesJson = jsonEncode({
        'items': [
          {
            'key': 'first_meet',
            'name': '初识',
            'affection': 0,
            'at': now.toIso8601String(),
          },
        ],
      });
      final map = {
        'id': 3,
        'character_name': '林黛玉',
        'book_id': 7,
        'book_title': '红楼梦',
        'bond_level': 2,
        'affection_total': 15,
        'session_count': 2,
        'turn_count': 24,
        'last_played_at': now.toIso8601String(),
        'milestones': milestonesJson,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final profile = CharacterProfile.fromMap(map);
      expect(profile.characterName, '林黛玉');
      expect(profile.bookId, 7);
      expect(profile.bondLevel, 2);
      expect(profile.affectionTotal, 15);
      expect(profile.sessionCount, 2);
      expect(profile.turnCount, 24);
      expect(profile.lastPlayedAt, now);
      expect(profile.milestones.length, 1);
      expect(profile.milestones.first.key, 'first_meet');

      final out = profile.toMap();
      expect(out['character_name'], '林黛玉');
      expect(out['book_id'], 7);
      expect(out['book_title'], '红楼梦');
      expect(out['bond_level'], 2);
      expect(out['affection_total'], 15);
      expect(out['session_count'], 2);
      expect(out['turn_count'], 24);
      expect(out['last_played_at'], now.toIso8601String());
      expect(out['created_at'], now.toIso8601String());
      expect(out['updated_at'], now.toIso8601String());
      // milestones 是 JSON 字符串：按结构比较（不比较键序 / 空白）
      expect(jsonDecode(out['milestones'] as String), jsonDecode(milestonesJson));

      // 幂等：再往返一次，JSON 列逐字节一致
      final again = CharacterProfile.fromMap(out);
      expect(again.toMap()['milestones'], out['milestones']);
    });

    test('缺字段 / 非法 milestones JSON 回退默认值，不抛异常', () {
      final profile = CharacterProfile.fromMap({
        'character_name': '薛宝钗',
        'milestones': '这不是 JSON {{{',
        'created_at': '2026-10-07T12:00:00.000',
        'updated_at': '2026-10-07T12:00:00.000',
      });
      expect(profile.id, isNull);
      expect(profile.bookId, isNull, reason: 'affection_total 等整列缺失应兜底');
      expect(profile.affectionTotal, 0);
      expect(profile.sessionCount, 0);
      expect(profile.turnCount, 0);
      expect(profile.bondLevel, 1);
      expect(profile.lastPlayedAt, isNull);
      expect(profile.milestones, isEmpty, reason: '非法 JSON 应兜底为空列表');
    });

    test('progressToNextLevel 与档位表同构', () {
      final at = DateTime(2026, 10, 7);
      CharacterProfile withAffection(int affection) => CharacterProfile(
            characterName: 'x',
            affectionTotal: affection,
            bondLevel: CharacterProfile.bondLevelOf(affection),
            createdAt: at,
            updatedAt: at,
          );

      expect(withAffection(0).progressToNextLevel(), 0.0);
      expect(withAffection(5).progressToNextLevel(), closeTo(0.5, 1e-9));
      expect(withAffection(10).progressToNextLevel(), 0.0);
      expect(withAffection(20).progressToNextLevel(), closeTo(0.5, 1e-9));
      expect(withAffection(240).progressToNextLevel(), 1.0);
      expect(withAffection(9999).progressToNextLevel(), 1.0);

      expect(CharacterProfile.bondLevelOf(0), 1);
      expect(CharacterProfile.bondLevelOf(9), 1);
      expect(CharacterProfile.bondLevelOf(10), 2);
      expect(CharacterProfile.bondLevelOf(30), 3);
      expect(CharacterProfile.bondLevelOf(300), kBondMilestones.length);
    });
  });

  group('BondMilestone', () {
    test('milestonesOf 按好感推导已解锁列表', () {
      expect(BondMilestone.milestonesOf(0, null).length, 1);
      expect(BondMilestone.milestonesOf(9, null).length, 1);
      expect(BondMilestone.milestonesOf(10, null).length, 2);
      expect(
        BondMilestone.milestonesOf(240, null).length,
        kBondMilestones.length,
      );

      final list = BondMilestone.milestonesOf(65, DateTime(2026, 10, 7));
      expect(
        list.map((m) => m.name).toList(),
        ['初识', '破冰', '交心', '知己'],
      );
      expect(list.last.key, 'confidant');
    });

    test('fromJson → toJson 往返一致', () {
      final at = DateTime(2026, 10, 7, 12, 0, 0);
      final m = BondMilestone.fromJson({
        'key': 'soulmate',
        'name': '灵魂之交',
        'affection': 240,
        'at': at.toIso8601String(),
      });
      expect(m.key, 'soulmate');
      expect(m.affection, 240);
      expect(m.at, at);
      expect(m.toJson()['key'], 'soulmate');
    });
  });

  group('CharacterProfileEvent', () {
    test('fromMap → toMap 往返一致', () {
      final now = DateTime(2026, 10, 7, 12, 0, 0);
      final map = {
        'id': 9,
        'gameplay_session_id': 42,
        'character_name': '林黛玉',
        'book_id': 7,
        'book_title': '红楼梦',
        'mode_id': 'mystery',
        'affection_delta': 5,
        'turn_count': 12,
        'settled_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      };

      final event = CharacterProfileEvent.fromMap(map);
      expect(event.gameplaySessionId, 42);
      expect(event.characterName, '林黛玉');
      expect(event.affectionDelta, 5);
      expect(event.turnCount, 12);
      expect(event.settledAt, now);

      final out = event.toMap();
      expect(out['gameplay_session_id'], 42);
      expect(out['character_name'], '林黛玉');
      expect(out['book_id'], 7);
      expect(out['book_title'], '红楼梦');
      expect(out['mode_id'], 'mystery');
      expect(out['affection_delta'], 5);
      expect(out['turn_count'], 12);
      expect(out['settled_at'], now.toIso8601String());
      expect(out['created_at'], now.toIso8601String());
    });

    test('缺失可选字段回退默认值', () {
      final event = CharacterProfileEvent.fromMap({
        'gameplay_session_id': 1,
        'character_name': '薛宝钗',
        'settled_at': '2026-10-07T12:00:00.000',
        'created_at': '2026-10-07T12:00:00.000',
      });
      expect(event.id, isNull);
      expect(event.bookId, isNull);
      expect(event.bookTitle, isNull);
      expect(event.modeId, isNull);
      expect(event.affectionDelta, 0);
      expect(event.turnCount, 0);
    });
  });
}
