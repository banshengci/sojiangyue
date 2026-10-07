// lib/page/plugin/plugin_workshop_page.dart
//
// 插件工坊：不写 JSON 也能做声明式插件。
//
// 造梦的 pluginbuilder 卖点是「无需编写 JSON 的插件工坊（制作 → 安装试用 →
// ZIP 导出）」。松江阅此前只有「导入 / 导出 .sjgame.zip / plugin.json」，
// 制作环节缺失——用户得手写 manifest。本页把制作过程表单化：
// 填元信息 → 勾权限 → 加工具（单步提示 / 多步提示链）→ 一键安装试用或导出。
//
// 产出的 JSON 严格遵守 songjiang_plugin_contract.dart 的契约，
// 与第三方插件共用同一套校验与运行时。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

/// 单步提示链草稿。
class _StepDraft {
  _StepDraft({required this.as, required this.prompt});

  String as;
  String prompt;

  Map<String, dynamic> toJson() => {'as': as, 'prompt': prompt};
}

/// 工具草稿。
class _ToolDraft {
  _ToolDraft({
    required this.id,
    required this.displayName,
    required this.description,
    required this.behavior,
    required this.prompt,
    List<_StepDraft>? steps,
  }) : steps = steps ?? <_StepDraft>[];

  String id;
  String displayName;
  String description;
  PluginToolBehavior behavior;
  String prompt;
  final List<_StepDraft> steps;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName.isEmpty ? id : displayName,
        if (description.isNotEmpty) 'description': description,
        'behavior': behavior == PluginToolBehavior.llmChain
            ? 'llm_chain'
            : 'ai_prompt',
        if (behavior == PluginToolBehavior.aiPrompt)
          'prompt': prompt
        else
          'steps': steps.map((s) => s.toJson()).toList(),
      };
}

/// 声明式插件可视化制作页。
class PluginWorkshopPage extends StatefulWidget {
  const PluginWorkshopPage({super.key});

  @override
  State<PluginWorkshopPage> createState() => _PluginWorkshopPageState();
}

class _PluginWorkshopPageState extends State<PluginWorkshopPage> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _versionController = TextEditingController(text: '1.0.0');
  final _authorController = TextEditingController();
  final _descController = TextEditingController();

  final Set<PluginPermission> _permissions = {PluginPermission.aiQuery};
  final List<_ToolDraft> _tools = [
    _ToolDraft(
      id: 'my_tool',
      displayName: '',
      description: '',
      behavior: PluginToolBehavior.aiPrompt,
      prompt: '',
    ),
  ];

  @override
  void dispose() {
    for (final c in [
      _idController,
      _nameController,
      _versionController,
      _authorController,
      _descController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _id => _idController.text.trim();
  String get _name => _nameController.text.trim();

  /// 生成符合契约的 manifest JSON。
  Map<String, dynamic> _buildManifest() => {
        'schemaVersion': '1.0',
        'id': _id,
        'name': _name.isEmpty ? _id : _name,
        'version': _versionController.text.trim().isEmpty
            ? '1.0.0'
            : _versionController.text.trim(),
        'description': _descController.text.trim(),
        'author': _authorController.text.trim(),
        'permissions': _permissions.map((p) => p.value).toList(),
        'hooks': <Map<String, dynamic>>[],
        'tools': _tools.map((t) => t.toJson()).toList(),
      };

  /// 校验，返回第一条错误；通过返回 null。
  String? _validate() {
    if (_id.isEmpty) return '请填写插件 ID（英文、数字、下划线）';
    if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(_id)) {
      return '插件 ID 只能包含字母、数字、下划线、点、连字符';
    }
    if (_tools.isEmpty) return '至少添加一个工具';
    final seen = <String>{};
    for (final t in _tools) {
      final tid = t.id.trim();
      if (tid.isEmpty) return '有工具没填 ID';
      if (!seen.add(tid)) return '工具 ID 重复：$tid';
      if (t.behavior == PluginToolBehavior.aiPrompt && t.prompt.trim().isEmpty) {
        return '工具「$tid」是单步提示，prompt 不能为空';
      }
      if (t.behavior == PluginToolBehavior.llmChain) {
        if (t.steps.isEmpty) return '工具「$tid」是提示链，至少需要一个步骤';
        for (final s in t.steps) {
          if (s.prompt.trim().isEmpty) {
            return '工具「$tid」有步骤没写 prompt';
          }
        }
      }
    }
    return null;
  }

  Future<void> _preview() async {
    final err = _validate();
    if (err != null) {
      SjToast.show(err);
      return;
    }
    final text = const JsonEncoder.withIndent('  ').convert(_buildManifest());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('插件 JSON 预览'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) SjToast.show('已复制到剪贴板');
            },
          ),
          TextButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// 安装试用：直接注入 PluginRegistry，立刻可在 AI 工具里被调用。
  Future<void> _tryInstall() async {
    final err = _validate();
    if (err != null) {
      SjToast.show(err);
      return;
    }
    try {
      final manifest = PluginManifest.fromJson(_buildManifest());
      PluginRegistry.instance.loadManifest(manifest);
      if (!mounted) return;
      SjToast.show(
          '已安装试用：${manifest.name}（${manifest.tools.length} 个工具）');
    } catch (e) {
      if (!mounted) return;
      SjToast.show('安装失败：$e');
    }
  }

  /// 导出为 .plugin.zip（内含 plugin.json）。
  Future<void> _export() async {
    final err = _validate();
    if (err != null) {
      SjToast.show(err);
      return;
    }
    try {
      final jsonText =
          const JsonEncoder.withIndent('  ').convert(_buildManifest());
      final archive = Archive()
        ..addFile(ArchiveFile(
          'plugin.json',
          utf8.encode(jsonText).length,
          utf8.encode(jsonText),
        ));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/plugins');
      await dir.create(recursive: true);
      final safe = _id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
      final file = File('${dir.path}/$safe.plugin.zip');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      SjToast.show('已导出：${file.path}');
    } catch (e) {
      if (!mounted) return;
      SjToast.show('导出失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件工坊'),
        actions: [
          IconButton(
            tooltip: '预览 JSON',
            icon: const Icon(Icons.code_outlined),
            onPressed: _preview,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildMetaCard(),
          const SizedBox(height: 14),
          _buildPermissionCard(),
          const SizedBox(height: 14),
          _buildToolsCard(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _tryInstall,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('安装试用'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('导出 ZIP'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '提示词里用 {{text}} 引用输入内容；多步链用 {{上一步的 as}} 串联，'
            '最后一步的输出即工具结果。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard() {
    return _Card(
      title: '基本信息',
      children: [
        TextField(
          controller: _idController,
          decoration: const InputDecoration(
            labelText: '插件 ID *',
            hintText: 'my_plugin',
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '显示名称',
            hintText: '我的插件',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _versionController,
                decoration: const InputDecoration(
                  labelText: '版本',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _authorController,
                decoration: const InputDecoration(
                  labelText: '作者',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: '描述',
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionCard() {
    return _Card(
      title: '权限',
      subtitle: '未声明即不可用',
      children: [
        for (final p in PluginPermission.values)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(p.value, style: const TextStyle(fontSize: 13)),
            value: _permissions.contains(p),
            onChanged: (v) => setState(() {
              if (v == true) {
                _permissions.add(p);
              } else {
                _permissions.remove(p);
              }
            }),
          ),
      ],
    );
  }

  Widget _buildToolsCard() {
    return _Card(
      title: '工具',
      subtitle: '${_tools.length} 个',
      trailing: TextButton.icon(
        icon: const Icon(Icons.add, size: 16),
        label: const Text('加工具'),
        onPressed: () => setState(
          () => _tools.add(_ToolDraft(
            id: 'tool_${_tools.length + 1}',
            displayName: '',
            description: '',
            behavior: PluginToolBehavior.aiPrompt,
            prompt: '',
          )),
        ),
      ),
      children: [
        for (var i = 0; i < _tools.length; i++) _buildToolEditor(i),
      ],
    );
  }

  Widget _buildToolEditor(int index) {
    final tool = _tools[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tool.displayName.isEmpty ? tool.id : tool.displayName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: '删除工具',
                  onPressed: _tools.length <= 1
                      ? null
                      : () => setState(() => _tools.removeAt(index)),
                ),
              ],
            ),
            _labeledField(
              '工具 ID *',
              initial: tool.id,
              onChanged: (v) => tool.id = v,
            ),
            const SizedBox(height: 6),
            _labeledField(
              '显示名称',
              initial: tool.displayName,
              onChanged: (v) => tool.displayName = v,
            ),
            const SizedBox(height: 6),
            _labeledField(
              '描述',
              initial: tool.description,
              onChanged: (v) => tool.description = v,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PluginToolBehavior>(
              initialValue: tool.behavior,
              isDense: true,
              decoration: const InputDecoration(
                labelText: '行为',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: PluginToolBehavior.aiPrompt,
                  child: Text('单步提示（ai_prompt）'),
                ),
                DropdownMenuItem(
                  value: PluginToolBehavior.llmChain,
                  child: Text('多步提示链（llm_chain）'),
                ),
              ],
              onChanged: (v) => setState(() {
                tool.behavior = v ?? PluginToolBehavior.aiPrompt;
                if (tool.behavior == PluginToolBehavior.llmChain &&
                    tool.steps.isEmpty) {
                  tool.steps.add(_StepDraft(as: 'step', prompt: ''));
                }
              }),
            ),
            const SizedBox(height: 8),
            if (tool.behavior == PluginToolBehavior.aiPrompt)
              _labeledField(
                '提示词 *',
                initial: tool.prompt,
                maxLines: 4,
                hint: '例如：把下面这段改写成白话文：\n{{text}}',
                onChanged: (v) => tool.prompt = v,
              )
            else ...[
              const Text('步骤（按顺序执行，后步可引用前步的 as）',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              for (var s = 0; s < tool.steps.length; s++) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _labeledField(
                        '变量名 as',
                        initial: tool.steps[s].as,
                        onChanged: (v) => tool.steps[s].as = v,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: tool.steps.length <= 1
                          ? null
                          : () => setState(() => tool.steps.removeAt(s)),
                    ),
                  ],
                ),
                _labeledField(
                  '提示词 *',
                  initial: tool.steps[s].prompt,
                  maxLines: 3,
                  hint: '可用 {{text}} 或 {{上一步的 as}}',
                  onChanged: (v) => tool.steps[s].prompt = v,
                ),
                const SizedBox(height: 6),
              ],
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('加步骤'),
                onPressed: () => setState(() => tool.steps
                    .add(_StepDraft(as: 'step', prompt: ''))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _labeledField(
    String label, {
    String? initial,
    int maxLines = 1,
    String? hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      initialValue: initial,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: onChanged,
    );
  }
}

/// 通用分区卡片。
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
