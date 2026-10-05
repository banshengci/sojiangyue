import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_card.dart';

/// 角色卡 / 关系 schema 契约测试（3.2）：对齐造梦 44 字段子集的映射与容错。
void main() {
  group('CharacterCard', () {
    test('fromMap → toMap 往返一致', () {
      final now = DateTime(2026, 10, 5, 12, 0, 0);
      final map = {
        'book_id': 7,
        'name': '林黛玉',
        'aliases': '["颦儿","潇湘妃子"]',
        'gender': '女',
        'role': '女主角',
        'importance': 95,
        'personality': '敏感多思',
        'background': '贾母外孙女',
        'motivation': '追求真情',
        'appearance': '弱柳扶风',
        'first_appearance_chapter': '第三回',
        'description': '金陵十二钗之首',
        'source': 'ai_distill',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final card = CharacterCard.fromMap(map);
      expect(card.name, '林黛玉');
      expect(card.importance, 95);
      expect(card.aliases, ['颦儿', '潇湘妃子']);
      final out = card.toMap();
      expect(out['book_id'], 7);
      expect(out['name'], '林黛玉');
      expect(out['importance'], 95);
    });

    test('缺失可选字段回退默认值，不抛异常', () {
      final card = CharacterCard.fromMap({
        'book_id': 7,
        'name': '薛宝钗',
        'created_at': '2026-10-05T12:00:00.000',
        'updated_at': '2026-10-05T12:00:00.000',
      });
      expect(card.importance, 50); // 默认中等
      expect(card.aliases, isNull);
      expect(card.source, 'ai_distill');
    });
  });

  group('CharacterRelation', () {
    test('五元组往返一致（造梦关系维度）', () {
      final map = {
        'book_id': 7,
        'source_name': '贾宝玉',
        'target_name': '林黛玉',
        'relation_type': '恋人',
        'trust': 80,
        'affection': 90,
        'power_gap': -10,
        'conflict_point': '家族压力',
        'hidden_attitude': '彼此试探',
        'created_at': '2026-10-05T12:00:00.000',
        'updated_at': '2026-10-05T12:00:00.000',
      };
      final r = CharacterRelation.fromMap(map);
      expect(r.trust, 80);
      expect(r.affection, 90);
      expect(r.powerGap, -10);
      final out = r.toMap();
      expect(out['source_name'], '贾宝玉');
      expect(out['power_gap'], -10);
    });
  });
}
