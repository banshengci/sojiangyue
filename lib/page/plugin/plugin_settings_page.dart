import 'package:flutter/material.dart';

import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/plugin_rules.dart';
import 'package:songjiang_reader/plugin/plugin_settings.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

/// 单个插件的设置页：宿主渲染的设置项 + 生成增强器开关。
///
/// 两件事放在同一页，是因为它们回答的是同一个问题：
/// **「这个插件能对我造成什么影响」**——
/// 设置决定它怎么工作，增强器决定它能不能改变对话的走向。
class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({super.key, required this.plugin});

  final SongjiangPlugin plugin;

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  Map<String, String> _values = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await PluginSettingsStore.resolve(
      widget.plugin.id,
      widget.plugin.settings,
    );
    if (!mounted) return;
    setState(() {
      _values = values;
      _loading = false;
    });
  }

  Future<void> _set(String key, String value) async {
    final def = widget.plugin.settings.firstWhere((d) => d.key == key);
    final error = validateSettingValue(def, value);
    if (error != null) {
      SjToast.show('$key：$error');
      return;
    }
    final ok =
        await PluginSettingsStore.set(widget.plugin.id, widget.plugin.settings, key, value);
    if (!ok) {
      SjToast.show('保存失败');
      return;
    }
    if (!mounted) return;
    setState(() => _values = {..._values, key: value});
  }

  Future<void> _editText(PluginSettingDef def) async {
    final controller = TextEditingController(text: _values[def.key] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(def.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: def.type == PluginSettingType.integer
              ? TextInputType.number
              : TextInputType.text,
          decoration: InputDecoration(
            hintText: def.hint ?? (def.type == PluginSettingType.integer ? '整数' : ''),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) await _set(def.key, result);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.plugin.settings;
    final enhancers = widget.plugin.enhancers;
    final rules = widget.plugin.rules;

    return Scaffold(
      appBar: AppBar(title: Text(widget.plugin.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (settings.isEmpty && enhancers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('这个插件没有可配置项。'),
                  ),
                for (final def in settings) _buildSettingTile(def),
                if (enhancers.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text(
                      '对对话的影响',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '开启后，这条规则会注入每次 AI 对话的设定里。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  for (final e in enhancers) _buildEnhancerTile(e),
                ],
                if (rules.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Text(
                      '规则',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '满足条件时自动生效，默认关闭。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  for (final r in rules) _buildRuleTile(r),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSettingTile(PluginSettingDef def) {
    final raw = _values[def.key] ?? def.defaultValue ?? '';
    switch (def.type) {
      case PluginSettingType.boolean:
        return SwitchListTile(
          title: Text(def.title),
          subtitle: def.hint == null ? null : Text(def.hint!),
          value: settingAsBool(raw),
          onChanged: (v) => _set(def.key, v ? 'true' : 'false'),
        );
      case PluginSettingType.enum_:
        return ListTile(
          title: Text(def.title),
          subtitle: def.hint == null ? null : Text(def.hint!),
          trailing: DropdownButton<String>(
            value: def.options.contains(raw) ? raw : def.options.firstOrNull,
            items: [
              for (final o in def.options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) {
              if (v != null) _set(def.key, v);
            },
          ),
        );
      case PluginSettingType.integer:
      case PluginSettingType.text:
        return ListTile(
          title: Text(def.title),
          subtitle: Text(raw.isEmpty ? '未设置' : raw),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: () => _editText(def),
        );
    }
  }

  Widget _buildRuleTile(PluginRule r) {
    final on = PluginRegistry.instance.isRuleEnabled(widget.plugin.id, r.id);
    final desc =
        '${describeRuleEvent(r.event)} · ${describeRuleMatch(r.match)}';
    return SwitchListTile(
      title: Text(r.title),
      subtitle: Text(desc),
      value: on,
      onChanged: (v) {
        PluginRegistry.instance.setRuleEnabled(widget.plugin.id, r.id, v);
        setState(() {});
      },
    );
  }

  Widget _buildEnhancerTile(PluginEnhancer e) {
    final on = PluginRegistry.instance.isEnhancerEnabled(
      widget.plugin.id,
      e.id,
    );
    return SwitchListTile(
      title: Text(e.title),
      subtitle: Text(e.rule, maxLines: 3, overflow: TextOverflow.ellipsis),
      value: on,
      onChanged: (v) {
        PluginRegistry.instance.setEnhancerEnabled(widget.plugin.id, e.id, v);
        setState(() {});
      },
    );
  }
}