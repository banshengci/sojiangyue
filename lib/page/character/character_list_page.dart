import 'dart:async';

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart';
import 'package:songjiang_reader/service/character/distill_background.dart';
import 'package:songjiang_reader/service/long_task/task_manifest.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/distill/distill_progress_dialog.dart';
import 'package:songjiang_reader/service/enhancement_pack/enhancement_pack_service.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'card_library_page.dart';
import 'character_avatar.dart';
import 'character_chat_sessions_page.dart';
import 'character_cleanup_page.dart';
import 'character_detail_page.dart';
import 'characters_page_strings.dart';
import 'crossover_page.dart';
import 'knowledge_page.dart';
import 'relationship_graph_page.dart';
import 'story_recap_page.dart';
import 'world_timeline_page.dart';

/// 一本书的人物速查页：列表 + 一键蒸馏 + 关系图入口。
class CharacterListPage extends StatefulWidget {
  const CharacterListPage({super.key, required this.bookId, this.bookTitle});

  final int bookId;
  final String? bookTitle;

  @override
  State<CharacterListPage> createState() => _CharacterListPageState();
}

class _CharacterListPageState extends State<CharacterListPage> {
  List<CharacterCard> _cards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }
  Future<void> _reload() async {
    setState(() => _loading = true);
    final cards = await characterDao.getCharacters(widget.bookId);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  /// 用户停止蒸馏后，把任务清单里的状态改成「已取消」，
  /// 免得任务中心一直显示「进行中」。
  Future<void> _markDistillCanceled() async {
    try {
      final store = TaskManifestStore.instance;
      for (final t in await store.list()) {
        if (t.kind == 'distill' && t.bookId == widget.bookId) {
          await store.upsert(t.copyWith(status: LongTaskStatus.canceled));
        }
      }
    } catch (e) {
      SjLog.warning('Distill: 标记取消状态失败: $e');
    }
  }

  /// 蒸馏前的选项面板：增量 / 全量 + 收录范围，并把蒸馏原理讲清楚。
  Future<void> _startDistill() async {
    if (_cards.isEmpty) {
      await _runDistill();
      return;
    }

    // 变量声明在 showModalBottomSheet 之外：StatefulBuilder 重建时不会重置
    var incremental = true;
    var majorOnly = false;

    final opts = await showModalBottomSheet<_DistillOptions>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final c = SjColors.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Text(CharactersPageText.distillModeTitle,
                        style: SjText.sectionTitle(c.ink)),
                  ),
                  SwitchListTile(
                    value: incremental,
                    onChanged: (v) => setSheetState(() => incremental = v),
                    title: const Text(CharactersPageText.distillIncrementalSwitch),
                    subtitle:
                        const Text(CharactersPageText.distillIncrementalSwitchHint),
                  ),
                  SwitchListTile(
                    value: majorOnly,
                    onChanged: (v) => setSheetState(() => majorOnly = v),
                    title: const Text(CharactersPageText.distillMajorOnlySwitch),
                    subtitle:
                        const Text(CharactersPageText.distillMajorOnlyHint),
                  ),
                  const Divider(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                    child: Text(CharactersPageText.distillHowItWorksTitle,
                        style: SjText.meta(c.ink)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                    child: Text(
                      CharactersPageText.distillHowItWorks,
                      style: SjText.meta(c.inkSoft).copyWith(height: 1.7),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(
                          ctx,
                          _DistillOptions(
                            incremental: incremental,
                            majorOnly: majorOnly,
                          ),
                        ),
                        child: const Text(CharactersPageText.distillStart),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (opts == null || !mounted) return;
    await _runDistill(
      incremental: opts.incremental,
      minImportance: opts.majorOnly ? 50 : 0,
    );
  }

  Future<void> _runDistill({
    bool incremental = true,
    int minImportance = 0,
  }) async {
    // 统一解析：优先新的 provider 体系，再回退旧 aiConfig_* 体系。
    // 只读 AiPrefs.getConfig(selectedServiceId) 会漏掉新体系，导致配置好了
    // 仍提示「请先配置 AI」。
    final model = resolveCurrentModel();
    if (model == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(CharactersPageText.needAiConfig)),
        );
      }
      return;
    }

    // 同一本书同一时刻只允许跑一个蒸馏：重复点击直接提示，
    // 避免并发出多个任务把 token 烧两遍。
    final tag = DistillBackground.charactersTag(widget.bookId);
    if (DistillBackground.isRunning(tag)) {
      SjToast.show(CharactersPageText.distillAlreadyRunning);
      return;
    }

    final service = CharacterDistillService(
      dao: characterDao,
      repository: CharacterDistillRepository(bookDao: bookDao),
    );

    final view = ValueNotifier<DistillProgressView?>(null);
    final error = ValueNotifier<Object?>(null);

    // 订阅交给 DistillBackground 持有：关掉对话框任务继续跑（后台运行），
    // 想停随时可以在对话框里点「停止」，或到任务中心停。
    DistillBackground.run(
      service.distill(
        bookId: widget.bookId,
        model: model,
        chapterCharBudget: 12000,
        incremental: incremental,
        minImportance: minImportance,
      ),
      tag: tag,
      onEvent: (e) {
        final p = e as DistillProgress;
        view.value = DistillProgressView(
          message: p.message,
          ratio:
              p.totalChunks == 0 ? null : p.processedChunks / p.totalChunks,
          done: p.phase == DistillPhase.done,
          failed: p.phase == DistillPhase.failed,
          countText: p.charactersFound > 0
              ? CharactersPageText.charactersCount(p.charactersFound)
              : null,
          skipped: p.skippedChunks,
        );
      },
      onError: (e) => error.value = e,
      onCanceled: _markDistillCanceled,
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DistillProgressDialog(
        view: view,
        error: error,
        tag: tag,
        runningTitle: CharactersPageText.generatingTitle,
        doneTitle: CharactersPageText.done,
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _exportPack() async {
    try {
      final path = await EnhancementPackService(characterDao).exportCharacterGraph(
        widget.bookId,
        widget.bookTitle ?? '本书',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导出增强包：$path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  Future<void> _importPack() async {
    final bytes = await EnhancementPackService.pickPackBytes();
    if (bytes == null) return;
    try {
      final n = await EnhancementPackService(characterDao)
          .importCharacterGraph(widget.bookId, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入 $n 个人物')));
        await _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Text(label),
          ],
        ),
      );

  /// AppBar 溢出菜单：把低频入口收起来，避免一排图标挤成一团。
  Future<void> _handleMenu(String value) async {
    Widget? page;
    switch (value) {
      case 'cleanup':
        page = CharacterCleanupPage(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
        );
      case 'world':
        page = WorldTimelinePage(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
          onRequestDistill: () => _runDistill(),
        );
      case 'cards':
        page = CardLibraryPage(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
        );
      case 'knowledge':
        page = KnowledgePage(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
        );
      case 'recap':
        page = StoryRecapPage(
          bookId: widget.bookId,
          bookTitle: widget.bookTitle,
        );
      case 'crossover':
        page = const CrossoverPage();
      case 'export':
        await _exportPack();
        return;
      case 'import':
        await _importPack();
        return;
    }
    if (page == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page!),
    );
    // 从原著知识等页面回来后，人物数据可能已更新
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final hasData = _cards.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle ?? CharactersPageText.charactersTitle),
        actions: [
          if (hasData)
            IconButton(
              tooltip: CharactersPageText.viewGraph,
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RelationshipGraphPage(
                    bookId: widget.bookId,
                    bookTitle: widget.bookTitle,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: CharactersPageText.chatSessionsTitle,
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CharacterChatSessionsPage(
                  bookId: widget.bookId,
                  bookTitle: widget.bookTitle,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: hasData
                ? CharactersPageText.redistillButton
                : CharactersPageText.distillButton,
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _startDistill,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _handleMenu,
            itemBuilder: (_) => [
              _menuItem('cleanup', Icons.cleaning_services_outlined,
                  CharactersPageText.cleanupTitle),
              _menuItem('world', Icons.public_outlined,
                  CharactersPageText.worldTimelineTitle),
              _menuItem('cards', Icons.style_outlined,
                  CharactersPageText.cardLibraryTitle),
              _menuItem('knowledge', Icons.menu_book_outlined, '原著知识'),
              _menuItem('recap', Icons.history_edu_outlined, '剧情回顾'),
              _menuItem('crossover', Icons.swap_horiz, '穿越联动'),
              const PopupMenuDivider(),
              _menuItem('export', Icons.file_upload_outlined, '导出增强包'),
              _menuItem('import', Icons.file_download_outlined, '导入增强包'),
            ],
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingHint()
          : !hasData
              ? EmptyStateHint(
                  icon: Icons.group_outlined,
                  title: CharactersPageText.charactersTitle,
                  subtitle: CharactersPageText.charactersEmptyHint,
                  action: FilledButton.icon(
                    onPressed: _startDistill,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text(CharactersPageText.distillButton),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _cards.length,
                  itemBuilder: (context, index) {
                    final card = _cards[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: characterAvatar(card, c),
                        title: Text(
                          card.name,
                          style: SjText.cardTitle(c.ink),
                        ),
                        subtitle: card.role != null && card.role!.isNotEmpty
                            ? Text(card.role!, style: SjText.meta(c.inkSoft))
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.frost,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${CharactersPageText.importance} ${card.importance}',
                            style: SjText.meta(c.inkSoft),
                          ),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CharacterDetailPage(
                              bookId: widget.bookId,
                              character: card,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// 蒸馏前的选项。
class _DistillOptions {
  const _DistillOptions({required this.incremental, required this.majorOnly});

  final bool incremental;
  final bool majorOnly;
}
