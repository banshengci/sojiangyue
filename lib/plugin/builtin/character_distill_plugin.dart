// lib/plugin/builtin/character_distill_plugin.dart
//
// 第一个「内置能力型插件」：人物蒸馏。
// 把已落地的 distill_characters 工具经插件契约注册，验证插件路径闭环。

import 'package:songjiang_reader/service/ai/tools/base_tool.dart';
import 'package:songjiang_reader/service/ai/tools/character_distill_tool.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

class CharacterDistillPlugin implements SongjiangPlugin {
  const CharacterDistillPlugin();

  @override
  String get id => 'com.songjiang.builtin.character_distill';

  @override
  String get name => '人物蒸馏';

  @override
  String get version => '1.0.0';

  @override
  String get description =>
      '对一本书抽取人物卡、人物关系、世界观设定与时间线，存入本地数据库。';

  @override
  String get author => 'songjiang';

  @override
  List<PluginPermission> get permissions => const [
        PluginPermission.readBookText,
        PluginPermission.aiQuery,
      ];

  @override
  List<AiToolDefinition> get tools => [distillCharactersToolDefinition];

  @override
  List<PluginHook> get hooks => const [
        PluginHook(
          event: PluginEventType.onBookImport,
          toolId: 'distill_characters',
        ),
      ];
}
