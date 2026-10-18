import 'package:flutter/material.dart';

import 'package:songjiang_reader/dao/scene_card_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/models/scene_card.dart';

/// 一次开局的选择结果。
class SessionSetup {
  const SessionSetup({
    required this.participation,
    required this.characters,
    this.userPersona,
    this.scenePremise,
  });

  /// 读者姿态：旁观 / 扮演 / 入场。
  final CharacterParticipation participation;

  /// 出场人物（≥1）。选 1 位是单人局，选多位是群聊。
  final List<CharacterCard> characters;

  /// 读者身份。扮演时为所代入的书中人物名；入场时为自定义名字；旁观时为 null。
  final String? userPersona;

  /// 选中的场景情境（未选场景时为 null，由调用方决定用什么开场）。
  final String? scenePremise;
}

/// 弹出「开局设置」：选姿态 → 填身份 → 挑场景 → 勾出场人物。
///
/// 为什么不继续用「选一个人物」的列表：造梦的开局是三件事一起定的
/// （书卷 / 你的身份 / 出场人物），只让人选人物，等于把
/// 「你是旁观、还是扮演其中一位」这层完全丢掉——而它恰恰决定了对话的样子。
Future<SessionSetup?> showSessionSetupSheet(
  BuildContext context, {
  required int bookId,
  required List<CharacterCard> cards,
  String? title,
}) {
  return showModalBottomSheet<SessionSetup>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SessionSetupSheet(
      bookId: bookId,
      cards: cards,
      title: title,
    ),
  );
}

class _SessionSetupSheet extends StatefulWidget {
  const _SessionSetupSheet({
    required this.bookId,
    required this.cards,
    this.title,
  });

  final int bookId;
  final List<CharacterCard> cards;
  final String? title;

  @override
  State<_SessionSetupSheet> createState() => _SessionSetupSheetState();
}

class _SessionSetupSheetState extends State<_SessionSetupSheet> {
  CharacterParticipation _participation = CharacterParticipation.spectator;
  final Set<String> _onStage = <String>{};
  String? _roleplayAs;
  final TextEditingController _joinName = TextEditingController();

  List<SceneCard> _scenes = const [];
  SceneCard? _scene;

  @override
  void initState() {
    super.initState();
    _loadScenes();
  }

  @override
  @override
  void dispose() {
    _joinName.dispose();
    super.dispose();
  }

  /// 读场景卡。测试环境没有数据库，失败时退化为「没有场景」而不是崩掉。
  Future<void> _loadScenes() async {
    try {
      final list = await sceneCardDao.listForBook(widget.bookId);
      if (!mounted) return;
      setState(() => _scenes = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _scenes = const []);
    }
  }

  /// 姿态说明：一句话讲清「这一局你在哪」。
  String get _hint => switch (_participation) {
        CharacterParticipation.spectator => '你不发言，看着他们自己把戏演下去',
        CharacterParticipation.roleplay => '你进去演其中一位，人物会把你当作他/她本人',
        CharacterParticipation.join => '你以自己的身份闯入，人物会对你好奇或戒备',
      };

  bool get _canStart {
    if (_onStage.isEmpty) return false;
    if (_participation == CharacterParticipation.roleplay) {
      return _roleplayAs != null && _roleplayAs!.isNotEmpty;
    }
    if (_participation == CharacterParticipation.join) {
      return _joinName.text.trim().isNotEmpty;
    }
    return true;
  }

  String? get _persona => switch (_participation) {
        CharacterParticipation.spectator => null,
        CharacterParticipation.roleplay => _roleplayAs,
        CharacterParticipation.join => _joinName.text.trim(),
      };

  Future<void> _createScene() async {
    final drafted = await showDialog<SceneCard>(
      context: context,
      builder: (_) => const _SceneEditorDialog(),
    );
    if (drafted == null || !mounted) return;
    try {
      final id = await sceneCardDao.create(
        name: drafted.name,
        premise: drafted.premise,
        bookId: widget.bookId,
      );
      await _loadScenes();
      if (!mounted) return;
      setState(() {
        for (final s in _scenes) {
          if (s.id == id) _scene = s;
        }
      });
    } catch (_) {
      // 落库失败不应阻断开局，至少让刚填的场景本次可用
      if (!mounted) return;
      setState(() => _scene = drafted);
    }
  }

  /// 管理场景卡：改名、改情境、删除。
  Future<void> _manageScenes() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('管理场景'),
            content: SizedBox(
              width: 360,
              child: _scenes.isEmpty
                  ? const Text('还没有场景卡。')
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final s in _scenes)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(s.name),
                              subtitle: Text(
                                s.premise,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: '编辑',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20),
                                    onPressed: () async {
                                      final edited =
                                          await showDialog<SceneCard>(
                                        context: ctx,
                                        builder: (_) =>
                                            _SceneEditorDialog(initial: s),
                                      );
                                      if (edited == null || s.id == null) return;
                                      await sceneCardDao.updateScene(
                                        edited.copyWith(id: s.id),
                                      );
                                      await _loadScenes();
                                      if (mounted) setLocal(() {});
                                    },
                                  ),
                                  IconButton(
                                    tooltip: '删除',
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    onPressed: () async {
                                      if (s.id == null) return;
                                      await sceneCardDao.deleteScene(s.id!);
                                      if (_scene?.id == s.id) {
                                        setState(() => _scene = null);
                                      }
                                      await _loadScenes();
                                      if (mounted) setLocal(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _canStart;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                widget.title ?? '开局设置',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 4),
                  const Text('你在这一局的位置',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in CharacterParticipation.values)
                        ChoiceChip(
                          label: Text(p.label),
                          selected: _participation == p,
                          onSelected: (_) => setState(() {
                            _participation = p;
                            if (p == CharacterParticipation.roleplay &&
                                _roleplayAs == null &&
                                widget.cards.isNotEmpty) {
                              _roleplayAs = widget.cards.first.name;
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_hint,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),

                  // 身份：仅在需要时出现
                  if (_participation == CharacterParticipation.roleplay) ...[
                    const SizedBox(height: 14),
                    const Text('你扮演谁',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _roleplayAs,
                      items: [
                        for (final c in widget.cards)
                          DropdownMenuItem(value: c.name, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() => _roleplayAs = v),
                    ),
                  ],
                  if (_participation == CharacterParticipation.join) ...[
                    const SizedBox(height: 14),
                    const Text('你叫什么',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _joinName,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: '人物会这样称呼你',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],

                  // 场景（可跳过）——造梦里场景可以暂时不选
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('场景（可跳过）',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                      const Spacer(),
                      TextButton(
                        onPressed: _manageScenes,
                        child: const Text('管理'),
                      ),
                      TextButton(
                        onPressed: _createScene,
                        child: const Text('新建'),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<int?>(
                    key: ValueKey<int>(_scenes.length),
                    initialValue: _scene?.id,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('不选场景'),
                      ),
                      for (final s in _scenes)
                        DropdownMenuItem<int?>(
                          value: s.id,
                          child: Text(s.name),
                        ),
                    ],
                    onChanged: (id) => setState(() {
                      _scene = null;
                      for (final s in _scenes) {
                        if (s.id == id) _scene = s;
                      }
                    }),
                  ),
                  if (_scene != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _scene!.premise,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    '谁在场（已选 ${_onStage.length} 位）',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '选 1 位是单独对话；选多位则以群聊开局',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  for (final c in widget.cards)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _onStage.contains(c.name),
                      title: Text(c.name),
                      subtitle: (c.role != null && c.role!.isNotEmpty)
                          ? Text(c.role!)
                          : null,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _onStage.add(c.name);
                        } else {
                          _onStage.remove(c.name);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      canStart ? '' : '选好人物后才能开始',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  FilledButton(
                    onPressed: canStart
                        ? () => Navigator.pop(
                              context,
                              SessionSetup(
                                participation: _participation,
                                userPersona: _persona,
                                scenePremise: _scene?.premise,
                                characters: widget.cards
                                    .where((c) => _onStage.contains(c.name))
                                    .toList(),
                              ),
                            )
                        : null,
                    child: const Text('开始'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建场景卡：名字 + 情境。
class _SceneEditorDialog extends StatefulWidget {
  const _SceneEditorDialog({this.initial});
  final SceneCard? initial;

  @override
  State<_SceneEditorDialog> createState() => _SceneEditorDialogState();
}

class _SceneEditorDialogState extends State<_SceneEditorDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _premise = TextEditingController();

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _name.text = init.name;
      _premise.text = init.premise;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _premise.dispose();
    super.dispose();
  }

  bool get _ok => _name.text.trim().isNotEmpty && _premise.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AlertDialog(
      title: Text(widget.initial == null ? '新建场景' : '编辑场景'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '场景名',
              hintText: '例如：雨夜书房',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _premise,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '情境',
              hintText: '人物此刻在哪儿、心里装着什么事？',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _ok
              ? () => Navigator.pop(
                    context,
                    SceneCard(
                      name: _name.text.trim(),
                      premise: _premise.text.trim(),
                      createdAt: now,
                      updatedAt: now,
                    ),
                  )
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
