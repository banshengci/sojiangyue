import 'package:songjiang_reader/models/chapter_split_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内置章节分割规则', () {
    test('默认规则可获取且 id 一致', () {
      final rule = getDefaultChapterSplitRule();
      expect(rule.id, kDefaultChapterSplitRuleId);
      expect(rule.isBuiltin, isTrue);
    });

    test('按 id 查找：命中返回规则，未命中返回 null', () {
      expect(findBuiltinChapterSplitRuleById('cn_only_numeric'), isNotNull);
      expect(findBuiltinChapterSplitRuleById('not_exist_rule'), isNull);
    });

    test('规则 id 唯一', () {
      final ids = builtinChapterSplitRules.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    // 这是最重要的一条：samples 字段是给用户看的“示例”，
    // 若某天改了 pattern 却忘了同步 samples（或反之），这条测试会立刻报出来。
    test('每条规则声明的 samples 都应能被自身的正则匹配', () {
      final mismatches = <String>[];
      for (final rule in builtinChapterSplitRules) {
        final pattern = rule.buildRegExp();
        for (final sample in rule.samples) {
          if (!pattern.hasMatch(sample)) {
            mismatches.add('[${rule.id}] 未匹配: "$sample"');
          }
        }
      }
      expect(mismatches, isEmpty,
          reason: '以下示例与正则不一致，请修正 pattern 或 samples:\n'
              '${mismatches.join('\n')}');
    });
  });
}
