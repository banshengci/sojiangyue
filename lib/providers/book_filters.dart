import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book_filters.g.dart';

enum ReadingStatusFilter { none, finished, reading, notStarted }

@riverpod
class ReadingStatusFilterNotifier extends _$ReadingStatusFilterNotifier {
  @override
  ReadingStatusFilter build() => ReadingStatusFilter.none;

  void toggle(ReadingStatusFilter status) {
    if (state == status) {
      state = ReadingStatusFilter.none;
    } else {
      state = status;
    }
  }

  /// 直接选中（不再二次切换）。
  ///
  /// 分段控件（SjSegmented）需要「点已选项不取消」的语义，
  /// 而 [toggle] 会把它取消掉。[select] 与它并存，互不影响。
  void select(ReadingStatusFilter status) {
    state = status;
  }

  void clear() {
    state = ReadingStatusFilter.none;
  }
}
