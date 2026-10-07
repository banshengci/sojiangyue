// lib/page/character/crossover_page.dart
//
// 穿越联动：让不同书的人物同场对话。
//
// 造梦 feature/crossover 的玩法——把两本（或多本）不相干的书里的角色凑到一张
// 桌上，看他们怎么互相打量。实现上不做新数据通道：场景只记「谁在场」，
// 对话复用群聊 prompt，成员的 (bookId, 姓名) 编码进会话的 characterName
// （见 CharacterChatService.encodeMemberRefs）。

import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/character_chat_dao.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/dao/character_extras_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/models/character_extras.dart';
import 'package:songjiang_reader/service/character/character_chat_service.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'character_chat_page.dart';
import 'characters_page_strings.dart';

class CrossoverPage extends StatefulWidget {
  const CrossoverPage({super.key});

  @override
  State<CrossoverPage> createState() => _CrossoverPageState();
}

class _CrossoverPageState extends State<CrossoverPage> {
  List<CrossoverScene> _scenes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final scenes = await characterExtrasDao.listCrossoverScenes();
    if (!mounted) return;
    setState(() {
      _scenes = scenes;
      _loading = false;
    });
  }

  Future<void> _edit([CrossoverScene? scene]) async {
    final result = await showDialog<CrossoverScene>(
      context: context,
      builder: (_) => _SceneEditorDialog(scene: scene),
    );
    if (result == null) return;
    await characterExtrasDao.saveCrossoverScene(result);
    if (mounted) SjToast.show('已保存');
    await _reload();
  }

  Future<void> _delete(CrossoverScene scene) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这个场景？'),
        content: Text(scene.name),
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
    if (ok != true || scene.id == null) return;
    await characterExtrasDao.deleteCrossoverScene(scene.id!);
    await _reload();
  }

  /// 进入群聊：用场景成员建一个群聊会话。
  Future<void> _enter(CrossoverScene scene) async {
    if (scene.members.isEmpty) {
      SjToast.show('这个场景还没有人物');
      return;
    }
    final refs = scene.members
        .map((m) => (bookId: m.bookId, name: m.characterName))
        .toList();
    final id = await characterChatDao.createSession(
      bookId: refs.first.bookId,
      characterName: CharacterChatService.encodeMemberRefs(refs),
      mode: CharacterChatMode.group,
      title: scene.name,
    );
    final session = await characterChatDao.getSession(id);
    if (!mounted || session == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterChatPage(
          session: session,
          titleOverride: scene.name,
          bookTitle: scene.members.map((m) => m.characterName).join(' × '),
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('穿越联动')),
      body: _loading
          ? const AppLoadingHint()
          : _scenes.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateHint(
                      icon: Icons.swap_horiz,
                      title: '穿越联动',
                      subtitle: '把不同书里的人物凑到一张桌上，'
                          '看他们怎么互相打量。\n先新建一个场景，挑几位出场人物。',
                      action: FilledButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add),
                        label: const Text('新建场景'),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _scenes.length,
                  itemBuilder: (context, i) {
                    final s = _scenes[i];
                    return Card(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: c.frost,
                          child: Icon(Icons.swap_horiz, size: 18, color: c.ink),
                        ),
                        title: Text(s.name, style: SjText.cardTitle(c.ink)),
                        subtitle: Text(
                          s.members.map((m) => m.label).join('  ×  '),
                          style: SjText.meta(c.inkSoft),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: s.members.length > 2,
                        onTap: () => _enter(s),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _edit(s);
                            } else {
                              _delete(s);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _scenes.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _edit(),
              tooltip: '新建场景',
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// 场景编辑器：场景名 + 跨书成员列表。
class _SceneEditorDialog extends StatefulWidget {
  const _SceneEditorDialog({this.scene});

  final CrossoverScene? scene;

  @override
  State<_SceneEditorDialog> createState() => _SceneEditorDialogState();
}

class _SceneEditorDialogState extends State<_SceneEditorDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.scene?.name ?? '');
  late final TextEditingController _noteController =
      TextEditingController(text: widget.scene?.note ?? '');
  late final List<CrossoverMember> _members = [
    ...?widget.scene?.members,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final books = await bookDao.selectNotDeleteBooks();
    if (!mounted) return;
    if (books.isEmpty) {
      SjToast.show('书架里还没有书');
      return;
    }
    final book = await showModalBottomSheet<Book>(
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
                child: Text('选择一本书', style: SjText.sectionTitle(c.ink)),
              ),
              for (final b in books)
                ListTile(
                  title: Text(b.title, style: SjText.cardTitle(c.ink)),
                  onTap: () => Navigator.pop(ctx, b),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (book == null || !mounted) return;

    final cards = await characterDao.getCharacters(book.id);
    if (!mounted) return;
    if (cards.isEmpty) {
      SjToast.show('《${book.title}》还没有人物数据，先做一次蒸馏');
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
                child: Text('选择出场人物', style: SjText.sectionTitle(c.ink)),
              ),
              for (final card in cards)
                ListTile(
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

    final exists = _members.any(
      (m) => m.bookId == book.id && m.characterName == picked.name,
    );
    if (exists) {
      SjToast.show('${picked.name} 已经在场上了');
      return;
    }
    setState(() {
      _members.add(CrossoverMember(
        bookId: book.id,
        characterName: picked.name,
        bookTitle: book.title,
      ));
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      SjToast.show('给这个场景起个名字');
      return;
    }
    if (_members.isEmpty) {
      SjToast.show('至少加一位出场人物');
      return;
    }
    final now = DateTime.now();
    final scene = widget.scene;
    Navigator.pop(
      context,
      CrossoverScene(
        id: scene?.id,
        name: name,
        members: List.of(_members),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        createdAt: scene?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return AlertDialog(
      title: Text(widget.scene == null ? '新建穿越场景' : '编辑场景'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '场景名',
                  hintText: '例如：大观园夜宴',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '场景说明（可选）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('在场人物', style: SjText.sectionTitle(c.ink)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('加人物'),
                    onPressed: _addMember,
                  ),
                ],
              ),
              if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('还没有人', style: SjText.meta(c.inkSoft)),
                )
              else
                for (var i = 0; i < _members.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _members[i].label,
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _members.removeAt(i)),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(CharactersPageText.chatCancel),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
