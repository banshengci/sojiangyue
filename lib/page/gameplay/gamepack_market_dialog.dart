// lib/page/gameplay/gamepack_market_dialog.dart
//
// 玩法包市场对话框（3.3 分发闭环）：列出目录条目，逐条「安装」，
// 安装即走「下载/读 asset → SHA256 比对 → 解析 → 落盘」链路（安全模型同 2.3 插件市场）。
// 随包示例目录可离线演示；配置 GAMEPACK_MIRROR_URL 后自动切真实远程目录。

import 'package:flutter/material.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_market_client.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

class GamepackMarketDialog extends StatefulWidget {
  const GamepackMarketDialog({super.key, this.onInstalled});

  /// 安装成功后回调（用于父页刷新已安装列表）。
  final VoidCallback? onInstalled;

  @override
  State<GamepackMarketDialog> createState() => _GamepackMarketDialogState();
}

class _GamepackMarketDialogState extends State<GamepackMarketDialog> {
  List<GameplayPackMarketEntry> _entries = const [];
  bool _loading = true;
  final Set<String> _installing = {};
  final Set<String> _installed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final catalog = await GameplayPackMarketClient.instance.fetchCatalog();
      if (mounted) setState(() => _entries = catalog.entries);
    } catch (e) {
      if (mounted) SjToast.show('加载玩法包目录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install(GameplayPackMarketEntry entry) async {
    setState(() => _installing.add(entry.id));
    try {
      final actual =
          await GameplayPackMarketClient.instance.installEntry(entry);
      if (mounted) {
        setState(() => _installed.add(entry.id));
        SjToast.show('已安装「${entry.name}」（sha256=${actual.substring(0, 12)}）');
        widget.onInstalled?.call();
      }
    } catch (e) {
      if (mounted) SjToast.show('安装失败：$e');
    } finally {
      if (mounted) setState(() => _installing.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('玩法包市场'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? const Center(child: Text('目录为空'))
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      final installing = _installing.contains(e.id);
                      final done = _installed.contains(e.id);
                      return ListTile(
                        title: Text(e.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.description,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Chip(
                              label: Text(e.packType,
                                  style: const TextStyle(fontSize: 10)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                        trailing: installing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : TextButton(
                                onPressed: done ? null : () => _install(e),
                                child: Text(done ? '已安装' : '安装'),
                              ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
