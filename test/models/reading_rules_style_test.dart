import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/reading_rules.dart';
import 'package:songjiang_reader/enums/convert_chinese_mode.dart';
import 'package:songjiang_reader/models/book_style.dart';

void main() {
  group('ReadingRules', () {
    test('默认无转换、非仿生阅读', () {
      final rules = ReadingRules(
        convertChineseMode: ConvertChineseMode.none,
        bionicReading: false,
      );
      expect(rules.convertChineseMode, ConvertChineseMode.none);
      expect(rules.bionicReading, isFalse);
    });

    test('copyWith 只改指定字段', () {
      final base = ReadingRules(
        convertChineseMode: ConvertChineseMode.none,
        bionicReading: false,
      );
      final updated = base.copyWith(bionicReading: true);
      expect(updated.bionicReading, isTrue);
      expect(updated.convertChineseMode, ConvertChineseMode.none);
    });
  });

  group('BookStyle', () {
    test('默认实例可序列化', () {
      final style = BookStyle();
      final json = style.toJson();
      expect(json, isNotEmpty);
      final restored = BookStyle.fromJson(json);
      expect(restored.maxColumnCount, style.maxColumnCount);
    });

    test('copyWith 修改栏数后可序列化', () {
      final style = BookStyle().copyWith(maxColumnCount: 2);
      expect(style.maxColumnCount, 2);
      final restored = BookStyle.fromJson(style.toJson());
      expect(restored.maxColumnCount, 2);
    });
  });
}
