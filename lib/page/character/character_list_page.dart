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
import 'package:songjiang_reader/service/enhancement_pack/enhancement_pack_service.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'card_library_page.dart';
import 'character_avatar.dart';
import 'character_chat_sessions_page.dart';
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

  /// 把蒸馏流交给后台：由进程级持有者托住订阅，
  /// 这样即便用户离开本页，任务也会跑完。
  void _detachDistillToBackground(Stream<DistillProgress> stream) {
    DistillBackground.run(
      stream,
      tag: 'characters',
      onDone: () {
        if (mounted) _reload();
      },
    );
  }

  /// 已有数据时先让用户选增量还是全量：增量只跑新增内容，
  /// 全量会把整本书重新烧一遍 token，不该是默认动作。
  Future<void> _startDistill() async {
    if (_cards.isEmpty) {
      await _runDistill();
      return;
    }
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                CharactersPageText.distillModeTitle,
                style: SjText.sectionTitle(SjColors.of(ctx).ink),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: const Text(CharactersPageText.distillIncremental),
              subtitle: const Text(CharactersPageText.distillIncrementalHint),
              onTap: () => Navigator.pop(ctx, 'incremental'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text(CharactersPageText.distillFull),
              subtitle: const Text(CharactersPageText.distillFullHint),
              onTap: () => Navigator.pop(ctx, 'full'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (mode == null || !mounted) return;
    await _runDistill(incremental: mode == 'incremental');
  }

  Future<void> _runDistill({bool incremental = true}) async {
    // 统一解析：优先新的 provider 体系，再回退旧 aiConfig_* 体系。
    // 之前这里只读 AiPrefs.getConfig(selectedServiceId)，而 AI 设置页只写
    // aiProviders，导致配置明明填好了却仍弹出「请先配置 AI」。
    final model = resolveCurrentModel();
    if (model == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(CharactersPageText.needAiConfig)),
        );
      }
      return;
    }

    final service = CharacterDistillService(
      dao: characterDao,
      repository: CharacterDistillRepository(bookDao: bookDao),
    );
    // 广播流：点「后台运行」后对话框会关闭、StreamBuilder 退订，
    // 若用单订阅流会把生成器一并取消——那样"后台运行"其实是"中止"。
    final stream = service.distill(
      bookId: widget.bookId,
      model: model,
      chapterCharBudget: 12000,
      incremental: incremental,
    ).asBroadcastStream();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<DistillProgress>(
          stream: stream,
          builder: (context, snap) {
            final p = snap.data;
            final phase = p?.phase ?? DistillPhase.preparing;
            final done = phase == DistillPhase.done;
            final failed = phase == DistillPhase.failed || snap.hasError;
            final total = p?.totalChunks ?? 0;
            final processed = p?.processedChunks ?? 0;
            final count = p?.charactersFound ?? 0;
            final skipped = p?.skippedChunks ?? 0;
            final message = snap.hasError
                ? CharactersPageText.distillFailed + snap.error.toString()
                : (p?.message ?? '');

            return AlertDialog(
              title: Text(done
                  ? CharactersPageText.done
                  : CharactersPageText.generatingTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!done && !failed)
                    LinearProgressIndicator(
                      value: total == 0 ? null : processed / total,
                    ),
                  const SizedBox(height: 12),
                  Text(message),
                  if (count > 0) ...[
                    const SizedBox(height: 8),
                    Text(CharactersPageText.charactersCount(count)),
                  ],
                  if (skipped > 0) ...[
                    const SizedBox(height: 4),
                    Text(CharactersPageText.distillSkipped(skipped)),
                  ],
                ],
              ),
              actions: [
                if (done || failed)
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(CharactersPageText.close),
                  )
                else
                  TextButton(
                    onPressed: () {
                      // 真正跑到后台：留一个订阅让生成器继续执行完。
                      _detachDistillToBackground(stream);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text(CharactersPageText.background),
                  ),
              ],
            );
          },
        );
      },
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
