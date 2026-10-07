// lib/page/character/card_library_page.dart
//
// 卡库：自设卡 + 开局模板。
//
// 造梦 feature/cards 有三类卡（场景卡 / 自设卡 / 开局模板）。松江阅此前只有
// 只读的「名场面卡」（随玩法包分发），读者自己写东西的入口是缺的。本页补齐
// 后两类：
// - 自设卡：一句话设定、一个场面、一条备忘；
// - 开局模板：一段起始情境，可一键带入角色对话，决定 TA 以什么状态开口。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/character_extras_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_extras.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'characters_page_strings.dart';

class CardLibraryPage extends StatefulWidget {
  const CardLibraryPage({
    super.key,
    required this.bookId,
    this.bookTitle,
  });

  final int bookId;
  final String? bookTitle;

  @override
  State<CardLibraryPage> createState() => _CardLibraryPageState();
}

class _CardLibraryPageState extends State<CardLibraryPage> {
  final _keywordController = TextEditingController();

  List<SelfCard> _selfCards = [];
  List<SelfCard> _openings = [];
  bool _loading = true;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final selfs = await characterExtrasDao.listSelfCards(
      widget.bookId,
      kind: SelfCardKind.selfCard,
      keyword: _keyword,
    );
    final openings = await characterExtrasDao.listSelfCards(
      widget.bookId,
      kind: SelfCardKind.opening,
      keyword: _keyword,
    );
    if (!mounted) return;
    setState(() {
      _selfCards = selfs;
      _openings = openings;
      _loading = false;
    });
  }

  Future<void> _edit({SelfCard? card, required SelfCardKind kind}) async {
    final titleController = TextEditingController(text: card?.title ?? '');
    final contentController = TextEditingController(text: card?.content ?? '');
    final tagsController =
        TextEditingController(text: card?.tags.join(' ') ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(card == null
            ? (kind == SelfCardKind.opening ? '新建开局模板' : '新建自设卡')
            : '编辑'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: contentController,
                maxLines: kind == SelfCardKind.opening ? 5 : 3,
                decoration: InputDecoration(
                  labelText: kind == SelfCardKind.opening ? '情境设定' : '内容',
                  hintText: kind == SelfCardKind.opening
                      ? '例如：夜雨，黛玉刚咳过一场，你推门进来。'
                      : '写点什么',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: '标签（空格分隔）',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CharactersPageText.chatCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    final title = titleController.text.trim();
    final content = contentController.text.trim();
    if (saved != true || title.isEmpty || content.isEmpty) {
      if (saved == true) SjToast.show('标题和内容都不能为空');
      return;
    }

    final tags = tagsController.text
        .split(RegExp(r'[\s,，]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final now = DateTime.now();

    if (card == null) {
      await characterExtrasDao.saveSelfCard(
        SelfCard(
          bookId: widget.bookId,
          kind: kind,
          title: title,
          content: content,
          tags: tags,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      await characterExtrasDao.saveSelfCard(
        card.copyWith(
          title: title,
          content: content,
          tags: tags,
          updatedAt: now,
        ),
      );
    }
    if (mounted) SjToast.show('已保存');
    await _reload();
  }

  Future<void> _delete(SelfCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这张卡？'),
        content: Text(card.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CharactersPageText.chatCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || card.id == null) return;
    await characterExtrasDao.deleteSelfCard(card.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(CharactersPageText.cardLibraryTitle),
          bottom: const TabBar(
            tabs: [
              Tab(text: '自设卡'),
              Tab(text: '开局模板'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _keywordController,
                decoration: const InputDecoration(
                  hintText: '搜索卡片',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (v) {
                  _keyword = v;
                  _reload();
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const AppLoadingHint()
                  : TabBarView(
                      children: [
                        _buildList(c, _selfCards, SelfCardKind.selfCard),
                        _buildList(c, _openings, SelfCardKind.opening),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (ctx) {
            final index = DefaultTabController.of(ctx).index;
            return FloatingActionButton(
              onPressed: () => _edit(
                kind: index == 1
                    ? SelfCardKind.opening
                    : SelfCardKind.selfCard,
              ),
              child: const Icon(Icons.add),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(SjColors c, List<SelfCard> cards, SelfCardKind kind) {
    if (cards.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: EmptyStateHint(
            icon: kind == SelfCardKind.opening
                ? Icons.theater_comedy_outlined
                : Icons.style_outlined,
            title: kind == SelfCardKind.opening ? '开局模板' : '自设卡',
            subtitle: kind == SelfCardKind.opening
                ? CharactersPageText.openingEmptyHint
                : CharactersPageText.selfCardEmptyHint,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: cards.length,
      itemBuilder: (context, i) {
        final card = cards[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(card.title, style: SjText.cardTitle(c.ink)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  card.content,
                  style: SjText.meta(c.inkSoft),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (card.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: card.tags
                        .map((t) => Chip(
                              label: Text(t),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelStyle: SjText.meta(c.inkSoft),
                              backgroundColor: c.frost,
                              side: BorderSide.none,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
            isThreeLine: true,
            onTap: () => _edit(card: card, kind: card.kind),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _delete(card),
            ),
          ),
        );
      },
    );
  }
}
