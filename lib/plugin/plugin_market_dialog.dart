// lib/plugin/plugin_market_dialog.dart
//
// 插件市场对话框：拉取目录 → 列出可用插件 → 逐条安装（含 SHA256 校验）/ 卸载。
// 文案使用本地中文常量，规避重新 gen-l10n（与 P0 切片策略一致）。

import 'package:flutter/material.dart';
import 'package:songjiang_reader/plugin/plugin_market_client.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

/// 打开插件市场对话框。
Future<void> showPluginMarketDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const PluginMarketDialog(),
  );
}

class PluginMarketDialog extends StatefulWidget {
  const PluginMarketDialog({super.key});

  @override
  State<PluginMarketDialog> createState() => _PluginMarketDialogState();
}

class _PluginMarketDialogState extends State<PluginMarketDialog> {
  PluginMarketCatalog? _catalog;
  String? _error;
  bool _loading = true;

  /// 每个条目 id 的安装中状态（null=空闲，true=进行中）。
  final Map<String, bool> _installing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _catalog = await PluginMarketClient.instance.fetchCatalog();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isInstalled(String id) =>
      PluginRegistry.instance.plugins.any((p) => p.id == id);

  Future<void> _install(PluginMarketEntry entry) async {
    setState(() => _installing[entry.id] = true);
    try {
      final res = await PluginMarketClient.instance.installEntry(entry);
      if (mounted) {
        SjToast.show('已安装：${res.plugin.name}');
        setState(() {}); // 刷新「已安装」状态。
      }
    } catch (e) {
      if (mounted) SjToast.show('安装失败：${e.toString()}');
    } finally {
      if (mounted) setState(() => _installing[entry.id] = false);
    }
  }

  Future<void> _uninstall(PluginMarketEntry entry) async {
    await PluginRegistry.instance.uninstall(entry.id);
    if (mounted) {
      SjToast.show('已卸载：${entry.name}');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('插件市场'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('加载失败：\n$_error'))
                : _catalog == null || _catalog!.entries.isEmpty
                    ? const Center(child: Text('目录为空'))
                    : ListView.separated(
                        itemCount: _catalog!.entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = _catalog!.entries[i];
                          final installed = _isInstalled(e.id);
                          final busy = _installing[e.id] == true;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${e.name} · ${e.version}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.description,
                                    style: theme.textTheme.bodySmall),
                                const SizedBox(height: 2),
                                Text('作者：${e.author}',
                                    style: theme.textTheme.labelSmall),
                                Text(
                                    'SHA256：${e.sha256.isEmpty ? '缺失' : e.sha256.substring(0, 12)}…',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: Colors.grey)),
                              ],
                            ),
                            trailing: installed
                                ? TextButton(
                                    onPressed: () => _uninstall(e),
                                    child: const Text('卸载'),
                                  )
                                : busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : ElevatedButton(
                                        onPressed: () => _install(e),
                                        child: const Text('安装'),
                                      ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
