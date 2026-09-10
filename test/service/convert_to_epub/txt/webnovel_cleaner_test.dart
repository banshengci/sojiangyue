import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/service/convert_to_epub/txt/webnovel_cleaner.dart';

void main() {
  group('cleanWebNovelText', () {
    test('去除广告与导航噪声行', () {
      const raw = '''
最新网址：www.example.com
请收藏本站，更新最快
第1章 开局
身份登记处，未满十八岁叉出去！
……平行世界，天原市。
上一章
下一章
请访问 www.foo.cn/book
二维码 扫码下载APP
正文内容继续。
''';
      final out = cleanWebNovelText(raw);
      expect(out.contains('第1章 开局'), isTrue);
      expect(out.contains('身份登记处'), isTrue);
      expect(out.contains('www.example.com'), isFalse);
      expect(out.contains('请收藏本站'), isFalse);
      expect(out.contains('上一章'), isFalse);
      expect(out.contains('扫码下载APP'), isFalse);
    });

    test('折叠连续空行', () {
      const raw = '甲。\n\n\n\n乙。\n\n\n丙。';
      final out = cleanWebNovelText(raw);
      expect(out.contains('\n\n\n'), isFalse);
      expect(out, '甲。\n\n乙。\n\n丙。');
    });

    test('保留章节标题与正文', () {
      const raw = '''
简介：本书免费阅读
第十二章 风云再起
正文一段。

第十三章 暗流
另一段。
''';
      final out = cleanWebNovelText(raw);
      expect(out.contains('第十二章 风云再起'), isTrue);
      expect(out.contains('第十三章 暗流'), isTrue);
      expect(out.contains('正文一段。'), isTrue);
      expect(out.contains('简介：本书免费阅读'), isFalse);
    });

    test('去除零宽字符与 BOM', () {
      final raw = '﻿甲\u200b乙\n第1章';
      final out = cleanWebNovelText(raw);
      expect(out.contains('﻿'), isFalse);
      expect(out.contains('​'), isFalse);
      expect(out.contains('第1章'), isTrue);
    });

    test('countRemovedLines 统计非空行差', () {
      const before = '垃圾行\n正文\n广告';
      const after = '正文';
      expect(countRemovedLines(before, after), 2);
    });
  });
}
