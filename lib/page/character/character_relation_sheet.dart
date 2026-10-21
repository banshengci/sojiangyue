// lib/page/character/character_relation_sheet.dart
//
// 玩法里的「关系」面板：谁对谁什么态度。
//
// 提示词里已经有一份「各怀心思」，但那只给模型看。玩家只能从台词里猜，
// 猜不到就会觉得人物莫名其妙——猜得到才叫有戏。
//
// 所以这里只展示**能观察到的部分**：明面态度、心里的分量、心结，
// 以及本局玩法自己算出来的好感/信任。
// hiddenAttitude（表里不一）不展示：那是留给玩家去发现的。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_relation_merge.dart';
import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/character/relation_playbook.dart';

/// 打开关系面板。
Future<void> showCharacterRelationSheet(
  BuildContext context, {
  required int bookId,
  required List<String> members,
  GameplayMode? mode,
  GameplaySession? state,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RelationSheet(
      bookId: bookId,
      members: members,
      mode: mode,
      state: state,
    ),
  );
}

class _RelationSheet extends StatefulWidget {
  const _RelationSheet({
    required this.bookId,
    required this.members,
    this.mode,
    this.state,
  });

  final int bookId;
  final List<String> members;
  final GameplayMode? mode;
  final GameplaySession? state;

  @override
  State<_RelationSheet> createState() => _RelationSheetState();
}

class _RelationSheetState extends State<_RelationSheet> {
  List<CharacterRelation> _relations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await characterDao.getRelations(widget.bookId);
    final cast = <String>{
      for (final m in widget.members) canonicalPersonName(m),
    };
    if (!mounted) return;
    setState(() {
      // 只留两端都在场的：场外的人接不住这局的话
      _relations = [
        for (final r in all)
          if (cast.contains(canonicalPersonName(r.sourceName)) &&
              cast.contains(canonicalPersonName(r.targetName)))
            r,
      ];
      _loading = false;
    });
  }

  /// 本局按人记的状态量（好感 / 信任）。
  List<(String, int)> _liveStats(String other) {
    final mode = widget.mode;
    final state = widget.state;
    if (mode == null || state == null) return const [];
    final out = <(String, int)>[];
    for (final def in mode.stats) {
      if (!def.perMember) continue;
      final v = state.memberStats[def.key]?[other];
      if (v != null) out.add((def.name, v));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('关系',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    )),
                const SizedBox(height: 3),
                Text('明面上看得出来的态度。心里那层要自己猜。',
                    style: SjText.meta(c.inkSoft)),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _buildBody(c),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(SjColors c) {
    if (_relations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
        child: Text(
          '这几位之间还没有蒸馏出关系。\n'
          '在「人物」页跑一次人物蒸馏，关系面板才会有内容。',
          style: SjText.meta(c.inkSoft),
        ),
      );
    }

    final blocks = <Widget>[];
    for (final m in widget.members) {
      final self = canonicalPersonName(m);
      final rows = <Widget>[];
      final seen = <String>{};

      for (final r in _relations) {
        final s = canonicalPersonName(r.sourceName);
        final t = canonicalPersonName(r.targetName);
        if (s != self) continue;
        if (!seen.add(t)) continue;

        final stance = describeRelationStance(r, outgoing: true);
        final live = _liveStats(t);
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(t, style: TextStyle(fontSize: 13, color: c.ink)),
                  if ((r.relationType ?? '').isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.pine.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        r.relationType!,
                        style: SjText.meta(c.pine).copyWith(fontSize: 10),
                      ),
                    ),
                  ],
                  if (live.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    for (final (name, value) in live)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text('$name $value',
                            style: SjText.meta(c.clay).copyWith(fontSize: 10)),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(stance.surface,
                  style: SjText.meta(c.inkSoft).copyWith(height: 1.45)),
              Text('心里：${stance.inner}',
                  style: SjText.meta(c.inkSoft).copyWith(height: 1.45)),
              if ((r.conflictPoint ?? '').trim().isNotEmpty)
                Text('心结：${r.conflictPoint!.trim()}',
                    style: SjText.meta(c.river).copyWith(height: 1.45)),
            ],
          ),
        ));
      }

      if (rows.isEmpty) continue;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(m,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  )),
            ),
            ...rows,
          ],
        ),
      ));
    }

    if (blocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
        child: Text(
          '这几位之间的关系还没有方向性的记录。\n'
          '（蒸馏只抽到了别人对他们的态度，反过来没有）',
          style: SjText.meta(c.inkSoft),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: blocks,
    );
  }
}
