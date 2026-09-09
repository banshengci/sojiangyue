import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/enums/text_alignment.dart';
import 'package:songjiang_reader/enums/translation_mode.dart';
import 'package:songjiang_reader/enums/writing_mode.dart';

void main() {
  group('TranslationModeEnum', () {
    test('fromCode 解析已知 code', () {
      expect(TranslationModeEnum.fromCode('off'), TranslationModeEnum.off);
      expect(
        TranslationModeEnum.fromCode('translation-only'),
        TranslationModeEnum.translationOnly,
      );
      expect(
        TranslationModeEnum.fromCode('original-only'),
        TranslationModeEnum.originalOnly,
      );
      expect(TranslationModeEnum.fromCode('bilingual'), TranslationModeEnum.bilingual);
    });

    test('未知 code 回退 off', () {
      expect(TranslationModeEnum.fromCode('nope'), TranslationModeEnum.off);
      expect(TranslationModeEnum.fromCode(''), TranslationModeEnum.off);
    });

    test('code 与 enum 名稳定', () {
      for (final mode in TranslationModeEnum.values) {
        expect(TranslationModeEnum.fromCode(mode.code), mode);
      }
    });
  });

  group('WritingModeEnum', () {
    test('fromCode 解析已知 code', () {
      expect(WritingModeEnum.fromCode('auto'), WritingModeEnum.auto);
      expect(WritingModeEnum.fromCode('vertical-rl'), WritingModeEnum.verticalRl);
      expect(WritingModeEnum.fromCode('horizontal-tb'), WritingModeEnum.horizontalTb);
    });

    test('未知 code 回退 auto', () {
      expect(WritingModeEnum.fromCode('unknown'), WritingModeEnum.auto);
    });

    test('isVertical / isHorizontal', () {
      expect(WritingModeEnum.verticalRl.isVertical, isTrue);
      expect(WritingModeEnum.verticalLr.isVertical, isTrue);
      expect(WritingModeEnum.horizontalTb.isVertical, isFalse);
      expect(WritingModeEnum.horizontalTb.isHorizontal, isTrue);
      expect(WritingModeEnum.auto.isVertical, isFalse);
      expect(WritingModeEnum.auto.isHorizontal, isFalse);
    });
  });

  group('TextAlignmentEnum', () {
    test('fromCode 解析已知 code', () {
      expect(TextAlignmentEnum.fromCode('auto'), TextAlignmentEnum.auto);
      expect(TextAlignmentEnum.fromCode('left'), TextAlignmentEnum.left);
      expect(TextAlignmentEnum.fromCode('justify'), TextAlignmentEnum.justify);
    });

    test('每个 value 的 code 均可回查', () {
      for (final a in TextAlignmentEnum.values) {
        expect(TextAlignmentEnum.fromCode(a.code), a);
      }
    });
  });
}
