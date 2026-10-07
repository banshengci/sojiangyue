import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart';

import 'base_tool.dart';

class DistillCharactersInput {
  DistillCharactersInput({required this.bookId, this.chapterCharBudget});

  final int bookId;
  final int? chapterCharBudget;

  factory DistillCharactersInput.fromJson(Map<String, dynamic> json) =>
      DistillCharactersInput(
        bookId: (json['bookId'] as num).toInt(),
        chapterCharBudget: (json['chapterCharBudget'] as num?)?.toInt(),
      );
}

/// 让 AI 助理「蒸馏」一本书的人物 / 关系 / 世界观 / 时间线，结果自动写入本地库。
/// 复用现有 AiToolRegistry + LangchainAiRegistry 接线，无需新增 AI 栈。
class DistillCharactersTool
    extends RepositoryTool<DistillCharactersInput, Map<String, dynamic>> {
  DistillCharactersTool(this._bookDao, this._dao)
      : super(
          name: 'distill_characters',
          description:
              '对一本书抽取人物卡、人物关系、世界观设定与世界时间线，存入本地数据库，供关系图谱与人物速查使用。输入书籍 ID，耗时较长（大书按章节切片多次调用模型）。仅在用户明确要求“整理人物 / 关系 / 世界观”时使用。',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'bookId': {
                'type': 'integer',
                'description': '必填。要蒸馏的书籍 ID，通常来自书架类工具。'
              },
              'chapterCharBudget': {
                'type': 'integer',
                'description': '可选。每个切片的最大字数，默认 12000。'
              }
            },
            'required': ['bookId'],
          },
          timeout: const Duration(minutes: 30),
        );

  final BookDao _bookDao;
  final CharacterDao _dao;

  @override
  DistillCharactersInput parseInput(Map<String, dynamic> json) =>
      DistillCharactersInput.fromJson(json);

  @override
  Future<Map<String, dynamic>> run(DistillCharactersInput input) async {
    final model = resolveCurrentModel();
    if (model == null) {
      return {'status': 'error', 'message': '尚未配置 AI 服务，无法蒸馏。'};
    }
    final service = CharacterDistillService(
      dao: _dao,
      repository: CharacterDistillRepository(bookDao: _bookDao),
    );

    var last = const DistillProgress(phase: DistillPhase.preparing);
    await for (final p in service.distill(
      bookId: input.bookId,
      model: model,
      chapterCharBudget: input.chapterCharBudget ?? 12000,
    )) {
      last = p;
    }

    final cards = await _dao.getCharacters(input.bookId);
    final relations = await _dao.getRelations(input.bookId);
    return {
      'status': 'ok',
      'bookId': input.bookId,
      'characters': cards.length,
      'relations': relations.length,
      'message': last.message,
    };
  }
}

/// 注册为「内置能力型插件」：由 CharacterDistillPlugin 经 PluginRegistry 自动加载，
/// 并入 AiToolRegistry（见 ai_tool_registry.dart 的 ...PluginRegistry.instance.builtinToolDefinitions）。
/// 因 defaultEnabledToolIds 包含全部定义项，默认即开启，可在 AI 工具设置里关闭。
final AiToolDefinition distillCharactersToolDefinition = AiToolDefinition(
  id: 'distill_characters',
  displayNameBuilder: (_) => '人物蒸馏',
  descriptionBuilder: (_) =>
      '对一本书抽取人物卡、人物关系、世界观设定与时间线，存入本地数据库。',
  build: (_) => DistillCharactersTool(bookDao, characterDao).tool,
);
