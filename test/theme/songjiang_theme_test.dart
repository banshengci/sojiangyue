import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';

void main() {
  group('SongJiangColors 品牌色板', () {
    test('色板非空且不重复', () {
      final palette = SongJiangColors.themePalette;

      expect(palette.length, greaterThanOrEqualTo(6));
      expect(palette.toSet().length, palette.length,
          reason: '色板里不应有重复颜色');
    });

    test('默认主色是松绿，且色板第一项就是它', () {
      // 对齐设计令牌《松江阅 · 色彩》松绿 #2E6B4F
      expect(SongJiangColors.pine, const Color(0xFF2E6B4F));
      expect(SongJiangColors.themePalette.first, SongJiangColors.pine);
    });

    test('每个色板颜色都能撑起封面文字的对比度', () {
      // 默认封面直接用色板颜色做底色，文字取黑或白。
      // 这里确保无论取哪个方向，对比度都够看书名。
      for (final color in SongJiangColors.themePalette) {
        final luminance = color.computeLuminance();
        final contrastWithWhite = (1.05) / (luminance + 0.05);
        final contrastWithBlack = (luminance + 0.05) / 0.05;
        final best =
            contrastWithWhite > contrastWithBlack ? contrastWithWhite : contrastWithBlack;

        expect(best, greaterThan(3.0),
            reason: '色板颜色 $color 与黑白两色的最佳对比度仅 ${best.toStringAsFixed(2)}');
      }
    });

    test('浅色底与深色底都不是纯灰度（保留品牌色偏）', () {
      // 宣纸偏暖、松烟偏绿，刻意区别于中性灰
      expect(SongJiangColors.paper, isNot(const Color(0xFFF2F2F7)));
      expect(SongJiangColors.ink, isNot(const Color(0xFF1C1C1E)));

      expect(
        SongJiangColors.paper.computeLuminance(),
        greaterThan(0.8),
        reason: '宣纸应作为浅色模式的亮底色',
      );
      expect(
        SongJiangColors.ink.computeLuminance(),
        lessThan(0.1),
        reason: '松烟应作为深色模式的暗底色',
      );
    });
  });

  group('SongJiangBrand 品牌标识', () {
    test('名称与标语已定义', () {
      expect(SongJiangBrand.name, '松江阅');
      expect(SongJiangBrand.nameEn, 'SongJiang Reader');
      expect(SongJiangBrand.tagline, isNotEmpty);
      expect(SongJiangBrand.logoAsset, 'assets/icon/songjiang-logo.png');
    });
  });
}
