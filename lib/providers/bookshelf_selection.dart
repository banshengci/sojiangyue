import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bookshelf_selection.g.dart';

/// 书架多选集合。
@riverpod
class BookshelfSelection extends _$BookshelfSelection {
  @override
  Set<int> build() => const {};

  bool get isEmpty => state.isEmpty;
  bool get isNotEmpty => state.isNotEmpty;
  bool isSelected(int bookId) => state.contains(bookId);

  void toggle(int bookId) {
    final next = Set<int>.from(state);
    if (!next.remove(bookId)) {
      next.add(bookId);
    }
    state = next;
  }

  void selectAll(Iterable<int> ids) {
    state = ids.toSet();
  }

  void clear() {
    state = const {};
  }

  void remove(int bookId) {
    final next = Set<int>.from(state)..remove(bookId);
    state = next;
  }
}
