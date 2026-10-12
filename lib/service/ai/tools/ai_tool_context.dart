import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songjiang_reader/providers/current_reading.dart';
import 'package:songjiang_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/books_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/groups_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/reading_history_repository.dart';
import 'package:songjiang_reader/service/ai/tools/repository/tag_repository.dart';

/// Context object shared by AI tools so builders don't need long constructors.
///
/// 单独成文件的目的：打破 `ai_tool_registry.dart` ↔ `*_tool.dart` 的 import 环。
/// 注册表要 import 每个工具，工具若反过来 import 注册表取本类，就形成循环；
/// 循环会让分析器把 `context as AiToolContext` 误判为「多余的 cast」
/// （同时给 base_tool 的导入报 unnecessary_import）。
/// 把本类下沉为叶子节点后，两侧都只依赖它，环消失。
///
/// 注意：`AiToolDefinition.build` 的形参类型是 `Object`（见 base_tool.dart），
/// 所以工具内部仍需要显式 `context as AiToolContext` 才能取到仓库。
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
