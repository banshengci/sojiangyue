// lib/page/character/knowledge_page.dart
//
// 原著知识：从全书抽出的可检索事实条目。
//
// 读者读长书时常有"这个门派规矩前面提过吧"的疑问，翻回去找很费劲。
// 本页把这类可查阅的事实抽成条目按主题检索，对应造梦 feature/originalknowledge。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_extras_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_extras.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/distill_background.dart';
import 'package:songjiang_reader/service/character/knowledge_distill_service.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'characters_page_strings.dart';

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({
    super.key,
    required this.bookId,
    this.bookTitle,
  });

  final int bookId;
  final String? bookTitle;

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  final _keywordController = TextEditingController();

  List<KnowledgeItem> _items = [];
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
    final items = await characterExtrasDao.listKnowledge(
      widget.bookId,
      keyword: _keyword,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _extract() async {
    final model = resolveCurrentModel();
    if (model == null) {
      SjToast.show(CharactersPageText.needAiConfig);
      return;
    }
    final incremental = _items.isNotEmpty;
    final service = KnowledgeDistillService(
      repository: CharacterDistillRepository(bookDao: bookDao),
    );
    if (!mounted) return;

    // 流必须在 showDialog 之前建好：若写在 StreamBuilder 的 builder 里，
    // 每次重建都会新建一条流 → 反复向模型发起抽取（重复烧 token）。
    final stream = service.distill(
      bookId: widget.bookId,
      model: model,
      incremental: incremental,
    ).asBroadcastStream();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StreamBuilder<KnowledgeProgress>(
        stream: stream,
        builder: (context, snap) {
          final p = snap.data;
          final done = p?.done ?? false;
          final failed = (p?.failed ?? false) || snap.hasError;
          final total = p?.total ?? 0;
          final processed = p?.processed ?? 0;
          return AlertDialog(
            title: Text(done ? '完成' : '正在抽取原著知识…'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!done && !failed)
                  LinearProgressIndicator(
                    value: total == 0 ? null : processed / total,
                  ),
                const SizedBox(height: 12),
                Text(snap.hasError
                    ? '抽取失败：${snap.error}'
                    : (p?.message ?? '')),
                if ((p?.itemsFound ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  Text('已获得 ${p!.itemsFound} 条知识'),
                ],
              ],
            ),
            actions: [
              if (done || failed)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(CharactersPageText.close),
                )
              else
                TextButton(
                  onPressed: () {
                    // 真正转到后台：由进程级持有者托住，关掉页面也会跑完
                    DistillBackground.run(
                      stream,
                      tag: 'knowledge',
                      onDone: () {
                        if (mounted) _reload();
                      },
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text(CharactersPageText.background),
                ),
            ],
          );
        },
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle == null
            ? '原著知识'
            : '${widget.bookTitle} · 原著知识'),
        actions: [
          IconButton(
            tooltip: _items.isEmpty ? '抽取知识' : '增量更新',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _extract,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _keywordController,
                decoration: const InputDecoration(
                  hintText: '按主题检索',
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
                : _items.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: EmptyStateHint(
                            icon: Icons.menu_book_outlined,
                            title: '原著知识',
                            subtitle: '把书里的规矩、名物、掌故抽成条目，'
                                '以后想查什么直接搜。\n需要 AI 通读全书，请先配置 AI 服务。',
                            action: FilledButton.icon(
                              onPressed: _extract,
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: const Text('抽取知识'),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              title: Text(item.topic,
                                  style: SjText.cardTitle(c.ink)),
                              subtitle: (item.chapter != null &&
                                      item.chapter!.isNotEmpty)
                                  ? Text(item.chapter!,
                                      style: SjText.meta(c.river))
                                  : null,
                              childrenPadding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 12),
                              expandedCrossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(item.summary,
                                    style: SjText.body(c.ink)),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
