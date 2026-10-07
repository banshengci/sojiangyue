// lib/page/gameplay/gameplay_center_page.dart
//
// 玩法中心页（3.3 入口）：浏览已安装玩法包，按类型展示名场面卡 / 读书挑战 /
// 阅读剧本，并支持导入、导出、激活为插件、分享名场面卡。
//
// 与 2.3 插件系统打通：reading_script 包的脚本工具可一键「激活为插件」，
// 经 GameplayPackService.activatePack 注入 PluginRegistry。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/plugin/declarative_plugin_tool.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/page/character/character_chat_page.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_modes.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_models.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_service.dart';
import 'package:songjiang_reader/page/gameplay/gamepack_market_dialog.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

class GameplayCenterPage extends ConsumerStatefulWidget {
  const GameplayCenterPage({super.key, this.controller});

  /// 可选的滚动控制器：接入底部导航的滚动隐藏联动。
  final ScrollController? controller;

  @override
  ConsumerState<GameplayCenterPage> createState() => _GameplayCenterPageState();
}

class _GameplayCenterPageState extends ConsumerState<GameplayCenterPage> {
  List<GameplayPackManifest> _packs = const [];
  Set<String> _activated = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// 随包示例玩法包资源（离线演示：红楼诗词闯关 / 三国名场面 / 每日挑战）。
  static const List<String> _bundledSampleAssets = [
    'assets/gameplay/hlm_quiz.sjgame.zip',
    'assets/gameplay/sanguo_scene.sjgame.zip',
    'assets/gameplay/daily_challenge.sjgame.zip',
  ];

  /// 随包示例是否已装载过（只自动装一次，用户手动移除后不再塞回来）。
  static const String _bundledLoadedKey = 'gameplay.bundledSamplesLoaded';

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _ensureBundledSamples();
    final packs = await GameplayPackService.instance.listInstalled();
    // 重启后恢复已激活脚本包的工具注入（能力持久化）。
    await GameplayPackService.instance.restoreActivated(packs);
    final activated = await GameplayPackService.instance.activatedIds();
    if (mounted) {
      setState(() {
        _packs = packs;
        _activated = activated;
        _loading = false;
      });
    }
  }

  /// 首次进入玩法中心时自动装载随包示例。
  ///
  /// 否则用户第一次打开只会看到一个空页面，需要自己去点右上角按钮才知道
  /// 有示例可加载——表现上就是「玩法中心用不了」。
  Future<void> _ensureBundledSamples() async {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool(_bundledLoadedKey) ?? false) return;
    // 先落标记：即便加载失败也不反复重试，避免每次进页面都弹一堆提示。
    await sp.setBool(_bundledLoadedKey, true);

    for (final asset in _bundledSampleAssets) {
      try {
        final data = await rootBundle.load(asset);
        final bytes = data.buffer.asUint8List();
        final manifest = await GameplayPackService.instance.importPack(bytes);
        await GameplayPackService.instance.saveInstalled(manifest);
      } catch (e) {
        SjLog.warning('Gameplay: 自动装载示例失败 $asset：$e');
      }
    }
  }

  Future<void> _import() async {
    final bytes = await GameplayPackService.pickPackBytes();
    if (bytes == null) return;
    try {
      final manifest = await GameplayPackService.instance.importPack(bytes);
      await GameplayPackService.instance.saveInstalled(manifest);
      SjToast.show('已导入玩法包：${manifest.name}');
      await _reload();
    } catch (e) {
      SjToast.show('导入失败：$e');
    }
  }

  /// 加载随包示例玩法包（离线演示：红楼诗词闯关 / 三国名场面 / 每日挑战）。
  Future<void> _loadBundledSamples() async {
    const samples = [
      'assets/gameplay/hlm_quiz.sjgame.zip',
      'assets/gameplay/sanguo_scene.sjgame.zip',
      'assets/gameplay/daily_challenge.sjgame.zip',
    ];
    int ok = 0;
    for (final asset in samples) {
      try {
        final data = await rootBundle.load(asset);
        final bytes = data.buffer.asUint8List();
        final manifest = await GameplayPackService.instance.importPack(bytes);
        await GameplayPackService.instance.saveInstalled(manifest);
        ok++;
      } catch (e) {
        SjToast.show('加载示例失败 $asset：$e');
      }
    }
    if (mounted) {
      SjToast.show(ok > 0 ? '已加载 $ok 个示例玩法包' : '未加载任何示例');
      await _reload();
    }
  }

  Future<void> _export(GameplayPackManifest manifest) async {
    try {
      final bytes = await GameplayPackService.instance.exportPack(manifest);
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/gameplay_packs');
      await dir.create(recursive: true);
      final safe = manifest.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File('${dir.path}/$safe.sjgame.zip');
      await file.writeAsBytes(bytes);
      SjToast.show('已导出：${file.path}');
    } catch (e) {
      SjToast.show('导出失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final byType = <String, List<GameplayPackManifest>>{};
    for (final p in _packs) {
      byType.putIfAbsent(p.packType, () => []).add(p);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('玩法中心'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导入玩法包',
            onPressed: _import,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _reload,
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: '加载随包示例玩法包',
            onPressed: _loadBundledSamples,
          ),
          IconButton(
            icon: const Icon(Icons.store_outlined),
            tooltip: '玩法包市场',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  GamepackMarketDialog(onInstalled: () => _reload()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: widget.controller,
              padding: const EdgeInsets.all(12),
              children: [
                _buildModesSection(context),
                if (_packs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: 26, bottom: 12),
                    child: Text(
                      '暂无玩法包。\n'
                      '可从插件市场获取「阅读剧本 / 读书挑战 / 名场面卡」玩法包，'
                      '或导入 .sjgame.zip。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                else ...[
                  _buildSection(
                    context,
                    '名场面卡',
                    Icons.auto_stories_outlined,
                    byType[GameplayPackType.sceneCard] ?? [],
                  ),
                  _buildSection(
                    context,
                    '读书挑战',
                    Icons.flag_outlined,
                    byType[GameplayPackType.readingChallenge] ?? [],
                  ),
                  _buildSection(
                    context,
                    '阅读剧本 / 闯关',
                    Icons.theater_comedy_outlined,
                    byType[GameplayPackType.readingScript] ?? [],
                  ),
                ],
              ],
            ),
    );
  }

  // ---- 玩法模式：选玩法 → 选书 → 选人物 → 开一局 ----

  Widget _buildModesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_play_outlined,
                size: 18, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('玩法模式',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('${kBuiltinGameplayModes.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(left: 26, top: 4, bottom: 10),
          child: Text('选一个玩法，挑一位人物，立刻开一局',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in kBuiltinGameplayModes)
                _modeCard(context, mode),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _modeCard(BuildContext context, GameplayMode mode) {
    return InkWell(
      onTap: () => _startMode(mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(mode.icon, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(mode.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(mode.summary,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Future<void> _startMode(GameplayMode mode) async {
    final books = await bookDao.selectNotDeleteBooks();
    if (!mounted) return;
    if (books.isEmpty) {
      SjToast.show('书架里还没有书');
      return;
    }
    final book = books.length == 1 ? books.first : await _pickBook(books);
    if (book == null || !mounted) return;

    final cards = await characterDao.getCharacters(book.id);
    if (!mounted) return;
    if (cards.isEmpty) {
      SjToast.show('《${book.title}》还没有人物，先做一次人物蒸馏');
      return;
    }
    final card = await _pickCharacter(cards);
    if (card == null || !mounted) return;

    // 玩法自带场景提示：随机取一条当开局情境
    final scene = mode.randomSceneHint(Random());
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterChatPage(
          bookId: book.id,
          characterName: card.name,
          bookTitle: book.title,
          gameplayDirective: mode.directive,
          opening: scene,
        ),
      ),
    );
  }

  Future<Book?> _pickBook(List<Book> books) => showModalBottomSheet<Book>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('选一本书'),
              ),
              for (final b in books)
                ListTile(
                  title: Text(b.title),
                  onTap: () => Navigator.pop(ctx, b),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );

  Future<CharacterCard?> _pickCharacter(List<CharacterCard> cards) =>
      showModalBottomSheet<CharacterCard>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text('选一位出场人物'),
              ),
              for (final card in cards.take(80))
                ListTile(
                  title: Text(card.name),
                  subtitle: (card.role != null && card.role!.isNotEmpty)
                      ? Text(card.role!)
                      : null,
                  onTap: () => Navigator.pop(ctx, card),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<GameplayPackManifest> packs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('${packs.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        if (packs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 26, bottom: 12),
            child: Text('（空）', style: TextStyle(color: Colors.grey)),
          )
        else
          ...packs.map((p) => _buildPackCard(context, p)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPackCard(BuildContext context, GameplayPackManifest pack) {
    return Card(
      margin: const EdgeInsets.only(left: 26, bottom: 10, right: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(pack.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  tooltip: '导出 .sjgame.zip',
                  onPressed: () => _export(pack),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: '移除',
                  onPressed: () async {
                    await GameplayPackService.instance.removeInstalled(pack.id);
                    SjToast.show('已移除：${pack.name}');
                    await _reload();
                  },
                ),
              ],
            ),
            if (pack.bookScope != null && pack.bookScope!.isNotEmpty)
              Text('适用：${pack.bookScope}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (pack.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(pack.description,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            const SizedBox(height: 8),
            if (pack.packType == GameplayPackType.sceneCard)
              ...pack.sceneCards.map((c) => _buildSceneCard(context, c)),
            if (pack.packType == GameplayPackType.readingChallenge)
              ...pack.challenges.map((c) => _buildChallenge(context, c)),
            if (pack.packType == GameplayPackType.readingScript)
              _buildScriptPack(context, pack),
          ],
        ),
      ),
    );
  }

  Widget _buildSceneCard(BuildContext context, SceneCard card) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('「${card.quote}」',
              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          const SizedBox(height: 4),
          Text(
            card.chapter != null && card.chapter!.isNotEmpty
                ? '——《${card.bookTitle}》${card.chapter}'
                : '——《${card.bookTitle}》',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (card.context != null && card.context!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(card.context!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.share, size: 16),
              label: const Text('分享名场面'),
              onPressed: () => GameplayPackService.shareSceneCard(card),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChallenge(BuildContext context, ReadingChallenge c) {
    final metricLabel = {
      'daily_minutes': '每日分钟',
      'daily_pages': '每日页', 'weekly_books': '每周本'
    }[c.metric] ?? c.metric;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${c.title} · $metricLabel ${c.target} / ${c.periodDays}天'
                '${c.rewardAchievement != null ? ' · 成就:${c.rewardAchievement}' : ''}'),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptPack(BuildContext context, GameplayPackManifest pack) {
    final isActivated = _activated.contains(pack.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('含 ${pack.scriptTools.length} 个脚本工具（声明式 llmChain）',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            if (isActivated)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Chip(
                  label: const Text('已激活', style: TextStyle(fontSize: 10)),
                  backgroundColor: Colors.green.withValues(alpha: 0.15),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            TextButton.icon(
              icon: Icon(isActivated ? Icons.check_circle_outline : Icons.extension_outlined,
                  size: 16),
              label: Text(isActivated ? '已激活为插件' : '激活为插件'),
              onPressed: isActivated
                  ? null
                  : () {
                      final n = GameplayPackService.instance.activatePack(pack);
                      setState(() => _activated = {..._activated, pack.id});
                      SjToast.show(n > 0
                          ? '已激活 $n 个脚本工具（注入插件系统）'
                          : '该包无脚本工具');
                    },
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...pack.scriptTools.map((spec) => _buildScriptToolRow(context, pack, spec)),
      ],
    );
  }

  Widget _buildScriptToolRow(
      BuildContext context, GameplayPackManifest pack, PluginToolSpec spec) {
    final stepHint = spec.behavior == PluginToolBehavior.llmChain
        ? '（${spec.steps.length} 步提示链）'
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6, right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.displayName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                if (spec.description.isNotEmpty)
                  Text(spec.description,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (stepHint.isNotEmpty)
                  Text(stepHint,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          TextButton(
            child: const Text('运行剧本'),
            onPressed: () => _runScriptTool(context, pack, spec),
          ),
        ],
      ),
    );
  }

  /// 阅读剧本运行时：输入文本 → 实际跑 langchain llmChain → 展示结果。
  ///
  /// 直接调用 runDeclarativeToolBySpec（无需注册、无需 Riverpod context），
  /// 与声明式插件共用同一运行时；AI 未配置时工具返回 error JSON，这里优雅提示。
  Future<void> _runScriptTool(
    BuildContext context,
    GameplayPackManifest pack,
    PluginToolSpec spec,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogCtx) => _ScriptRunDialog(
        pack: pack,
        spec: spec,
        controller: controller,
      ),
    );
    if (result == null) return; // 取消
    if (!mounted) return;
    if (result['status'] != 'ok') {
      SjToast.show('运行失败：${result['message'] ?? '未知错误'}');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${spec.displayName} · 结果'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result['steps'] is Map)
                ...(result['steps'] as Map).entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('· ${e.key}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey)),
                            Text('${e.value}',
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
              const Divider(),
              Text('${result['result']}',
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

/// 阅读剧本运行弹窗（输入 + 执行 + 加载态）。
class _ScriptRunDialog extends StatefulWidget {
  const _ScriptRunDialog({
    required this.pack,
    required this.spec,
    required this.controller,
  });

  final GameplayPackManifest pack;
  final PluginToolSpec spec;
  final TextEditingController controller;

  @override
  State<_ScriptRunDialog> createState() => _ScriptRunDialogState();
}

class _ScriptRunDialogState extends State<_ScriptRunDialog> {
  bool _running = false;
  String? _error;

  Future<void> _run() async {
    if (widget.controller.text.trim().isEmpty) {
      setState(() => _error = '请输入文本 / 选中内容 / 问题');
      return;
    }
    setState(() => _running = true);
    try {
      final json = await runDeclarativeToolBySpec(
        widget.pack.toPluginManifest(),
        widget.spec,
        {'text': widget.controller.text.trim()},
      );
      final map = jsonDecode(json) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context, map);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context, {
        'status': 'error',
        'message': e.toString(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.spec.displayName),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.spec.description,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: widget.controller,
              maxLines: 6,
              minLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '输入章节文本 / 选中内容 / 问题，将作为 {{text}} 传入剧本',
                contentPadding: EdgeInsets.all(10),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('取消'),
          onPressed: _running ? null : () => Navigator.pop(context),
        ),
        _running
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : FilledButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('运行'),
                onPressed: _run,
              ),
      ],
    );
  }
}
