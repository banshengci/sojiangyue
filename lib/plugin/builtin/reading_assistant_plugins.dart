// lib/plugin/builtin/reading_assistant_plugins.dart
//
// 三个「内置能力型插件」：摘句卡 / 章节回顾 / 共读提问。
//
// 设计原则：内置插件**不走特权通道**——它们不自己写 LLM 调用，而是把配方交给
// `declarative_plugin_tool.dart` 的 toDefinition 编译，与第三方声明式插件
// 完全同一条执行路径。这样内置插件也顺带成了插件引擎的活样例：
// 第三方照着抄结构就能写出能跑的插件。
//
// 为什么选这三个：读书场景里高频、不依赖额外数据源、失败也无害。

import 'package:songjiang_reader/plugin/declarative_plugin_tool.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/service/ai/tools/base_tool.dart';

/// 摘句卡：把选中的一段话做成可分享的短文案。
class QuoteCardPlugin implements SongjiangPlugin {
  const QuoteCardPlugin();

  static const String pluginId = 'com.songjiang.builtin.quote_card';

  static final PluginManifest _manifest = PluginManifest(
    schemaVersion: '1.0',
    id: pluginId,
    name: '摘句卡',
    version: '1.0.0',
    description: '为选中的书摘生成几句话，适合抄进笔记或分享。',
    author: 'songjiang',
    permissions: const [PluginPermission.aiQuery],
    hooks: const [PluginHook(event: PluginEventType.onSelectText, toolId: 'make_quote_card')],
    tools: const [],
  );

  static final PluginToolSpec _spec = PluginToolSpec(
    id: 'make_quote_card',
    displayName: '做摘句卡',
    description: '把一段书摘改写成 3 条适合分享的短句，保留原句意象，注明出处。',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'text': {'type': 'string', 'description': '要处理的原文段落'},
        'book_title': {'type': 'string', 'description': '书名，用于标注出处'},
      },
      'required': ['text', 'book_title'],
    },
    behavior: PluginToolBehavior.aiPrompt,
    prompt: '你在帮读者把一段书摘做成可以抄下来、发给朋友的短句。\n'
        '原文：{{text}}\n'
        '书名：{{book_title}}\n'
        '\n'
        '输出 3 条候选，每条不超过 28 个字。\n'
        '要求：保留原句里的具体意象（物件、动作、天气这类），'
        '不要改写成空泛的抒情；三条的切口要不一样，不要同义反复。\n'
        '每条后面用括号注出处，例如：（《书名》）。\n'
        '只输出三条，用换行分隔，不要序号、不要解释。',
  );

  @override
  String get id => pluginId;
  @override
  String get name => '摘句卡';
  @override
  String get version => '1.0.0';
  @override
  String get description => _manifest.description;
  @override
  String get author => 'songjiang';
  @override
  List<PluginPermission> get permissions => _manifest.permissions;
  @override
  List<PluginHook> get hooks => _manifest.hooks;
  @override
  List<AiToolDefinition> get tools => [toDefinition(_manifest, _spec)];
}

/// 章节回顾：读完一章，用几句话收束。
class ChapterRecapPlugin implements SongjiangPlugin {
  const ChapterRecapPlugin();

  static const String pluginId = 'com.songjiang.builtin.chapter_recap';

  static final PluginManifest _manifest = PluginManifest(
    schemaVersion: '1.0',
    id: pluginId,
    name: '章节回顾',
    version: '1.0.0',
    description: '把一章内容压成一段回顾与几个要点，便于隔天接上。',
    author: 'songjiang',
    permissions: const [PluginPermission.aiQuery],
    hooks: const [PluginHook(event: PluginEventType.onChapterEnter, toolId: 'recap_chapter')],
    tools: const [],
  );

  static final PluginToolSpec _spec = PluginToolSpec(
    id: 'recap_chapter',
    displayName: '做章节回顾',
    description: '把给定章节正文压缩成 200 字内的回顾与 3 个要点。',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'chapter_title': {'type': 'string', 'description': '章节名'},
        'content': {'type': 'string', 'description': '章节正文'},
      },
      'required': ['chapter_title', 'content'],
    },
    behavior: PluginToolBehavior.aiPrompt,
    prompt: '下面是一章的正文，请帮读者做一份能隔天接上的回顾。\n'
        '章节：{{chapter_title}}\n'
        '正文：\n{{content}}\n'
        '\n'
        '输出两部分：\n'
        '1) 一段不超过 200 字的回顾，按发生顺序说清谁做了什么、结果如何；\n'
        '2) 三个要点，每条一行，不超过 20 字，分别对应：关键转折、人物变化、留下的悬念。\n'
        '只写这两部分，不要评价文笔，不要剧透后文。',
  );

  @override
  String get id => pluginId;
  @override
  String get name => '章节回顾';
  @override
  String get version => '1.0.0';
  @override
  String get description => _manifest.description;
  @override
  String get author => 'songjiang';
  @override
  List<PluginPermission> get permissions => _manifest.permissions;
  @override
  List<PluginHook> get hooks => _manifest.hooks;
  @override
  List<AiToolDefinition> get tools => [toDefinition(_manifest, _spec)];
}

/// 共读提问：给一章出几个能聊起来的问题。
class DiscussionQuestionsPlugin implements SongjiangPlugin {
  const DiscussionQuestionsPlugin();

  static const String pluginId = 'com.songjiang.builtin.discussion_questions';

  static final PluginManifest _manifest = PluginManifest(
    schemaVersion: '1.0',
    id: pluginId,
    name: '共读提问',
    version: '1.0.0',
    description: '为一章内容出 5 个由浅入深的讨论问题，适合读书会或自问。',
    author: 'songjiang',
    permissions: const [PluginPermission.aiQuery],
    hooks: const [],
    tools: const [],
  );

  static final PluginToolSpec _spec = PluginToolSpec(
    id: 'discussion_questions',
    displayName: '出讨论问题',
    description: '根据章节内容生成 5 个递进的讨论问题，避免是非题。',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'chapter_title': {'type': 'string', 'description': '章节名'},
        'content': {'type': 'string', 'description': '章节正文'},
      },
      'required': ['chapter_title', 'content'],
    },
    behavior: PluginToolBehavior.aiPrompt,
    prompt: '你要为一章内容准备读书会的讨论问题。\n'
        '章节：{{chapter_title}}\n'
        '正文：\n{{content}}\n'
        '\n'
        '出 5 个问题，由浅入深：前两个关于发生了什么，中间两个关于人物为什么那样选择，'
        '最后一个关于读者自己的判断。\n'
        '要求：不能是是非题，不能有标准答案；每题不超过 40 字；不要引用原文长句。\n'
        '只输出 5 个问题，用换行分隔。',
  );

  @override
  String get id => pluginId;
  @override
  String get name => '共读提问';
  @override
  String get version => '1.0.0';
  @override
  String get description => _manifest.description;
  @override
  String get author => 'songjiang';
  @override
  List<PluginPermission> get permissions => _manifest.permissions;
  @override
  List<PluginHook> get hooks => _manifest.hooks;
  @override
  List<AiToolDefinition> get tools => [toDefinition(_manifest, _spec)];
}
