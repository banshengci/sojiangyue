import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/service/ai/tools/ai_tool_registry.dart';

void main() {
  group('AiToolRegistry', () {
    test('定义表非空且 id 唯一', () {
      final defs = AiToolRegistry.definitions;
      expect(defs, isNotEmpty);
      final ids = defs.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('defaultEnabledToolIds 覆盖全部定义', () {
      final defaults = AiToolRegistry.defaultEnabledToolIds();
      expect(defaults.length, AiToolRegistry.definitions.length);
      for (final def in AiToolRegistry.definitions) {
        expect(defaults, contains(def.id));
      }
    });

    test('sanitizeIds 过滤未知 id 并去重', () {
      final known = AiToolRegistry.defaultEnabledToolIds().first;
      final result = AiToolRegistry.sanitizeIds([
        known,
        known,
        'not_a_real_tool',
        'another_fake',
      ]);
      expect(result, [known]);
    });

    test('sanitizeIds 保持已知 id 的相对顺序', () {
      final all = AiToolRegistry.defaultEnabledToolIds();
      final shuffledPick = [all[0], all[2], all[0], all[1]];
      final result = AiToolRegistry.sanitizeIds(shuffledPick);
      expect(result, [all[0], all[2], all[1]]);
    });

    test('byId 能取到已知工具，未知返回 null', () {
      final known = AiToolRegistry.defaultEnabledToolIds().first;
      expect(AiToolRegistry.byId(known), isNotNull);
      expect(AiToolRegistry.byId('missing'), isNull);
    });
  });
}
