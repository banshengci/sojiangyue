import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/widgets/book_notes/book_note_tile.dart';
import 'package:songjiang_reader/widgets/bookshelf/continue_reading_card.dart';

/// v3 两处新逻辑的单元测试。
///
/// 这两处都是纯函数，不依赖 L10n / 数据库 / 渲染，因此可以直接断言：
///  - `ContinueReadingCard.pick` —— 书架顶部「继续阅读」挑哪一本
///  - `noteTypeLabel` —— 笔记类型的中文标签（双编码里的「文字」那一半）
void main() {
  group('ContinueReadingCard.pick', () {
    Book book({
      required int id,
      required double progress,
      required DateTime updated,
      bool deleted = false,
    }) {
      return Book.mock().copyWith(
        id: id,
        readingPercentage: progress,
        updateTime: updated,
        isDeleted: deleted,
      );
    }

    test('空书架返回 null', () {
      expect(ContinueReadingCard.pick(const []), isNull);
      expect(ContinueReadingCard.pick(const [[]]), isNull);
    });

    test('只挑「读到一半」的书（0 < 进度 < 1）', () {
      final books = <List<Book>>[
        [book(id: 1, progress: 0, updated: DateTime(2026, 1, 3))],
        [book(id: 2, progress: 1, updated: DateTime(2026, 1, 4))],
      ];
      expect(ContinueReadingCard.pick(books), isNull);
    });

    test('多本读到一半时取 updateTime 最新的', () {
      final books = <List<Book>>[
        [book(id: 1, progress: 0.2, updated: DateTime(2026, 1, 1))],
        [book(id: 2, progress: 0.6, updated: DateTime(2026, 3, 1))],
        [book(id: 3, progress: 0.4, updated: DateTime(2026, 2, 1))],
      ];
      expect(ContinueReadingCard.pick(books)?.id, 2);
    });

    test('跳过已删除的书', () {
      final books = <List<Book>>[
        [book(id: 1, progress: 0.6, updated: DateTime(2026, 3, 1), deleted: true)],
        [book(id: 2, progress: 0.3, updated: DateTime(2026, 1, 1))],
      ];
      expect(ContinueReadingCard.pick(books)?.id, 2);
    });

    test('文件夹里的书也参与挑选', () {
      final books = <List<Book>>[
        [
          book(id: 1, progress: 0.3, updated: DateTime(2026, 1, 1)),
          book(id: 2, progress: 0.8, updated: DateTime(2026, 5, 1)),
        ],
      ];
      expect(ContinueReadingCard.pick(books)?.id, 2);
    });
  });

  group('noteTypeLabel', () {
    test('已知类型有中文标签', () {
      expect(noteTypeLabel('highlight'), '划线');
      expect(noteTypeLabel('underline'), '下划线');
    });

    test('未知类型回退到「笔记」，不返回空串', () {
      expect(noteTypeLabel('unknown'), '笔记');
      expect(noteTypeLabel(''), '笔记');
    });

    test('标签不为空（双编码的文字那一半必须存在）', () {
      for (final t in ['highlight', 'underline', 'x']) {
        expect(noteTypeLabel(t), isNotEmpty);
      }
    });
  });
}
