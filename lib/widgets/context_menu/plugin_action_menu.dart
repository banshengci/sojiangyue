// lib/widgets/context_menu/plugin_action_menu.dart
//
// 划词菜单中的「插件动作」区：列出所有已启用、声明了 onSelectText 钩子的插件，
// 点击后直接运行其声明式工具（ai_prompt / llmChain），并把 Markdown 结果就地展示。
//
// 这条链路打通了「阅读页划词 → on_select_text 钩子 → 第三方 AI 插件」的端到端闭环：
// plugin_event_dispatcher 与 plugin_registry 已实现了钩子执行与多步链，
// 此处是消费侧 UI 的最后一块拼图。安全边界仍由插件体系保证——插件只能拼模板调 LLM，
// 不引入任何 Dart 代码。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:songjiang_reader/page/reading_page.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/widgets/common/axis_flex.dart';

class PluginActionMenu extends StatefulWidget {
  const PluginActionMenu({
    super.key,
    required this.content,
    required this.decoration,
    required this.axis,
  });

  final String content;
  final BoxDecoration decoration;
  final Axis axis;

  /// 是否存在可用于划词菜单的插件动作（已启用 + 声明了 onSelectText 钩子）。
  /// 供上层 context_menu 决定是否插入本组件及其间距。
  static bool hasActions() => PluginRegistry.instance.plugins.any((p) =>
      PluginRegistry.instance.isEnabled(p.id) &&
      p.hooks.any((h) => h.event == PluginEventType.onSelectText));

  @override
  State<PluginActionMenu> createState() => _PluginActionMenuState();
}

class _PluginActionMenuState extends State<PluginActionMenu> {
  late final List<_PluginAction> _actions;
  String? _runningLabel;
  bool _loading = false;
  String? _activeLabel;
  String? _resultMd;
  String? _error;

  @override
  void initState() {
    super.initState();
    _actions = _collectActions();
  }

  List<_PluginAction> _collectActions() {
    final out = <_PluginAction>[];
    for (final p in PluginRegistry.instance.plugins) {
      if (!PluginRegistry.instance.isEnabled(p.id)) continue;
      for (final h in p.hooks) {
        if (h.event != PluginEventType.onSelectText) continue;
        final label = (h.ui?['actionLabel'] as String?) ?? p.name;
        out.add(_PluginAction(
          pluginId: p.id,
          toolId: h.toolId,
          label: label,
        ));
      }
    }
    return out;
  }

  Future<void> _run(_PluginAction action) async {
    if (_loading) return;
    // 锁定选区：避免运行期间 WebView 选区清除事件误关 overlay，导致结果丢失。
    epubPlayerKey.currentState?.setSelectionClearLocked(true);
    setState(() {
      _loading = true;
      _runningLabel = action.label;
      _activeLabel = action.label;
      _resultMd = null;
      _error = null;
    });
    try {
      final raw = await PluginRegistry.instance
          .runDeclarativeTool(action.pluginId, action.toolId, {
        'text': widget.content,
      });
      if (!mounted) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['status'] == 'ok') {
        setState(() {
          _resultMd = map['result'] as String? ?? '';
          _loading = false;
        });
      } else {
        setState(() {
          _error = map['message'] as String? ?? '插件执行失败';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_actions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: widget.axis == Axis.vertical ? 100 : double.infinity,
      decoration: widget.decoration,
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: AxisFlex(
          axis: widget.axis,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AxisFlex(
              axis: widget.axis == Axis.horizontal
                  ? Axis.vertical
                  : Axis.horizontal,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in _actions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: PointerInterceptor(
                      child: TextButton.icon(
                        onPressed: _loading ? null : () => _run(a),
                        icon: _loading && _runningLabel == a.label
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome, size: 16),
                        label: Text(a.label),
                      ),
                    ),
                  ),
              ],
            ),
            if (_activeLabel != null) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (_loading && _runningLabel == _activeLabel)
                const SizedBox(
                  height: 20,
                  child: Center(child: Text('生成中…')),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                )
              else if (_resultMd != null && _resultMd!.isNotEmpty)
                GptMarkdown(
                  _resultMd!,
                  style: const TextStyle(fontSize: 14),
                )
              else
                const SizedBox.shrink(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PluginAction {
  const _PluginAction({
    required this.pluginId,
    required this.toolId,
    required this.label,
  });
  final String pluginId;
  final String toolId;
  final String label;
}
