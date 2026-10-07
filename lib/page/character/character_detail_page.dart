import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'character_avatar.dart';
import 'character_chat_page.dart';
import 'character_edit_page.dart';
import 'characters_page_strings.dart';

/// 单人详情页：角色卡字段 + 其参与的人物关系。
class CharacterDetailPage extends StatefulWidget {
  const CharacterDetailPage({
    super.key,
    required this.bookId,
    required this.character,
  });

  final int bookId;
  final CharacterCard character;

  @override
  State<CharacterDetailPage> createState() => _CharacterDetailPageState();
}

class _CharacterDetailPageState extends State<CharacterDetailPage> {
  List<CharacterRelation> _relations = [];
  Map<String, CharacterCard> _byName = {};
  late CharacterCard _card = widget.character;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final relations = await characterDao.getRelationsForCharacter(
      widget.bookId,
      widget.character.name,
    );
    final cards = await characterDao.getCharacters(widget.bookId);
    if (!mounted) return;
    _byName = {for (final c in cards) c.name: c};
    setState(() {
      // 重新读一遍自己：编辑页保存后回来能立刻看到新资料
      _card = _byName[widget.character.name] ?? widget.character;
      _relations = relations;
      _loading = false;
    });
  }

  /// 校对资料（改字段 / 配头像 / AI 补全）。
  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterEditPage(
          bookId: widget.bookId,
          card: _card,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  void _openOther(String name) {
    final card = _byName[name];
    if (card == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterDetailPage(bookId: widget.bookId, character: card),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final card = _card;
    return Scaffold(
      appBar: AppBar(
        title: Text(card.name),
        actions: [
          IconButton(
            tooltip: CharactersPageText.editTitle,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _edit,
          ),
          IconButton(
            tooltip: CharactersPageText.chatTitle,
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CharacterChatPage(
                  bookId: widget.bookId,
                  characterName: card.name,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingHint()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 头像 + 姓名（配过头像的会显示图片）
                Center(
                  child: Column(
                    children: [
                      characterAvatar(card, c, radius: 40),
                      const SizedBox(height: 8),
                      Text(card.name, style: SjText.sectionTitle(c.ink)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 身份 / 重要度
                Row(
                  children: [
                    Expanded(
                      child: _Chip(
                        label: card.role ?? CharactersPageText.identity,
                        color: c.river,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Chip(
                      label:
                          '${CharactersPageText.importance} ${card.importance}',
                      color: c.clay,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (card.aliases != null && card.aliases!.isNotEmpty) ...[
                  _SectionTitle(CharactersPageText.aliases),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: card.aliases!
                        .map((a) => _Chip(label: a, color: c.inkSoft))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                if (card.description != null && card.description!.isNotEmpty) ...[
                  _SectionTitle(CharactersPageText.description),
                  Text(card.description!, style: SjText.body(c.ink)),
                  const SizedBox(height: 16),
                ],
                if (card.personality != null && card.personality!.isNotEmpty) ...[
                  _SectionTitle(CharactersPageText.personality),
                  Text(card.personality!, style: SjText.body(c.ink)),
                  const SizedBox(height: 16),
                ],
                if (card.motivation != null && card.motivation!.isNotEmpty) ...[
                  _SectionTitle(CharactersPageText.motivation),
                  Text(card.motivation!, style: SjText.body(c.ink)),
                  const SizedBox(height: 16),
                ],
                if (card.background != null && card.background!.isNotEmpty) ...[
                  _SectionTitle(CharactersPageText.backgroundTitle),
                  Text(card.background!, style: SjText.body(c.ink)),
                  const SizedBox(height: 16),
                ],
                if (card.appearance != null && card.appearance!.isNotEmpty) ...[
                  _SectionTitle(CharactersPageText.appearance),
                  Text(card.appearance!, style: SjText.body(c.ink)),
                  const SizedBox(height: 16),
                ],
                if (card.firstAppearanceChapter != null &&
                    card.firstAppearanceChapter!.isNotEmpty) ...[
                  _SectionTitle(CharactersPageText.firstAppearance),
                  Text(card.firstAppearanceChapter!, style: SjText.body(c.ink)),
                  const SizedBox(height: 16),
                ],

                _SectionTitle(CharactersPageText.relationshipTitle),
                if (_relations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(CharactersPageText.noRelation,
                        style: SjText.meta(c.inkSoft)),
                  )
                else
                  ..._relations.map((r) {
                    final other = r.sourceName == card.name
                        ? r.targetName
                        : r.sourceName;
                    final dir = r.sourceName == card.name
                        ? CharactersPageText.relationTo(other)
                        : '$other →';
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          CharactersPageText.relationType(r.relationType),
                          style: SjText.cardTitle(c.ink),
                        ),
                        subtitle: Text(dir, style: SjText.meta(c.inkSoft)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TrustBadge(
                                label: '信', value: r.trust, positive: c.river, negative: c.clay),
                            const SizedBox(width: 6),
                            _TrustBadge(
                                label: '情',
                                value: r.affection,
                                positive: c.river,
                                negative: c.clay),
                          ],
                        ),
                        onTap: () => _openOther(other),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: SjText.sectionTitle(c.ink)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(label, style: SjText.chip(c.ink)),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({
    required this.label,
    required this.value,
    required this.positive,
    required this.negative,
  });
  final String label;
  final int value;
  final Color positive;
  final Color negative;
  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final color = value >= 0 ? positive : negative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label$value', style: SjText.meta(c.inkSoft)),
    );
  }
}
