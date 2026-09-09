import 'package:songjiang_reader/models/chapter_split_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('default chapter split pattern', () {
    final pattern = getDefaultChapterSplitRule().buildRegExp();

    test('matches headings with trailing ASCII whitespace', () {
      expect(pattern.hasMatch('第一章 '), isTrue);
      expect(pattern.hasMatch('第二章  '), isTrue);
    });

    test('matches headings with trailing ideographic whitespace', () {
      expect(pattern.hasMatch('第三章　'), isTrue);
    });

    test('matches Chinese webnovel titles without space after 章', () {
      expect(pattern.hasMatch('第1章开局就离婚（加料 田曦薇）'), isTrue);
      expect(pattern.hasMatch('第十二章风起云涌'), isTrue);
    });
  });
}
