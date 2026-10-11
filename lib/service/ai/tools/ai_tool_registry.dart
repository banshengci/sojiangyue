import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/service/ai/tools/ai_tool_context.dart';
import 'package:songjiang_reader/service/ai/tools/apply_book_tags_tool.dart';
import 'package:songjiang_reader/service/ai/tools/book_content_search_tool.dart';
import 'package:songjiang_reader/service/ai/tools/books_tags_list_tool.dart';
import 'package:songjiang_reader/service/ai/tools/bookshelf_lookup_tool.dart';
import 'package:songjiang_reader/service/ai/tools/bookshelf_organize_tool.dart';
import 'package:songjiang_reader/service/ai/tools/calculator_tool.dart';
import 'package:songjiang_reader/service/ai/tools/chapter_content_by_href_tool.dart';
import 'package:songjiang_reader/service/ai/tools/current_book_toc_tool.dart';
import 'package:songjiang_reader/service/ai/tools/current_chapter_content_tool.dart';
import 'package:songjiang_reader/service/ai/tools/current_reading_metadata_tool.dart';
import 'package:songjiang_reader/service/ai/tools/current_time_tool.dart';
import 'package:songjiang_reader/service/ai/tools/mindmap_tool.dart';
import 'package:songjiang_reader/service/ai/tools/notes_search_tool.dart';
import 'package:songjiang_reader/service/ai/tools/reading_history_tool.dart';
import 'package:songjiang_reader/service/ai/tools/tags_list_tool.dart';
import 'package:langchain_core/tools.dart';
import 'package:songjiang_reader/service/ai/tools/base_tool.dart';
export 'package:songjiang_reader/service/ai/tools/base_tool.dart';
// 兼容：原先从本文件取 `AiToolContext` 的使用方无需改动。
export 'package:songjiang_reader/service/ai/tools/ai_tool_context.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';

// AiToolDefinition 已下沉至 base_tool.dart（叶子层）。
// AiToolContext 已下沉至 ai_tool_context.dart —— 15 个工具都需要它做类型转换，
// 若它留在本文件，就会形成 15 组「工具 <-> registry」互相依赖。

class AiToolRegistry {
  static final List<AiToolDefinition> _definitions = [
    calculatorToolDefinition,
    currentTimeToolDefinition,
    mindmapToolDefinition,
    bookContentSearchToolDefinition,
    bookshelfLookupToolDefinition,
    bookshelfOrganizeToolDefinition,
    notesSearchToolDefinition,
    readingHistoryToolDefinition,
    currentReadingMetadataToolDefinition,
    currentBookTocToolDefinition,
    currentChapterContentToolDefinition,
    chapterContentByHrefToolDefinition,
    tagsListToolDefinition,
    booksTagsListToolDefinition,
    applyBookTagsToolDefinition,
    ...PluginRegistry.instance.builtinToolDefinitions,
  ];

  // 动态聚合：核心工具 + 已启用的动态插件工具（第三方插件运行时加载）。
  static List<AiToolDefinition> get _allDefinitions =>
      [..._definitions, ...PluginRegistry.instance.enabledDynamicToolDefinitions];

  static Map<String, AiToolDefinition> get _definitionMap =>
      {for (final def in _allDefinitions) def.id: def};

  static List<AiToolDefinition> get definitions =>
      List<AiToolDefinition>.unmodifiable(_allDefinitions);

  static AiToolDefinition? byId(String id) => _definitionMap[id];

  static List<String> defaultEnabledToolIds() =>
      _allDefinitions.map((def) => def.id).toList(growable: false);

  static List<String> sanitizeIds(List<String> ids) {
    final seen = <String>{};
    final filtered = <String>[];
    for (final id in ids) {
      if (_definitionMap.containsKey(id) && seen.add(id)) {
        filtered.add(id);
      }
    }
    return filtered;
  }

  static List<Tool> buildTools(
    AiToolContext context,
    List<String> enabledIds,
  ) {
    final enabled = enabledIds.toSet();
    return _allDefinitions
        .where((def) => enabled.contains(def.id))
        .map((def) => def.build(context))
        .toList(growable: false);
  }

  static String displayNameForId(String id, {L10n? l10n}) =>
      _definitionMap[id]?.displayNameOrDefault(l10n) ?? id;

  static String descriptionForId(String id, {L10n? l10n}) =>
      _definitionMap[id]?.descriptionOrDefault(l10n) ?? '';
}
