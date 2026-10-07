// lib/page/character/character_chat_page.dart
//
// 角色对话页：与某位书中人物聊天。
//
// 造梦的核心体验是「让书中人带着性格、关系与记忆重新开口」，本页即为该体验
// 在松江阅的落点：设定全部来自本地蒸馏产物，回复走流式，消息落库可回溯。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:songjiang_reader/dao/character_chat_dao.dart';
import 'package:songjiang_reader/dao/gameplay_dao.dart';
import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/service/character/character_chat_service.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'characters_page_strings.dart';

/// 与角色对话。
///
/// 传 [session] 进入已有会话；只传 [bookId] + [characterName] 时会自动建会话。
class CharacterChatPage extends StatefulWidget {
  const CharacterChatPage({
    super.key,
    this.session,
    this.bookId,
    this.characterName,
    this.bookTitle,
    this.mode = CharacterChatMode.single,
    this.opening,
    this.titleOverride,
    this.gameplayDirective,
    this.gameplayMode,
  });

  final CharacterChatSession? session;
  final int? bookId;
  final String? characterName;
  final String? bookTitle;
  final CharacterChatMode mode;

  /// 开局模板：一段起始情境，会作为额外设定注入角色，并在对话顶部留一条旁白。
  final String? opening;

  /// 覆盖标题（穿越场景直接用场景名）。
  final String? titleOverride;

  /// 玩法模式的规则外壳（如「规则怪谈」的规矩），会拼进角色的 system 设定。
  final String? gameplayDirective;

  /// 玩法模式（带状态/分幕/暗牌的完整玩法）。传入后本局会开启玩法运行时。
  final GameplayMode? gameplayMode;

  @override
  State<CharacterChatPage> createState() => _CharacterChatPageState();
}

class _CharacterChatPageState extends State<CharacterChatPage> {
  final _service = CharacterChatService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  CharacterChatSession? _session;
  List<CharacterChatMessage> _messages = [];

  /// 玩法运行时状态（仅当选了玩法模式时存在）。
  GameplaySession? _gameplay;
  bool _gameplayBusy = false;

  /// 原始流式文本（含状态块）；展示时剥离，结算时解析。
  String _streamingRaw = '';
  String _streaming = '';
  bool _loading = true;
  bool _sending = false;
  bool _greeting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 玩法规则与开局情境合并后的额外设定。
  String? get _extraDirective {
    final parts = <String>[
      if (widget.gameplayMode != null && _gameplay != null)
        GameplayRuntime.buildDirective(
            mode: widget.gameplayMode!, session: _gameplay!),
      if (widget.gameplayDirective?.trim().isNotEmpty ?? false)
        widget.gameplayDirective!.trim(),
      if (widget.opening?.trim().isNotEmpty ?? false)
        '当前情境：${widget.opening!.trim()}',
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      var session = widget.session;
      if (session == null) {
        final bookId = widget.bookId;
        final name = widget.characterName;
        if (bookId == null || name == null) {
          throw StateError('缺少会话信息');
        }
        final id = await characterChatDao.createSession(
          bookId: bookId,
          characterName: name,
          mode: widget.mode,
        );
        session = await characterChatDao.getSession(id);
      }
      if (session == null) throw StateError('会话创建失败');

      final messages = await characterChatDao.listMessages(session.id!);
      if (!mounted) return;
      setState(() {
        _session = session;
        _messages = messages;
        _loading = false;
      });

      // 新会话：先把开局情境记为一条旁白，再让角色开口
      if (messages.isEmpty && widget.opening != null &&
          widget.opening!.trim().isNotEmpty) {
        await characterChatDao.appendMessage(
          sessionId: session.id!,
          role: CharacterChatRole.narrator,
          content: widget.opening!.trim(),
        );
        final refreshed = await characterChatDao.listMessages(session.id!);
        if (!mounted) return;
        setState(() => _messages = refreshed);
      }
      await _initGameplay(session);

      if (_messages.isEmpty) await _generateGreeting();
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 初始化玩法运行时：加载或新建本局状态，需要暗牌则先生成。
  Future<void> _initGameplay(CharacterChatSession session) async {
    final mode = widget.gameplayMode;
    if (mode == null) return;

    final existing = await gameplayDao.getByChatSession(session.id!);
    if (existing != null) {
      if (!mounted) return;
      setState(() => _gameplay = existing);
      return;
    }

    var fresh = GameplaySession(
      chatSessionId: session.id!,
      modeId: mode.id,
      stats: {for (final d in mode.stats) d.key: d.initial},
    );
    fresh = fresh.copyWith(id: await gameplayDao.save(fresh));
    if (!mounted) return;
    setState(() => _gameplay = fresh);

    // 玩法有暗牌（剧本杀真相 / 海龟汤汤底）时，开局先让模型写出来
    if (mode.setupPrompt != null) await _setupSecret();
  }

  /// 生成暗牌。
  Future<void> _setupSecret() async {
    final mode = widget.gameplayMode;
    if (mode == null || mode.setupPrompt == null) return;
    if ((_gameplay?.secret?.isNotEmpty ?? false)) return;

    setState(() => _gameplayBusy = true);
    try {
      final secret = await _service.generateGameplaySecret(
        mode: mode,
        characterName:
            _session?.characterName ?? widget.characterName ?? '主角',
        bookTitle: widget.bookTitle,
        scene: widget.opening,
      );
      _gameplay = _gameplay!.copyWith(secret: secret);
      await gameplayDao.save(_gameplay!);
      if (mounted) setState(() {});
    } catch (e) {
      SjLog.warning('Gameplay: 生成开局设定失败: $e');
      if (mounted) SjToast.show('开局设定生成失败：$e');
    } finally {
      if (mounted) setState(() => _gameplayBusy = false);
    }
  }

  /// 揭晓暗牌（对局后的复盘）。
  Future<void> _revealSecret() async {
    final secret = _gameplay?.secret;
    if (secret == null || secret.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = SjColors.of(ctx);
        return AlertDialog(
          title: Text(widget.gameplayMode?.secretLabel ?? '揭晓真相'),
          content: SingleChildScrollView(
            child: Text(secret, style: SjText.body(c.ink)),
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
    if (!mounted) return;
    _gameplay = _gameplay!.copyWith(revealed: true);
    await gameplayDao.save(_gameplay!);
    setState(() {});
  }

  /// 结算本回合：把状态变化累加进本局。
  Future<void> _applyGameplayTurn(GameplayTurn turn) async {
    final mode = widget.gameplayMode;
    final session = _gameplay;
    if (mode == null || session == null) return;
    if (!turn.hasChanges && !turn.ended && turn.note == null) return;
    _gameplay = GameplayRuntime.apply(
      mode: mode,
      session: session,
      turn: turn,
    );
    await gameplayDao.save(_gameplay!);
    if (mounted) setState(() {});
  }

  Future<void> _generateGreeting() async {
    final session = _session;
    if (session == null) return;
    setState(() => _greeting = true);
    try {
      final text = await _service.greeting(session);
      if (text.isEmpty) return;
      final id = await _service.saveCharacterMessage(
        session.id!,
        session.characterName,
        text,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.character,
            speaker: session.characterName,
            content: text,
            createdAt: DateTime.now(),
          ),
        ];
      });
    } catch (e) {
      // 开场白失败不阻断：用户仍可主动发问
      SjLog.warning('CharacterChat: 角色开场白生成失败: $e');
    } finally {
      if (mounted) setState(() => _greeting = false);
    }
  }

  Future<void> _send() async {
    final session = _session;
    final text = _inputController.text.trim();
    if (session == null || text.isEmpty || _sending) return;

    final history = List<CharacterChatMessage>.from(_messages);
    final isFirstRound = history.isEmpty;

    setState(() {
      _sending = true;
      _error = null;
      _streaming = '';
      _messages = [
        ..._messages,
        CharacterChatMessage(
          sessionId: session.id!,
          role: CharacterChatRole.user,
          content: text,
          createdAt: DateTime.now(),
        ),
      ];
    });
    _inputController.clear();
    _scrollToEnd();

    await _service.saveUserMessage(session.id!, text);

    try {
      await for (final chunk in _service.reply(
        session: session,
        history: history,
        input: text,
        extraDirective: _extraDirective,
      )) {
        if (!mounted) return;
        _streamingRaw = chunk;
        // 状态块是给程序读的，展示时先剥掉
        setState(() => _streaming = GameplayRuntime.parse(chunk).displayText);
        _scrollToEnd();
      }

      // 从原始文本里解析状态块，正文用于展示与落库
      final turn = GameplayRuntime.parse(_streamingRaw);
      final reply = turn.displayText;
      if (reply.isEmpty) {
        throw StateError('模型没有返回内容');
      }
      final id = await _service.saveCharacterMessage(
        session.id!,
        session.characterName,
        reply,
      );
      await _service.touch(session.id!);
      await _applyGameplayTurn(turn);
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.character,
            speaker: session.characterName,
            content: reply,
            createdAt: DateTime.now(),
          ),
        ];
        _streaming = '';
      });

      // 首轮对话后自动生成会话标题（失败也不影响使用）
      if (isFirstRound && (session.title == null || session.title!.isEmpty)) {
        final title = await _service.generateTitle(
          session: session,
          firstUserMessage: text,
          firstReply: reply,
        );
        if (title != null && mounted) {
          await characterChatDao.updateSessionTitle(session.id!, title);
          setState(() => _session = session.copyWith(title: title));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _streaming = '';
        });
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// 重新生成：撤掉最后一条角色发言，用同样的历史再要一次。
  ///
  /// 这是「分支」最轻的形态——保留读者说过的话，只换 TA 的回答。
  Future<void> _regenerate() async {
    final session = _session;
    if (session == null || _sending) return;

    // 以最近一条读者发言为这一轮的锚点：它之后的内容全部撤掉重来。
    // 同时覆盖两种情形——「换个说法」，以及「上一轮生成失败后重试」。
    var userIndex = -1;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == CharacterChatRole.user) {
        userIndex = i;
        break;
      }
    }
    if (userIndex < 0) {
      SjToast.show('还没有可以重新生成的回答');
      return;
    }

    final prompt = _messages[userIndex].content;
    final toDelete = _messages
        .sublist(userIndex + 1)
        .where((m) => m.id != null)
        .toList();
    final history = _messages.sublist(0, userIndex);

    setState(() {
      _sending = true;
      _error = null;
      _streaming = '';
      _messages = history;
    });

    try {
      for (final m in toDelete) {
        await characterChatDao.deleteMessage(m.id!);
      }

      await for (final chunk in _service.reply(
        session: session,
        history: history,
        input: prompt,
        extraDirective: _extraDirective,
      )) {
        if (!mounted) return;
        _streamingRaw = chunk;
        // 状态块是给程序读的，展示时先剥掉
        setState(() => _streaming = GameplayRuntime.parse(chunk).displayText);
        _scrollToEnd();
      }

      // 从原始文本里解析状态块，正文用于展示与落库
      final turn = GameplayRuntime.parse(_streamingRaw);
      final reply = turn.displayText;
      if (reply.isEmpty) throw StateError('模型没有返回内容');
      final id = await _service.saveCharacterMessage(
          session.id!, session.characterName, reply);
      await _service.touch(session.id!);
      await _applyGameplayTurn(turn);
      if (!mounted) return;
      setState(() {
        _messages = [
          ...history,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.character,
            speaker: session.characterName,
            content: reply,
            createdAt: DateTime.now(),
          ),
        ];
        _streaming = '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _streaming = '';
        });
      }
    }
  }

  /// 读心：生成一条旁白，写出角色此刻没说出口的念头。
  Future<void> _readMind() async {
    final session = _session;
    if (session == null || _sending) return;
    if (_messages.isEmpty) {
      SjToast.show('先聊两句再读心');
      return;
    }
    setState(() => _sending = true);
    try {
      final text = await _service.readMind(
        session: session,
        history: _messages,
      );
      final id = await characterChatDao.appendMessage(
        sessionId: session.id!,
        role: CharacterChatRole.narrator,
        content: '（${session.characterName} 心里）$text',
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.narrator,
            content: '（${session.characterName} 心里）$text',
            createdAt: DateTime.now(),
          ),
        ];
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 长按气泡：复制 / 重新生成 / 读心。
  Future<void> _onBubbleLongPress(CharacterChatMessage m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制这段话'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            if (m.role == CharacterChatRole.character) ...[
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('换个说法（重新生成）'),
                onTap: () => Navigator.pop(ctx, 'regenerate'),
              ),
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('读心（TA 此刻在想什么）'),
                onTap: () => Navigator.pop(ctx, 'mind'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.content));
        if (mounted) SjToast.show('已复制');
      case 'regenerate':
        await _regenerate();
      case 'mind':
        await _readMind();
    }
  }

  Future<void> _clear() async {
    final session = _session;
    if (session == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(CharactersPageText.chatClear),
        content: const Text(CharactersPageText.chatClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CharactersPageText.chatCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(CharactersPageText.chatClear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await characterChatDao.clearMessages(session.id!);
    if (!mounted) return;
    setState(() => _messages = []);
    await _generateGreeting();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final session = _session;
    final title = widget.titleOverride ??
        session?.characterName ??
        widget.characterName ??
        CharactersPageText.chatTitle;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (widget.bookTitle != null)
              Text(
                widget.bookTitle!,
                style: SjText.meta(c.inkSoft),
              ),
          ],
        ),
        bottom: (widget.gameplayMode != null && _gameplay != null)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: _buildGameplayBar(c),
              )
            : null,
        actions: [
          IconButton(
            tooltip: '读心',
            icon: const Icon(Icons.psychology_outlined),
            onPressed: (_sending || _messages.isEmpty) ? null : _readMind,
          ),
          IconButton(
            tooltip: CharactersPageText.chatClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _messages.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingHint()
          : Column(
              children: [
                if (_error != null) _buildErrorBar(c),
                Expanded(
                  child: _messages.isEmpty && !_greeting
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              CharactersPageText.chatInputHint,
                              style: SjText.meta(c.inkSoft),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          itemCount: _messages.length + (_streaming.isEmpty ? 0 : 1),
                          itemBuilder: (context, i) {
                            if (i >= _messages.length) {
                              return _Bubble(
                                text: _streaming,
                                isUser: false,
                                speaker: title,
                                streaming: true,
                              );
                            }
                            final m = _messages[i];
                            if (m.role == CharacterChatRole.narrator) {
                              return _NarratorLine(text: m.content);
                            }
                            return GestureDetector(
                              onLongPress: () => _onBubbleLongPress(m),
                              child: _Bubble(
                                text: m.content,
                                isUser: m.role == CharacterChatRole.user,
                                speaker: m.speaker,
                              ),
                            );
                          },
                        ),
                ),
                if (_greeting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      CharactersPageText.chatGreeting,
                      style: SjText.meta(c.inkSoft),
                    ),
                  ),
                _buildInputBar(c),
              ],
            ),
    );
  }

  /// 玩法状态条：玩法名 · 进度幕 · 各状态量 · 揭晓入口。
  Widget _buildGameplayBar(SjColors c) {
    final mode = widget.gameplayMode!;
    final state = _gameplay!;
    final phase = mode.phases.isEmpty
        ? null
        : mode.phases[state.phaseIndex.clamp(0, mode.phases.length - 1)];

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(mode.icon, size: 13, color: c.river),
            const SizedBox(width: 6),
            Text(mode.name, style: SjText.meta(c.ink)),
            if (_gameplayBusy) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ],
            if (phase != null) ...[
              const SizedBox(width: 10),
              Text('第 ${state.phaseIndex + 1}/${mode.phases.length} 幕 · $phase',
                  style: SjText.meta(c.inkSoft)),
            ],
            for (final def in mode.stats) ...[
              const SizedBox(width: 12),
              Text('${def.name} ${state.stats[def.key] ?? def.initial}',
                  style: SjText.meta(def.isScore ? c.clay : c.inkSoft)),
            ],
            if ((state.secret?.isNotEmpty ?? false) && !state.revealed) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _revealSecret,
                child: Text('揭晓${mode.secretLabel ?? '真相'}',
                    style: SjText.meta(c.pine)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBar(SjColors c) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: c.clay.withValues(alpha: 0.12),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: c.clay),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: SjText.meta(c.ink),
              ),
            ),
            if (!_sending)
              TextButton(
                onPressed: _regenerate,
                child: const Text('重试'),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => setState(() => _error = null),
            ),
          ],
        ),
      );

  Widget _buildInputBar(SjColors c) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                enabled: !_sending,
                decoration: InputDecoration(
                  hintText: CharactersPageText.chatInputHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? SizedBox(
                    width: 44,
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.pine),
                    ),
                  )
                : IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    tooltip: CharactersPageText.chatSend,
                  ),
          ],
        ),
      ),
    );
  }
}

/// 旁白行（开局情境等）：居中、斜体、不占气泡。
class _NarratorLine extends StatelessWidget {
  const _NarratorLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: SjText.meta(c.inkSoft).copyWith(
          fontStyle: FontStyle.italic,
          height: 1.6,
        ),
      ),
    );
  }
}

/// 消息气泡：读者在右，书中人在左。
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.isUser,
    this.speaker,
    this.streaming = false,
  });

  final String text;
  final bool isUser;
  final String? speaker;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final bg = isUser ? c.pine : c.card;
    final fg = isUser ? c.onPine : c.ink;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 2),
            bottomRight: Radius.circular(isUser ? 2 : 12),
          ),
          border: isUser
              ? null
              : Border.all(color: c.cardBorder, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser && speaker != null && speaker!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  speaker!,
                  style: SjText.meta(c.river),
                ),
              ),
            Text(
              text.isEmpty && streaming ? CharactersPageText.chatThinking : text,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
