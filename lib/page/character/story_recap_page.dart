// lib/page/character/story_recap_page.dart
//
// 剧情回顾：按章节生成/查看前情提要，结果缓存复用。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_extras_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_extras.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/story_recap_service.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'characters_page_strings.dart';

class StoryRecapPage extends StatefulWidget {
  const StoryRecapPage({
    super.key,
    required this.bookId,
    this.bookTitle,
  });

  final int bookId;
  final String? bookTitle;

  @override
  State<StoryRecapPage> createState() => _StoryRecapPageState();
}

class _StoryRecapPageState extends State<StoryRecapPage> {
  final _service = StoryRecapService(
    repository: CharacterDistillRepository(bookDao: bookDao),
  );

  List<StoryRecap> _recaps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final list = await characterExtrasDao.listRecaps(widget.bookId);
    if (!mounted) return;
    setState(() {
      _recaps = list;
      _loading = false;
    });
  }

  /// 选一章 → 生成「读到这一章之前」的前情提要。
  Future<void> _pickChapter() async {
    final model = resolveCurrentModel();
    if (model == null) {
      SjToast.show(CharactersPageText.needAiConfig);
      return;
    }

    List<String> titles;
    try {
      final chapters =
          await _service.repository.getChapters(widget.bookId);
      titles = chapters.map((c) => c.title).toList();
    } catch (e) {
      SjToast.show('读取章节失败：$e');
      return;
    }
    if (!mounted) return;
    if (titles.isEmpty) {
      SjToast.show('这本书还没有可用的章节');
      return;
    }

    final index = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final c = SjColors.of(ctx);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '回顾到哪一章之前？',
                    style: SjText.sectionTitle(c.ink),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: titles.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(
                        '第 ${i + 1} 章 · ${titles[i]}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => Navigator.pop(ctx, i),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (index == null || !mounted) return;
    if (index == 0) {
      SjToast.show('第一章之前没有前情');
      return;
    }

    // 已缓存就直接展示，不重复烧 token
    final cached = await characterExtrasDao.getRecap(widget.bookId, index);
    if (cached != null) {
      if (!mounted) return;
      await _showRecap(cached.chapterTitle ?? titles[index], cached.content);
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('正在整理前情…'),
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('AI 正在回顾前面的章节，请稍候。')),
          ],
        ),
      ),
    );

    String content;
    try {
      content = await _service.generate(
        bookId: widget.bookId,
        chapterIndex: index,
        model: model,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        SjToast.show('生成失败：$e');
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);

    await characterExtrasDao.saveRecap(StoryRecap(
      bookId: widget.bookId,
      chapterIndex: index,
      chapterTitle: titles[index],
      content: content,
      createdAt: DateTime.now(),
    ));
    await _reload();
    if (!mounted) return;
    await _showRecap(titles[index], content);
  }

  Future<void> _showRecap(String title, String content) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = SjColors.of(ctx);
        return AlertDialog(
          title: Text('回顾至 $title'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(content, style: SjText.body(c.ink)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(CharactersPageText.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _delete(StoryRecap recap) async {
    if (recap.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这条回顾？'),
        content: Text(recap.chapterTitle ?? ''),
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
    if (ok != true) return;
    await characterExtrasDao.deleteRecap(recap.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle == null
            ? '剧情回顾'
            : '${widget.bookTitle} · 剧情回顾'),
      ),
      body: _loading
          ? const AppLoadingHint()
          : _recaps.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateHint(
                      icon: Icons.history_edu_outlined,
                      title: '剧情回顾',
                      subtitle: '读到后面忘了前面？\n选一章，让 AI 把之前发生的事讲一遍。',
                      action: FilledButton.icon(
                        onPressed: _pickChapter,
                        icon: const Icon(Icons.auto_stories_outlined),
                        label: const Text('生成前情提要'),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _recaps.length,
                  itemBuilder: (context, i) {
                    final r = _recaps[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: ListTile(
                        title: Text(
                          '回顾至 ${r.chapterTitle ?? '第 ${r.chapterIndex} 章'}',
                          style: SjText.cardTitle(c.ink),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            r.content,
                            style: SjText.meta(c.inkSoft),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        isThreeLine: true,
                        onTap: () =>
                            _showRecap(r.chapterTitle ?? '第 ${r.chapterIndex} 章', r.content),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _delete(r),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _recaps.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _pickChapter,
              tooltip: '生成前情提要',
              child: const Icon(Icons.auto_stories_outlined),
            ),
    );
  }
}
