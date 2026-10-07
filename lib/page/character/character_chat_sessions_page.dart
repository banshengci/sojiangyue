// lib/page/character/character_chat_sessions_page.dart
//
// 角色对话的会话列表：搜索、多选删除、按人物新建对话。
//
// 对应造梦 feature/sessions 的会话管理能力（搜索 / 多选删除 / 自动标题）。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/character_chat_dao.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/dao/character_extras_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/models/character_extras.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'character_chat_page.dart';
import 'characters_page_strings.dart';

/// 某本书的全部角色对话会话。
class CharacterChatSessionsPage extends StatefulWidget {
  const CharacterChatSessionsPage({
    super.key,
    required this.bookId,
    this.bookTitle,
  });

  final int bookId;
  final String? bookTitle;

  @override
  State<CharacterChatSessionsPage> createState() =>
      _CharacterChatSessionsPageState();
}

class _CharacterChatSessionsPageState
    extends State<CharacterChatSessionsPage> {
  final _keywordController = TextEditingController();

  List<CharacterChatSession> _sessions = [];
  final Map<int, CharacterChatMessage?> _lastMessages = {};
  final Set<int> _selected = {};
  bool _loading = true;
  bool _selecting = false;
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
    final list = await characterChatDao.listSessions(
      widget.bookId,
      keyword: _keyword,
    );
    final lasts = <int, CharacterChatMessage?>{};
    for (final s in list) {
      lasts[s.id!] = await characterChatDao.lastMessage(s.id!);
    }
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _lastMessages
        ..clear()
        ..addAll(lasts);
      _loading = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(CharactersPageText.chatDeleteSelected),
        content: Text(CharactersPageText.chatDeletedCount(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CharactersPageText.chatCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(CharactersPageText.chatDeleteSelected),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await characterChatDao.deleteSessions(_selected.toList());
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    SjToast.show(CharactersPageText.chatDeletedCount(count));
    await _reload();
  }

  /// 选一位人物开始新对话。
  Future<void> _newChat() async {
    final cards = await characterDao.getCharacters(widget.bookId);
    if (!mounted) return;
    if (cards.isEmpty) {
      SjToast.show(CharactersPageText.chatNoCharacterData);
      return;
    }

    final picked = await showModalBottomSheet<CharacterCard>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final c = SjColors.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  CharactersPageText.chatPickCharacter,
                  style: SjText.sectionTitle(c.ink),
                ),
              ),
              for (final card in cards)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: c.frost,
                    child: Text(
                      card.name.isNotEmpty ? card.name[0] : '?',
                      style: TextStyle(color: c.ink),
                    ),
                  ),
                  title: Text(card.name, style: SjText.cardTitle(c.ink)),
                  subtitle: (card.role != null && card.role!.isNotEmpty)
                      ? Text(card.role!, style: SjText.meta(c.inkSoft))
                      : null,
                  onTap: () => Navigator.pop(ctx, card),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;

    // 可选：挑一个开局模板带入这次对话
    final opening = await _pickOpening();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterChatPage(
          bookId: widget.bookId,
          characterName: picked.name,
          bookTitle: widget.bookTitle,
          opening: opening,
        ),
      ),
    );
    await _reload();
  }

  /// 选开局模板；返回 null 表示不用模板。
  Future<String?> _pickOpening() async {
    final openings = await characterExtrasDao.listSelfCards(
      widget.bookId,
      kind: SelfCardKind.opening,
    );
    if (openings.isEmpty || !mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final c = SjColors.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '选一个开局情境（可跳过）',
                  style: SjText.sectionTitle(c.ink),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('不用模板'),
                onTap: () => Navigator.pop(ctx, null),
              ),
              for (final o in openings)
                ListTile(
                  leading: const Icon(Icons.theater_comedy_outlined),
                  title: Text(o.title, style: SjText.cardTitle(c.ink)),
                  subtitle: Text(
                    o.content,
                    style: SjText.meta(c.inkSoft),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(ctx, o.content),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _open(CharacterChatSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterChatPage(
          session: session,
          bookTitle: widget.bookTitle,
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(CharactersPageText.chatSessionsTitle),
        actions: [
          if (_selecting)
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _sessions.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(_sessions.map((s) => s.id!));
                }
              }),
              child: const Text(CharactersPageText.chatSelectAll),
            )
          else
            IconButton(
              tooltip: CharactersPageText.chatDeleteSelected,
              icon: const Icon(Icons.checklist_outlined),
              onPressed: _sessions.isEmpty
                  ? null
                  : () => setState(() => _selecting = true),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _keywordController,
              decoration: const InputDecoration(
                hintText: '搜索对话',
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
                : _sessions.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: EmptyStateHint(
                            icon: Icons.forum_outlined,
                            title: CharactersPageText.chatSessionsTitle,
                            subtitle: CharactersPageText.chatNoSessions,
                            action: FilledButton.icon(
                              onPressed: _newChat,
                              icon: const Icon(Icons.add_comment_outlined),
                              label: const Text(CharactersPageText.chatNew),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _sessions.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = _sessions[i];
                          final last = _lastMessages[s.id!];
                          final checked = _selected.contains(s.id);
                          return ListTile(
                            leading: _selecting
                                ? Checkbox(
                                    value: checked,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selected.add(s.id!);
                                      } else {
                                        _selected.remove(s.id);
                                      }
                                    }),
                                  )
                                : CircleAvatar(
                                    backgroundColor: c.frost,
                                    child: Text(
                                      s.characterName.isNotEmpty
                                          ? s.characterName[0]
                                          : '?',
                                      style: TextStyle(color: c.ink),
                                    ),
                                  ),
                            title: Text(
                              s.displayTitle,
                              style: SjText.cardTitle(c.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              last?.content ?? s.characterName,
                              style: SjText.meta(c.inkSoft),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _selecting
                                ? null
                                : const Icon(Icons.chevron_right),
                            onTap: _selecting
                                ? () => setState(() {
                                      if (checked) {
                                        _selected.remove(s.id);
                                      } else {
                                        _selected.add(s.id!);
                                      }
                                    })
                                : () => _open(s),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _selecting
          ? FloatingActionButton.extended(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              label: const Text(CharactersPageText.chatDeleteSelected),
            )
          : FloatingActionButton(
              onPressed: _newChat,
              tooltip: CharactersPageText.chatNew,
              child: const Icon(Icons.add_comment_outlined),
            ),
    );
  }
}
