import 'package:flutter/material.dart';

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';

/// 一次开局的选择结果。
class SessionSetup {
  const SessionSetup({
    required this.participation,
    required this.characters,
    this.userPersona,
  });

  /// 读者姿态：旁观 / 扮演 / 入场。
  final CharacterParticipation participation;

  /// 出场人物（≥1）。选 1 位是单人局，选多位是群聊。
  final List<CharacterCard> characters;

  /// 读者身份。扮演时为所代入的书中人物名；入场时为自定义名字；旁观时为 null。
  final String? userPersona;
}

/// 弹出「开局设置」：选姿态 → 填身份 → 勾出场人物。
///
/// 为什么要单独一屏而不是继续用「选一个人物」的列表：
/// 造梦的开局是三件事一起定的（书卷 / 你的身份 / 出场人物），
/// 只让人选人物，等于把「你是旁观、还是扮演其中一位」这层完全丢掉——
/// 而那一层恰恰决定了对话会是什么样子。
Future<SessionSetup?> showSessionSetupSheet(
  BuildContext context, {
  required List<CharacterCard> cards,
  String? title,
}) {
  return showModalBottomSheet<SessionSetup>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SessionSetupSheet(cards: cards, title: title),
  );
}

class _SessionSetupSheet extends StatefulWidget {
  const _SessionSetupSheet({required this.cards, this.title});

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

  @override
  void dispose() {
    _joinName.dispose();
    super.dispose();
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                                _roleplayAs == null) {
                              _roleplayAs = widget.cards.isEmpty
                                  ? null
                                  : widget.cards.first.name;
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
                      subtitle:
                          (c.role != null && c.role!.isNotEmpty)
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
