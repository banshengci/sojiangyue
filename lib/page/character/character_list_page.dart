import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/ai/langchain_ai_config.dart';
import 'package:songjiang_reader/service/ai/langchain_registry.dart';
import 'package:songjiang_reader/service/character/character_distill_repository.dart';
import 'package:songjiang_reader/service/character/character_distill_service.dart';
import 'package:songjiang_reader/service/enhancement_pack/enhancement_pack_service.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'character_detail_page.dart';
import 'characters_page_strings.dart';
import 'relationship_graph_page.dart';

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
  List<CharacterRelation> _relations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final cards = await characterDao.getCharacters(widget.bookId);
    final relations = await characterDao.getRelations(widget.bookId);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _relations = relations;
      _loading = false;
    });
  }

  Future<void> _runDistill() async {
    final id = AiPrefs.selectedServiceId;
    final raw = AiPrefs.getConfig(id);
    if (raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(CharactersPageText.needAiConfig)));
      }
      return;
    }
    final config = LangchainAiConfig.fromPrefs(id, raw);
    final pipeline = LangchainAiRegistry(null).resolve(config);

    final service = CharacterDistillService(
      dao: characterDao,
      repository: CharacterDistillRepository(bookDao: bookDao),
    );
    final stream = service.distill(
      bookId: widget.bookId,
      model: pipeline.model,
      chapterCharBudget: 12000,
    );

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
                    onPressed: () => Navigator.of(ctx).pop(),
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
            tooltip: hasData
                ? CharactersPageText.redistillButton
                : CharactersPageText.distillButton,
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _runDistill,
          ),
          IconButton(
            tooltip: '导出增强包',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _exportPack,
          ),
          IconButton(
            tooltip: '导入增强包',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _importPack,
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
                    onPressed: _runDistill,
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
                        leading: CircleAvatar(
                          backgroundColor: c.frost,
                          child: Text(
                            card.name.isNotEmpty ? card.name[0] : '?',
                            style: TextStyle(color: c.ink),
                          ),
                        ),
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
