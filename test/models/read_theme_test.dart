import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/read_theme.dart';

void main() {
  group('ReadTheme 序列化', () {
    test('toJson / fromJson 往返保留主题名', () {
      final theme = ReadTheme(
        id: 3,
        name: '竹月',
        backgroundColor: 'ffe9efe6',
        textColor: 'ff26412f',
        backgroundImagePath: '',
      );

      final restored = ReadTheme.fromJson(theme.toJson());

      expect(restored.id, 3);
      expect(restored.name, '竹月');
      expect(restored.backgroundColor, 'ffe9efe6');
      expect(restored.textColor, 'ff26412f');
    });

    test('旧数据没有 name 时回退为空串（界面显示「自定义」）', () {
      final theme = ReadTheme.fromJson('''
      {
        "id": 1,
        "backgroundColor": "FFFBF7EE",
        "textColor": "FF2E2A24",
        "backgroundImagePath": ""
      }
      ''');

      expect(theme.name, isEmpty);
    });

    test('fromDb 读取 name，缺省回退空串', () {
      final withName = ReadTheme.fromDb(<String, dynamic>{
        'id': 2,
        'name': '松烟',
        'background_color': 'ff121815',
        'text_color': 'ffe6ede4',
        'background_image_path': '',
      });
      expect(withName.name, '松烟');

      final noName = ReadTheme.fromDb(<String, dynamic>{
        'id': 2,
        'background_color': 'ff121815',
        'text_color': 'ffe6ede4',
        'background_image_path': '',
      });
      expect(noName.name, isEmpty);
    });

    test('copyWith 可以只改名字', () {
      final theme = ReadTheme(
        id: 5,
        name: '',
        backgroundColor: 'fffaf0dc',
        textColor: 'ff3b2f22',
        backgroundImagePath: '',
      );

      final renamed = theme.copyWith(name: '秋杏');

      expect(renamed.name, '秋杏');
      expect(renamed.backgroundColor, theme.backgroundColor);
      expect(renamed.textColor, theme.textColor);
    });
  });

  group('预置阅读主题', () {
    // 直接从源码解析预置主题的 INSERT 语句，确保 6 个品牌主题都还在、
    // 且配色是合法的 8 位 ARGB hex（改色时最容易写漏一位）。
    final source = File('lib/dao/database.dart').readAsStringSync();
    final themeInserts = RegExp(
      r"INSERT INTO tb_themes \(name, background_color, text_color, background_image_path\)"
      r" VALUES \('([^']*)', '([0-9a-fA-F]{8})', '([0-9a-fA-F]{8})', ''\)",
    ).allMatches(source).toList();

    test('共 6 个预置主题，且都有中文名', () {
      expect(themeInserts.length, 6,
          reason: '松江阅预置了宣纸 / 松烟 / 竹月 / 藕荷 / 秋杏 / 苍黛 六个主题');

      final names = themeInserts.map((m) => m.group(1)!).toList();
      expect(names, ['宣纸', '松烟', '竹月', '藕荷', '秋杏', '苍黛']);
    });

    test('每个预置主题的前景色都不是纯黑或纯白（护眼）', () {
      for (final match in themeInserts) {
        final name = match.group(1)!;
        final textColor = match.group(3)!.toLowerCase();
        expect(textColor, isNot('ff000000'), reason: '$name 的文字色不能是纯黑');
        expect(textColor, isNot('ffffffff'), reason: '$name 的文字色不能是纯白');
      }
    });

    test('深色主题的文字亮度应高于背景（避免看不清）', () {
      for (final match in themeInserts) {
        final name = match.group(1)!;
        final bg = Color(int.parse('0x${match.group(2)!}'));
        final fg = Color(int.parse('0x${match.group(3)!}'));

        expect(fg.computeLuminance() != bg.computeLuminance(), isTrue,
            reason: '$name 的前景与背景亮度不能相同');
        expect(
            (fg.computeLuminance() - bg.computeLuminance()).abs() > 0.3,
            isTrue,
            reason: '$name 的前景与背景对比度过低');
      }
    });
  });
}
