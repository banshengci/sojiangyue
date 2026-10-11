/// AI 工具的依赖注入上下文。
///
/// 从 `lib/service/ai/tools/ai_tool_registry.dart` 下沉到本文件。
/// 动机：15 个内置工具都需要 `(context as AiToolContext)` 做类型转换，而它们原先
/// 只能从 registry 拿到这个类型 —— registry 又 import 全部工具来构建定义表，
/// 于是形成 15 组「工具 <-> registry」互相依赖的 2-环。
/// 本文件不依赖任何 `*_tool.dart`，工具改为依赖它即可断开该环。
///
/// 与 `base_tool.dart` 的分工：base_tool 只放工具基类与定义类型（叶子层，零项目内依赖）；
/// 本文件承载"运行时依赖装配"，因此会依赖 repository/ 与 providers/。
/// 行为无变化：字段、初始化顺序、`isReading` 实现逐字保持。
/// 下面 7 条 import 是从原 `ai_tool_registry.dart` 一并搬来的 ——
/// 本文件引用的 `WidgetRef` / 6 个 Repository / `currentReadingProvider`
/// 必须在本文件可见（export 不会把名字引入自身作用域）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songjiang_reader/providers/current_reading.dart';
import 'package:songjiang_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/books_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/groups_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/reading_history_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/tag_repository.dart';

/// Context object shared by AI tools so builders don't need long constructors.
class AiToolContext {
  AiToolContext({required this.ref});

  final WidgetRef ref;

  late final NotesRepository notesRepository = NotesRepository();
  late final BooksRepository booksRepository = BooksRepository();
  late final BookContentSearchRepository bookContentSearchRepository =
      BookContentSearchRepository(booksRepository: booksRepository);
  late final GroupsRepository groupsRepository = GroupsRepository();
  late final ReadingHistoryRepository readingHistoryRepository =
      ReadingHistoryRepository();
  late final TagRepository tagRepository = TagRepository();

  bool get isReading => ref.read(currentReadingProvider).isReading;
}
