// lib/plugin/plugin_event_dispatcher.dart
//
// 插件事件分发器（P0c 起）。
// 在书籍生命周期关键节点发出事件，触发声明了该钩子的插件能力。
// 已实现：onBookImport（入库后）、onBookOpen（打开阅读器）、onChapterEnter
// （进入章节）、onSelectText（划词选中）。后台静默执行，互不阻塞导入 / 阅读主流程。
// 钩子执行：内置能力型（distill_characters）+ 第三方声明式工具（ai_prompt / llmChain），
// 第三方工具受 ai.query 权限约束，经 PluginRegistry.runDeclarativeTool 安全触发。

import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/service/ai/langchain_ai_config.dart';
import 'package:songjiang_reader/service/ai/langchain_registry.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 插件事件分发器（单例）。
///
/// 松江阅只暴露少量、明确的事件（对齐造梦的收敛钩子哲学）。每类事件遍历
/// 已注册插件，执行声明了对应钩子的能力。当前 distill_characters 是内置能力型
/// 钩子，绑定 onBookImport；第三方插件的钩子由 PluginRegistry.loadManifest
/// 编译后的 DeclarativePlugin 同样经此分发。
class PluginEventDispatcher {
  PluginEventDispatcher._();
  static final PluginEventDispatcher instance = PluginEventDispatcher._();

  /// 书籍入库完成。发即弃（fire-and-forget）。
  void onBookImported(int bookId) => _fire(PluginEventType.onBookImport, bookId);

  /// 打开阅读器（书籍开始阅读）。发即弃。
  void onBookOpened(int bookId) => _fire(PluginEventType.onBookOpen, bookId);

  /// 进入某章节。chapterIndex 提供上下文（如注入当前章人物关系）。发即弃。
  void onChapterEntered(int bookId, {int? chapterIndex}) =>
      _fire(PluginEventType.onChapterEnter, bookId, chapterIndex: chapterIndex);

  /// 选中正文文本（阅读器划词）。发即弃；payload 携带选中的 text。
  /// UI 侧划词动作接入后由阅读页调用。
  void onSelectText(int bookId, {required String text}) => _fire(
        PluginEventType.onSelectText,
        bookId,
        payload: {'text': text},
      );

  void _fire(
    PluginEventType event,
    int bookId, {
    int? chapterIndex,
    Map<String, dynamic>? payload,
  }) {
    () async {
      try {
        await _dispatch(
          event,
          bookId,
          chapterIndex: chapterIndex,
          payload: payload,
        );
      } catch (e, st) {
        SjLog.warning(
          'Plugin: 分发异常 event=$event bookId=$bookId: $e\n$st',
        );
      }
    }();
  }

  Future<void> _dispatch(
    PluginEventType event,
    int bookId, {
    int? chapterIndex,
    Map<String, dynamic>? payload,
  }) async {
    if (AiPrefs.getConfig(AiPrefs.selectedServiceId).isEmpty) {
      SjLog.info('Plugin: 未配置 AI 服务，跳过事件 $event bookId=$bookId');
      return;
    }
    SjLog.info('Plugin: 分发事件 $event bookId=$bookId'
        '${chapterIndex != null ? ' chapterIndex=$chapterIndex' : ''}');
    for (final plugin in PluginRegistry.instance.plugins) {
      for (final hook in plugin.hooks) {
        if (hook.event != event) continue;
        // 内置能力型钩子：distill_characters（仅 onBookImport 且开启自动蒸馏时触发）。
        if (hook.toolId == 'distill_characters') {
          if (event == PluginEventType.onBookImport &&
              AiPrefs.autoDistillOnImport) {
            await _runCharacterDistill(bookId);
          }
          continue;
        }
        // 第三方声明式工具（ai_prompt / llmChain）经钩子触发：
        // 仅声明了 ai.query 权限的插件可运行；划词钩子还需 read.book.text
        // （输入会把选中文本注入工具入参）。输入含 bookId / chapterIndex /
        // event，以及事件专属 payload（如 onSelectText 的 text）。
        if (plugin is DeclarativePlugin) {
          if (!plugin.permissions.contains(PluginPermission.aiQuery)) {
            SjLog.warning(
              'Plugin: 钩子工具需 ai.query 权限，跳过 ${plugin.id}/${hook.toolId}',
            );
            continue;
          }
          if (event == PluginEventType.onSelectText &&
              !plugin.permissions.contains(PluginPermission.readBookText)) {
            SjLog.warning(
              'Plugin: 划词钩子需 read.book.text 权限，跳过 ${plugin.id}/${hook.toolId}',
            );
            continue;
          }
          final input = <String, dynamic>{
            'bookId': bookId,
            'chapterIndex': chapterIndex ?? -1,
            'event': event.name,
            if (payload != null) ...payload,
          };
          try {
            final res = await PluginRegistry.instance.runDeclarativeTool(
              plugin.id,
              hook.toolId,
              input,
            );
            SjLog.info(
              'Plugin: 钩子工具完成 ${plugin.id}.${hook.toolId}: $res',
            );
          } catch (e, st) {
            SjLog.warning(
              'Plugin: 钩子工具执行失败 ${plugin.id}.${hook.toolId}: $e\n$st',
            );
          }
        }
      }
    }
  }

  Future<void> _runCharacterDistill(int bookId) async {
    final id = AiPrefs.selectedServiceId;
    final config = LangchainAiConfig.fromPrefs(id, AiPrefs.getConfig(id));
    final model = LangchainAiRegistry(null).resolve(config).model;
    final service = CharacterDistillService(
      dao: characterDao,
      repository: CharacterDistillRepository(bookDao: bookDao),
    );
    var lastMessage = '';
    await for (final p in service.distill(bookId: bookId, model: model)) {
      lastMessage = p.message;
    }
    SjLog.info('Plugin: 自动蒸馏完成 bookId=$bookId（$lastMessage）');
  }
}
