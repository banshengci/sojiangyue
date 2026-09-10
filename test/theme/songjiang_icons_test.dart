import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/theme/songjiang_icons.dart';

void main() {
  group('SongJiangIcons', () {
    test('关键图标均为 Material IconData', () {
      expect(SongJiangIcons.bookshelf, isA<IconData>());
      expect(SongJiangIcons.statistics, isA<IconData>());
      expect(SongJiangIcons.notes, isA<IconData>());
      expect(SongJiangIcons.settings, isA<IconData>());
      expect(SongJiangIcons.import, isA<IconData>());
      expect(SongJiangIcons.aiPreview, isA<IconData>());
      expect(SongJiangIcons.aiQuiz, isA<IconData>());
      expect(SongJiangIcons.vocabulary, isA<IconData>());
    });

    test('选中态图标与未选中成对存在', () {
      expect(SongJiangIcons.bookshelfSelected, isA<IconData>());
      expect(SongJiangIcons.statisticsSelected, isA<IconData>());
      expect(SongJiangIcons.notesSelected, isA<IconData>());
      expect(SongJiangIcons.settingsSelected, isA<IconData>());
    });
  });
}
