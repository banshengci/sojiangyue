import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/service/convert_to_epub/create_epub.dart';

void main() {
  group('buildEpubParagraphs', () {
    test('几乎无空行时每行独立成段', () {
      const content = '第一段。\n第二段。\n第三段。';
      final result = buildEpubParagraphs(content);
      expect(result.length, 3);
      expect(result[0], contains('第一段。'));
      expect(result[1], contains('第二段。'));
    });

    test('有空行时整块软换行合并为一段', () {
      const content = '开头元数据\n\n这是段落一。\n软换行续写。\n\n下一段。';
      final result = buildEpubParagraphs(content);
      expect(result.length, 3);
      expect(result[1], contains('这是段落一。 软换行续写。'));
      expect(result[2], contains('下一段。'));
    });

    test('块内全角空格缩进视为新段', () {
      const content = '块一。\n\n　　缩进新段。\n普通续行。';
      final result = buildEpubParagraphs(content);
      // 块一 + 缩进段 + 续行并入缩进段
      expect(result.length, 2);
      expect(result[0], contains('块一。'));
      expect(result[1], contains('缩进新段。 普通续行。'));
    });

    test('空行与空白行不产生空段', () {
      const content = '甲。\n\n\n乙。\n   \n\n丙。';
      final result = buildEpubParagraphs(content);
      expect(result.length, 3);
    });
  });
}
