// lib/page/character/character_cleanup_page.dart
//
// 人物整理：蒸馏出来的角色里挑掉不要的。
//
// 一本大书蒸馏下来常会得到上百个角色，其中大量是只出现一两次的龙套。
// 之前没有挑选的入口——抽到什么就得留什么，人物页和关系图都被噪声挤满。
// 这里按重要度排序 + 多选 + 快捷勾选（主要/次要），批量删除不要的，
// 删除时连同指向它们的关系一起清掉。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_dedupe.dart';
import 'package:songjiang_reader/models/character_relation_merge.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'characters_page_strings.dart';

/// 重要度分界线：>= 50 视为「主要人物」（与蒸馏提示词里的定义一致）。
const int kMajorImportance = 50;

class CharacterCleanupPage extends StatefulWidget {
  const CharacterCleanupPage({
    super.key,
    required this.bookId,
    this.bookTitle,
  });

  final int bookId;
  final String? bookTitle;

  @override
  State<CharacterCleanupPage> createState() => _CharacterCleanupPageState();
}

class _CharacterCleanupPageState extends State<CharacterCleanupPage> {
  List<CharacterCard> _cards = [];
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final cards = await characterDao.getCharacters(widget.bookId);
    // 重要度高的在前，方便一眼看出谁该留
    cards.sort((a, b) => b.importance.compareTo(a.importance));
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _selected.removeWhere((n) => !cards.any((c) => c.name == n));
      _loading = false;
    });
  }

  void _selectWhere(bool Function(CharacterCard) test, {required bool select}) {
    setState(() {
      for (final c in _cards) {
        if (!test(c)) continue;
        if (select) {
          _selected.add(c.name);
        } else {
          _selected.remove(c.name);
        }
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除选中的角色？'),
        content: Text('将删除 $count 个角色，'
            '以及所有指向它们的关系连线。此操作不可撤销。'),
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

    await characterDao.deleteCharacters(widget.bookId, _selected.toList());
    if (!mounted) return;
    SjToast.show('已删除 $count 个角色');
    _selected.clear();
    await _reload();
  }

  /// 把同一个人物的多张卡合并。
  ///
  /// 蒸馏对「这人叫什么」是逐段独立判断的，同一个人常被拆成
  /// 「凌小东 / 小东 / 我 / 主角」好几张，关系也跟着分成几条。
  /// 重跑一次蒸馏能修，但要再花一遍 token；这里直接按别名互指关系就地合并。
  Future<void> _mergeDuplicates() async {
    final cards = await characterDao.getCharacters(widget.bookId);
    if (cards.length < 2) {
      SjToast.show('人物太少，没有可合并的');
      return;
    }
    final merged = mergeSamePerson(cards);
    if (merged.length == cards.length) {
      SjToast.show('没有发现重复人物');
      return;
    }

    final before = {for (final c in cards) c.name};
    final after = {for (final c in merged) c.name};
    final absorbed = before.difference(after);
    final lines = <String>[
      for (final m in merged)
        if ((m.aliases ?? const <String>[]).any(absorbed.contains))
          '${m.name}  ←  '
              '${(m.aliases ?? const <String>[]).where(absorbed.contains).join('、')}',
    ];

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('合并重复人物？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${cards.length} 张卡会合并成 ${merged.length} 张，'
                '指向它们的关系统一改写到正名下。'),
            const SizedBox(height: 10),
            for (final line in lines.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: const TextStyle(fontSize: 12)),
              ),
            if (lines.length > 8)
              Text('…共 ${lines.length} 组', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CharactersPageText.chatCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('合并'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final relations = await characterDao.getRelations(widget.bookId);
    final world = await characterDao.getWorldSettings(widget.bookId);
    final timeline = await characterDao.getTimeline(widget.bookId);
    final index = aliasToName(merged);

    await characterDao.replaceBookGraph(
      bookId: widget.bookId,
      characters: merged,
      // 两端先改写成正名，再去重：否则「妈妈→」和「郑怡云→」会被当成两条
      relations: dedupeRelations([
        for (final r in relations) remapRelation(r, index),
      ]),
      settings: world,
      events: timeline,
    );
    if (!mounted) return;
    SjToast.show('已合并 ${cards.length - merged.length} 个重复人物');
    _selected.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final majorCount =
        _cards.where((e) => e.importance >= kMajorImportance).length;
    final minorCount = _cards.length - majorCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle == null
            ? CharactersPageText.cleanupTitle
            : '${widget.bookTitle} · ${CharactersPageText.cleanupTitle}'),
        actions: [
          IconButton(
            tooltip: '合并重复人物',
            icon: const Icon(Icons.merge_type),
            onPressed: _cards.isEmpty ? null : _mergeDuplicates,
          ),
          TextButton(
            onPressed: _cards.isEmpty
                ? null
                : () => setState(() {
                      if (_selected.length == _cards.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(_cards.map((e) => e.name));
                      }
                    }),
            child: Text(_selected.length == _cards.length && _cards.isNotEmpty
                ? '取消全选'
                : '全选'),
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingHint()
          : _cards.isEmpty
              ? EmptyStateHint(
                  icon: Icons.cleaning_services_outlined,
                  title: CharactersPageText.cleanupTitle,
                  subtitle: '这本书还没有人物数据。\n先做一次人物蒸馏，再回来挑选。',
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      color: c.frost,
                      child: Text(
                        '共 ${_cards.length} 个角色：主要 $majorCount · 次要 $minorCount\n'
                        '勾掉不要的（次要角色通常是只出场一两次的龙套）',
                        style: SjText.meta(c.inkSoft),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => _selectWhere(
                              (e) => e.importance < kMajorImportance,
                              select: true,
                            ),
                            child: const Text('选中全部次要角色'),
                          ),
                          TextButton(
                            onPressed: () => _selectWhere(
                              (e) => e.importance >= kMajorImportance,
                              select: true,
                            ),
                            child: const Text('选中全部主要角色'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _cards.length,
                        itemBuilder: (context, i) {
                          final card = _cards[i];
                          final checked = _selected.contains(card.name);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(card.name);
                              } else {
                                _selected.remove(card.name);
                              }
                            }),
                            title: Text(card.name, style: SjText.cardTitle(c.ink)),
                            subtitle: Text(
                              [
                                if (card.role != null && card.role!.isNotEmpty)
                                  card.role!,
                                '重要度 ${card.importance}',
                              ].join(' · '),
                              style: SjText.meta(c.inkSoft),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _loading || _cards.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    _selected.isEmpty ? '删除选中角色' : '删除选中的 ${_selected.length} 个角色',
                  ),
                ),
              ),
            ),
    );
  }
}
