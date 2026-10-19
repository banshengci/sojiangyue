import 'dart:async';
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
import 'package:songjiang_reader/plugin/plugin_npc_runner.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/service/character/chat_autoplay.dart';
import 'package:songjiang_reader/service/character/dialogue_review.dart';
import 'package:songjiang_reader/service/character/dialogue_suggestions.dart';
import 'package:songjiang_reader/service/character/director_action.dart';
import 'package:songjiang_reader/plugin/plugin_rule_runner.dart';

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

  /// 本轮由插件规则注入的指令（生成前算好，重新生成时复用同一份）。
  String? _ruleInstruction;

  /// 对话回合数（以角色发言计），规则里的 everyTurns 用它。
  int _turn = 0;

  /// 旁观模式的「继续演出」：置位后复用 _send 的流程，但不发用户消息。
  bool _advanceRequested = false;

  /// 本轮「继续演出」使用的导演指令（推进/放缓/冲突/视角/破第四面墙）。
  String? _advanceInstruction;

  /// 自动连播：开启后每轮结束自动再推进一幕，到上限或被打断即停。
  bool _autoPlay = false;
  int _autoTurns = 0;
  static const int _autoPlayLimit = 10;

  /// 最近一次用户输入（after_turn 规则要按关键词匹配）。
  String _lastUserInput = '';

  /// 本会话启用的增强规则（按会话开关，不是全局）。
  List<String> _sessionEnhancerRules = const [];

  /// 玩法运行时状态（仅当选了玩法模式时存在）。
  GameplaySession? _gameplay;
  bool _gameplayBusy = false;

  /// 原始流式文本（含状态块）；展示时剥离，结算时解析。
  String _streamingRaw = '';

  /// 本回合开始前的状态快照。
  /// 「重新生成」会重走同一回合，若直接再结算一次会把好感计两遍，
  /// 因此先把状态回滚到这一轮的起点再重新结算。
  Map<String, int>? _statsBeforeTurn;
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
          mode: widget.gameplayMode!,
          session: _gameplay!,
          // 群聊时告诉规则层有哪些人，好感/信任才能按人展示
          members: onStageNames(
            _session?.characterName ?? widget.characterName ?? '',
          ),
        ),
      if (widget.gameplayDirective?.trim().isNotEmpty ?? false)
        widget.gameplayDirective!.trim(),
      if (widget.opening?.trim().isNotEmpty ?? false)
        '当前情境：${widget.opening!.trim()}',
      // 本会话开启的增强规则（插件声明、用户按会话开关）
      ..._sessionEnhancerRules,

      if (_ruleInstruction != null && _ruleInstruction!.trim().isNotEmpty)
        _ruleInstruction!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  @override
  void dispose() {
    // 离开页面必须停连播：否则会在后台继续烧 token
    _autoPlay = false;
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
      // 回合数从已有消息里恢复：规则的 everyTurns 要跨越重启继续数
      _turn = messages
          .where((m) => m.role == CharacterChatRole.character)
          .length;

      // 会话级增强器：每个会话一份，阅读页 AI 用的是全局开关
      _sessionEnhancerRules =
          PluginRegistry.instance.enhancerRulesForSession(session.id!);
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
          characterName: () {
            // 群聊的 characterName 是 bookId:姓名 串，塞进提示词会显得莫名其妙
            final raw = _session?.characterName ??
                widget.characterName ??
                '主角';
            final names = onStageNames(raw);
            return names.isEmpty ? raw : names.join('、');
          }(),
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
      final spoken = _speakerOf(session, text);
      final id = await _service.saveCharacterMessage(
        session.id!,
        spoken.speaker,
        spoken.text,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.character,
            speaker: spoken.speaker,
            content: spoken.text,
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
    final advancing = _advanceRequested;
    // 推进时忽略输入框里的半截文字：那是用户没发出来的话，不该算进这一轮
    final text = advancing ? '' : _inputController.text.trim();
    if (session == null || _sending) return;
    // 旁观模式的「继续演出」没有用户发言，不能按空文本拦掉
    if (text.isEmpty && !advancing) return;

    final history = List<CharacterChatMessage>.from(_messages);
    final isFirstRound = history.isEmpty;
    _statsBeforeTurn =
        _gameplay == null ? null : Map<String, int>.from(_gameplay!.stats);

    setState(() {
      _sending = true;
      _error = null;
      _streaming = '';
      _streamingRaw = '';
      // 「继续演出」没有用户发言：不追加空气泡，否则历史里会出现一条空白
      if (!advancing) {
        _messages = [
          ..._messages,
          CharacterChatMessage(
            sessionId: session.id!,
            role: CharacterChatRole.user,
            content: text,
            createdAt: DateTime.now(),
          ),
        ];
      }
    });
    if (!advancing) {
      _inputController.clear();
      _scrollToEnd();
      // 必须落库：这一行曾经在重构里被误删，表现是「角色的话还在、读者的话没了」
      // ——界面上有气泡（内存里有），退出重进就查不到了。
      await _service.saveUserMessage(session.id!, text);
    }

    // 生成前：结算 before_generation 规则，指令并进本轮设定
    _ruleInstruction = null;
    _lastUserInput = text;
    try {
      final instructions = await PluginRuleRunner.instructionsFor(
        sessionId: session.id!,
        turn: _turn + 1,
        userInput: text,
      );
      if (instructions.isNotEmpty) {
        _ruleInstruction = instructions.join('\n');
      }
    } catch (_) {
      // 规则失败不阻断发送
    }

    try {
      await for (final chunk in _service.reply(
        session: session,
        history: history,
        input: text,
        continueScene: advancing,
        continueInstruction: _advanceInstruction,
        extraDirective: _extraDirective,
      )) {
        if (!mounted) return;
        _streamingRaw = chunk;
        // 状态块是给程序读的，展示时先剥掉
        setState(() => _streaming =
            GameplayRuntime.parse(chunk, streaming: true).displayText);
        _scrollToEnd();
      }

      // 从原始文本里解析状态块，正文用于展示与落库
      final turn = GameplayRuntime.parse(_streamingRaw);
      final reply = turn.displayText;
      if (reply.isEmpty) {
        throw StateError('模型没有返回内容');
      }
      final spoken = _speakerOf(session, reply);
      final id = await _service.saveCharacterMessage(
        session.id!,
        spoken.speaker,
        spoken.text,
      );
      await _service.touch(session.id!);
      await _applyGameplayTurn(turn);
      // 记忆折叠：后台进行，不阻塞本次对话，失败也不影响展示
      // 回合结束：结算 after_turn 规则
      await PluginRuleRunner.settleTurn(
        sessionId: session.id!,
        turn: _turn + 1,
        userInput: _lastUserInput,
      );
      _turn++;
      unawaited(_service.refreshMemory(session.id!));
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.character,
            speaker: spoken.speaker,
            content: spoken.text,
            createdAt: DateTime.now(),
          ),
        ];
        _streaming = '';
      });

      // 首轮对话后自动生成会话标题（失败也不影响使用）
      if (!advancing && isFirstRound &&
          (session.title == null || session.title!.isEmpty)) {
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

  /// 旁观模式的「继续演出」：让在场的人自己往下演一幕。
  ///
  /// 与 [_send] 的区别只有一点——没有用户发言。规则结算、流式接收、
  /// 落库、玩法结算全部复用同一条路径，靠 [_advanceRequested] 告诉
  /// [_send] 走「无发言」分支；另写一份迟早会两边走偏。
  /// 「帮我写下一句」：让模型代拟几条可以发出去的话。
  Future<void> _openSuggestions() async {
    final session = _session;
    if (session == null || _sending) return;
    if (_messages.isEmpty) {
      SjToast.show('先聊两句再让 TA 帮你想');
      return;
    }
    setState(() => _sending = true);
    try {
      final list = await _service.suggestNextLine(
        session: session,
        history: _messages,
      );
      if (!mounted) return;
      if (list.isEmpty) {
        SjToast.show('这次没写出来，再试一次');
        return;
      }
      final picked = await showModalBottomSheet<ChatSuggestion>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('挑一句，可以直接改'),
                ),
              ),
              for (final s in list)
                ListTile(
                  title: Text(s.text),
                  subtitle: s.label.isEmpty ? null : Text(s.label),
                  onTap: () => Navigator.pop(ctx, s),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      _inputController.text = picked.text;
      _inputController.selection = TextSelection.collapsed(
        offset: picked.text.length,
      );
      _stopAutoPlayOnType();
    } catch (e) {
      if (!mounted) return;
      SjToast.show('代笔失败：$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  IconData _directorIcon(DirectorAction a) => switch (a) {
        DirectorAction.advance => Icons.skip_next,
        DirectorAction.slowEmotion => Icons.self_improvement,
        DirectorAction.conflict => Icons.flash_on,
        DirectorAction.viewpoint => Icons.swap_horiz,
        DirectorAction.fourthWall => Icons.theater_comedy,
      };

  /// 导演面板：选一个意图，可附一句目标。
  ///
  /// 与「继续演出」的区别：继续只是往前推，导演能指定往哪个方向推
  /// （放缓 / 冲突 / 换视角 / 破第四面墙）。
  Future<void> _openDirectorSheet() async {
    if (_session == null || _sending) return;
    var action = DirectorAction.advance;
    final goalCtrl = TextEditingController();
    final picked = await showModalBottomSheet<(DirectorAction, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('这一幕往哪走？'),
                  ),
                ),
                for (final a in DirectorAction.values)
                  ListTile(
                    leading: Icon(_directorIcon(a), size: 20),
                    title: Text(a.label),
                    subtitle: Text(a.hint),
                    trailing: action == a ? const Icon(Icons.check) : null,
                    onTap: () => setLocal(() => action = a),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: goalCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '这次想达成什么（可空）',
                      hintText: '例如：让宝玉先开口道歉',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(ctx, (action, goalCtrl.text.trim())),
                      child: const Text('开演'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    goalCtrl.dispose();
    if (picked == null) return;
    await _advance(action: picked.$1, goal: picked.$2);
  }

  Future<void> _advance({
    DirectorAction action = DirectorAction.advance,
    String? goal,
  }) async {
    if (_session == null || _sending) return;
    _advanceInstruction = buildDirectorDirective(action, goal: goal);
    _advanceRequested = true;
    try {
      await _send();
    } finally {
      _advanceRequested = false;
      _advanceInstruction = null;
    }
  }

  /// 开关自动连播。开启后每演完一幕自动续下一幕，到上限或被操作打断即停。
  void _toggleAutoPlay() {
    if (_autoPlay) {
      setState(() => _autoPlay = false);
      return;
    }
    setState(() {
      _autoPlay = true;
      _autoTurns = 0;
    });
    unawaited(_runAutoPlay());
  }

  Future<void> _runAutoPlay() async {
    while (mounted &&
        shouldContinueAutoPlay(
          autoPlay: _autoPlay,
          turns: _autoTurns,
          limit: _autoPlayLimit,
          hasError: _error != null,
        )) {
      setState(() => _autoTurns++);
      await _advance();
      // 出错或用户已经离开：立刻停，不要继续烧 token
      if (!mounted || _error != null) break;
      // 给用户一个能按停的窗口，也避免请求打得太密
      await Future<void>.delayed(autoPlayGap);
    }
    if (mounted && _autoPlay) setState(() => _autoPlay = false);
  }

  /// 用户开始打字 = 他要插话了，连播让位。
  void _stopAutoPlayOnType() {
    if (_autoPlay) setState(() => _autoPlay = false);
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
  /// 检查这一轮：让审校器点出跑偏的地方，可选择按问题重写。
  Future<void> _reviewLastTurn() async {
    final session = _session;
    if (session == null || _sending) return;
    if (_messages.isEmpty || _messages.last.role != CharacterChatRole.character) {
      SjToast.show('没有可检查的角色发言');
      return;
    }
    setState(() => _sending = true);
    var issues = const <ReviewIssue>[];
    try {
      issues = await _service.reviewLastTurn(
        session: session,
        history: _messages,
      );
    } catch (e) {
      if (mounted) SjToast.show('检查失败：$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    if (issues.isEmpty) {
      SjToast.show('这一轮没查出明显问题');
      return;
    }
    final fix = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('查出 ${issues.length} 处问题'),
              ),
            ),
            for (final i in issues)
              ListTile(
                leading: Icon(
                  i.isError ? Icons.error_outline : Icons.warning_amber,
                  size: 20,
                ),
                title: Text(i.codeLabel),
                subtitle: Text('${i.detail}\n原文：「${i.evidence}」'),
                isThreeLine: true,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('按问题重写这一轮'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (fix == true && mounted) {
      await _regenerate(correction: buildCorrectionInstruction(issues));
    }
  }

  Future<void> _regenerate({String? correction}) async {
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

    // 重走这一轮：先把状态回滚到本轮开始前，避免重复计分
    if (_gameplay != null && _statsBeforeTurn != null) {
      _gameplay =
          _gameplay!.copyWith(stats: Map<String, int>.from(_statsBeforeTurn!));
    }

    setState(() {
      _sending = true;
      _error = null;
      _streaming = '';
      _streamingRaw = '';
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
        rewriteInstruction: correction,
      )) {
        if (!mounted) return;
        _streamingRaw = chunk;
        // 状态块是给程序读的，展示时先剥掉
        setState(() => _streaming =
            GameplayRuntime.parse(chunk, streaming: true).displayText);
        _scrollToEnd();
      }

      // 从原始文本里解析状态块，正文用于展示与落库
      final turn = GameplayRuntime.parse(_streamingRaw);
      final reply = turn.displayText;
      if (reply.isEmpty) throw StateError('模型没有返回内容');
      final spoken = _speakerOf(session, reply);
      final id = await _service.saveCharacterMessage(
          session.id!, spoken.speaker, spoken.text);
      await _service.touch(session.id!);
      await _applyGameplayTurn(turn);
      // 记忆折叠：后台进行，不阻塞本次对话，失败也不影响展示
      // 回合结束：结算 after_turn 规则
      await PluginRuleRunner.settleTurn(
        sessionId: session.id!,
        turn: _turn + 1,
        userInput: _lastUserInput,
      );
      _turn++;
      unawaited(_service.refreshMemory(session.id!));
      if (!mounted) return;
      setState(() {
        _messages = [
          ...history,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.character,
            speaker: spoken.speaker,
            content: spoken.text,
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
  /// 另存为分支：把当前这段对话复制成一个新会话，此后两条线各走各的。
  ///
  /// 为什么需要：现在选错一句话只能清空重来，玩家因此**不敢做选择**。
  /// 能分支，"试一条路"才变得安全——试完还能回到原来的时间线上。
  /// 从末尾分叉（AppBar 的「另存为分支」）。
  Future<void> _fork() async {
    if (_messages.isEmpty) return;
    await _forkAt(_messages.last.id);
  }

  /// 从指定位置分叉。at 为 null 表示整段复制。
  ///
  /// 为什么需要：选错一句话只能清空重来，玩家因此**不敢做选择**。
  /// 能分支，"试一条路"才变得安全——试完还能回到原来的时间线上。
  Future<void> _forkAt(int? at) async {
    final session = _session;
    if (session?.id == null || _sending) return;
    try {
      final newId = await characterChatDao.forkSession(
        session!.id!,
        atMessageId: at,
      );
      final fresh = await characterChatDao.getSession(newId);
      if (!mounted || fresh == null) return;
      SjToast.show('已分出分支，接下来走的是新的时间线');
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CharacterChatPage(
            session: fresh,
            bookTitle: widget.bookTitle,
            gameplayMode: widget.gameplayMode,
          ),
        ),
      );
    } catch (e) {
      SjToast.show('分支失败：$e');
    }
  }

  /// 分支导航：回到主线 / 切到同源分支 / 走进从这条线分出去的分支。
  ///
  /// 「回到主线」必须跳到**根**而不是上一层：A→B→C 里停在 B 仍然是分支。
  Future<void> _openBranches() async {
    final session = _session;
    if (session?.id == null) return;

    CharacterChatSession? root;
    var siblings = <CharacterChatSession>[];
    var children = <CharacterChatSession>[];
    try {
      root = await characterChatDao.rootOf(session!);
      final parentId = session.parentSessionId;
      if (parentId != null) {
        siblings = await characterChatDao.listBranches(parentId);
      }
      children = await characterChatDao.listBranches(session.id!);
    } catch (e) {
      SjToast.show('读取分支失败：$e');
      return;
    }
    if (!mounted) return;

    final target = await showModalBottomSheet<CharacterChatSession>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final rows = <Widget>[];
        if (root != null && root.id != session.id) {
          rows.add(ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('回到主线'),
            subtitle: Text(root.displayTitle),
            onTap: () => Navigator.pop(ctx, root),
          ));
        }
        for (final s in siblings) {
          if (s.id == session.id) continue;
          rows.add(ListTile(
            leading: const Icon(Icons.call_split),
            title: Text(s.displayTitle),
            subtitle: const Text('同源分支'),
            onTap: () => Navigator.pop(ctx, s),
          ));
        }
        for (final s in children) {
          rows.add(ListTile(
            leading: const Icon(Icons.subdirectory_arrow_right),
            title: Text(s.displayTitle),
            subtitle: const Text('从这条线分出'),
            onTap: () => Navigator.pop(ctx, s),
          ));
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Text(
                    '这条时间线还没有分支。\n长按任意一条消息，可以「从这里分出分支」。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13),
                  ),
                )
              else
                Flexible(child: ListView(shrinkWrap: true, children: rows)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || target == null || target.id == session.id) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterChatPage(
          session: target,
          bookTitle: widget.bookTitle,
          gameplayMode: widget.gameplayMode,
        ),
      ),
    );
  }

  /// 「我的位置」的图标：旁观＝看着，扮演＝戴面具，入场＝推门进去。
  IconData _participationIcon(CharacterParticipation? participation) =>
      switch (participation) {
        CharacterParticipation.roleplay => Icons.theater_comedy_outlined,
        CharacterParticipation.join => Icons.login_outlined,
        _ => Icons.visibility_outlined,
      };

  /// 标题右边那枚「我现在是谁」的胶囊：常驻可见，点一下换姿态。
  Widget _participationChip(CharacterChatSession session, SjColors c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _changeParticipation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.inkSoft.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _participationIcon(session.participation),
              size: 12,
              color: c.inkSoft,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                participationLabel(
                  session.participation,
                  session.userPersona,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SjText.meta(c.inkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 中途改姿态：这一局你是旁观、扮演谁、还是以自己的身份入场。
  ///
  /// 姿态原先只能在开局时定，改主意就得重开一局。它本质上是"我在场上的位置"，
  /// 不是"这个人物是谁"，所以中途改是合理的。
  Future<void> _changeParticipation() async {
    final session = _session;
    if (session == null || session.id == null) return;
    // 下面会在闭包里用到这些值，先取出来：闭包捕获会让类型提升失效
    final sessionId = session.id!;
    final currentParticipation = session.participation;
    final currentPersona = session.userPersona;

    final picked = await showModalBottomSheet<CharacterParticipation>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in CharacterParticipation.values)
              ListTile(
                leading: Icon(
                  switch (p) {
                    CharacterParticipation.spectator =>
                      Icons.visibility_outlined,
                    CharacterParticipation.roleplay =>
                      Icons.theater_comedy_outlined,
                    CharacterParticipation.join => Icons.login_outlined,
                  },
                ),
                title: Text(p.label),
                trailing: currentParticipation == p
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;

    String? persona;
    if (picked != CharacterParticipation.spectator) {
      persona = await _askPersona(
        title: picked == CharacterParticipation.roleplay ? '你扮演谁' : '你叫什么',
        initial: currentPersona,
      );
      if (persona == null || persona.trim().isEmpty) return;
      persona = persona.trim();
    }

    try {
      await characterChatDao.updateParticipation(
        sessionId,
        participation: picked,
        userPersona: persona,
      );
      final fresh = await characterChatDao.getSession(sessionId);
      if (!mounted) return;
      setState(() => _session = fresh ?? session);
      SjToast.show('已改为「${participationLabel(picked, persona)}」');
    } catch (e) {
      SjToast.show('修改失败：$e');
    }
  }

  Future<String?> _askPersona({required String title, String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：林黛玉'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// 群聊回复形如「姓名：内容」，拆出说话人与正文；单人直接用会话人物名。
  ///
  /// 不拆的话，群聊里每条消息的 speaker 都是 `bookId:姓名,...` 整串：
  /// 界面上显示成一行内部编码，玩法也读不出"这句话是谁说的"。
  ({String speaker, String text}) _speakerOf(
    CharacterChatSession session,
    String reply,
  ) {
    final names = onStageNames(session.characterName);
    final fallback = names.isEmpty ? session.characterName : names.first;
    if (session.mode != CharacterChatMode.group) {
      return (speaker: fallback, text: reply);
    }
    final spoken = splitSpokenLine(reply, names);
    return (
      speaker: spoken.speaker.isEmpty ? fallback : spoken.speaker,
      text: spoken.text,
    );
  }

  /// 本会话的增强器开关。
  ///
  /// 与「设置 → AI → 插件」里的开关分开：那边是全局（阅读页 AI 用），
  /// 这边只作用于当前会话——同一个插件，这局开、下局关是合理的。
  /// 引入一名临时角色。
  ///
  /// 由插件声明"该来什么样的人"，宿主负责生成、写进在场成员、留一条入场旁白。
  /// 失败不影响会话——最坏是没加成，不会把对话搞坏。
  Future<void> _addTemporaryNpc() async {
    final session = _session;
    if (session == null || session.id == null) return;
    final generators = PluginRegistry.instance.availableNpcGenerators;
    if (generators.isEmpty) {
      SjToast.show('还没有插件提供临时角色');
      return;
    }

    var entry = generators.first;
    if (generators.length > 1) {
      final picked = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < generators.length; i++)
                ListTile(
                  title: Text(generators[i].generator.title),
                  onTap: () => Navigator.pop(ctx, i),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      entry = generators[picked];
    }

    final sessionId = session.id!;
    setState(() => _gameplayBusy = true);
    try {
      final npc = await generateNpc(
        generator: entry.generator,
        bookTitle: widget.bookTitle ?? '这本书',
        members: onStageNames(session.characterName),
        scene: widget.opening,
      );
      if (!mounted) return;
      if (npc == null) {
        SjToast.show('没能生成出合适的角色，可以再试一次');
        return;
      }

      await characterChatDao.addSessionMember(
        sessionId,
        defaultBookId: session.bookId,
        name: npc.name,
      );
      final notice = entry.generator.notice ??
          '一名新人物进入了场景：${npc.name}'
              '${npc.why.isEmpty ? '' : '——${npc.why}'}';
      await characterChatDao.appendMessage(
        sessionId: sessionId,
        role: CharacterChatRole.narrator,
        content: notice,
      );

      final fresh = await characterChatDao.getSession(sessionId);
      final messages = await characterChatDao.listMessages(sessionId);
      if (!mounted) return;
      setState(() {
        if (fresh != null) _session = fresh;
        _messages = messages;
      });
      SjToast.show('「${npc.name}」进入了场景');
    } catch (e) {
      SjToast.show('引入临时角色失败：$e');
    } finally {
      if (mounted) setState(() => _gameplayBusy = false);
    }
  }

  Future<void> _openSessionEnhancers() async {
    final session = _session;
    if (session == null || session.id == null) return;
    // 闭包捕获会让类型提升失效，先取出 id
    final sessionId = session.id!;
    final available = PluginRegistry.instance.availableEnhancers;
    if (available.isEmpty) {
      SjToast.show('还没有插件声明增强器');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('本会话的增强规则'),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in available)
                      SwitchListTile(
                        title: Text(entry.enhancer.title),
                        subtitle: Text(
                          entry.enhancer.rule,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: PluginRegistry.instance.isEnhancerEnabledIn(
                          sessionId,
                          entry.pluginId,
                          entry.enhancer.id,
                        ),
                        onChanged: (v) {
                          PluginRegistry.instance.setEnhancerEnabledIn(
                            sessionId,
                            entry.pluginId,
                            entry.enhancer.id,
                            v,
                          );
                          setLocal(() {});
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _sessionEnhancerRules =
          PluginRegistry.instance.enhancerRulesForSession(sessionId);
    });
  }

  Future<void> _readMind() async {
    final session = _session;
    if (session == null || _sending) return;
    if (_messages.isEmpty) {
      SjToast.show('先聊两句再读心');
      return;
    }
    setState(() => _sending = true);
    try {
      final mind = await _service.readMind(
        session: session,
        history: _messages,
      );
      // 标签由 service 给：群聊的 characterName 是内部编码，
      // 这里自己拼会印出「（1:姬动,1:烈焰,... 心里）」。
      final content = '（${mind.name} 心里）${mind.text}';
      final id = await characterChatDao.appendMessage(
        sessionId: session.id!,
        role: CharacterChatRole.narrator,
        content: content,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          CharacterChatMessage(
            id: id,
            sessionId: session.id!,
            role: CharacterChatRole.narrator,
            content: content,
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
            ListTile(
              leading: const Icon(Icons.call_split),
              title: const Text('从这里分出分支'),
              subtitle: const Text('保留到这为止的经过，另开一条时间线'),
              onTap: () => Navigator.pop(ctx, 'fork'),
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
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('检查这一轮（有没有跑偏）'),
                onTap: () => Navigator.pop(ctx, 'review'),
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
      case 'fork':
        await _forkAt(m.id);
      case 'regenerate':
        await _regenerate();
      case 'mind':
        await _readMind();
      case 'review':
        await _reviewLastTurn();
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

    // 玩法对局也重新开局：否则状态会停留在清空前的数值上
    if (widget.gameplayMode != null) {
      await gameplayDao.deleteByChatSession(session.id!);
      _gameplay = null;
      await _initGameplay(session);
      if (!mounted) return;
    }

    await _generateGreeting();
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final session = _session;
    final title = widget.titleOverride ??
        session?.displayTitle ??
        widget.characterName ??
        CharactersPageText.chatTitle;

    return Scaffold(
      appBar: AppBar(
        // 标题栏只留两行：标题；下面一行是「我现在是谁」的胶囊 + 书名。
        // 姿态原先埋在一行 12px 小字里，被 6 个动作按钮一挤就没了。
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (session != null || widget.bookTitle != null)
              Row(
                children: [
                  if (session != null) _participationChip(session, c),
                  if (session != null && widget.bookTitle != null)
                    const SizedBox(width: 8),
                  if (widget.bookTitle != null)
                    Flexible(
                      child: Text(
                        widget.bookTitle!,
                        style: SjText.meta(c.inkSoft),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
          ],
        ),
        bottom: (widget.gameplayMode != null && _gameplay != null)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: _buildGameplayBar(c),
              )
            : null,
        // 动作按钮从 6 个收到 2 个（读心 + 更多）。
        //
        // 原先 6 个按钮（6×48dp）把 360dp 宽屏幕剩下的十几 dp 全给了标题，
        // 标题和「旁观 / 扮演 / 入场」那行被挤成 0 宽——等于没有入口，
        // 用户只能去猜哪个图标是切换身份（图里都以为是那个分叉）。
        actions: [
          IconButton(
            tooltip: '读心',
            icon: const Icon(Icons.psychology_outlined),
            onPressed: (_sending || _messages.isEmpty) ? null : _readMind,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'branches':
                  await _openBranches();
                case 'fork':
                  await _fork();
                case 'enhancers':
                  await _openSessionEnhancers();
                case 'npc':
                  await _addTemporaryNpc();
                case 'clear':
                  await _clear();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem<String>(
                value: 'branches',
                child: Text('分支…'),
              ),
              PopupMenuItem<String>(
                value: 'fork',
                enabled: !_sending && _messages.isNotEmpty,
                child: const Text('另存为分支'),
              ),
              const PopupMenuItem<String>(
                value: 'enhancers',
                child: Text('本会话增强规则'),
              ),
              const PopupMenuItem<String>(
                value: 'npc',
                child: Text('引入临时角色'),
              ),
              PopupMenuItem<String>(
                value: 'clear',
                enabled: _messages.isNotEmpty,
                child: const Text(CharactersPageText.chatClear),
              ),
            ],
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
    // 按成员的状态（好感/信任）需要知道有谁在场
    final members = onStageNames(
      _session?.characterName ?? widget.characterName ?? '',
    );
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
              if (def.perMember && members.isNotEmpty)
                for (final m in members) ...[
                  Text(
                    '${def.name}·$m ${state.memberStats[def.key]?[m] ?? def.initial}',
                    style: SjText.meta(def.isScore ? c.clay : c.inkSoft),
                  ),
                  const SizedBox(width: 8),
                ]
              else
                Text(
                  '${def.name} ${state.stats[def.key] ?? def.initial}',
                  style: SjText.meta(def.isScore ? c.clay : c.inkSoft),
                ),
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

  /// 旁观模式才有「继续演出」：这种模式不靠读者发言驱动，
  /// 否则提示词里那句"不要等读者回答"永远等不到兑现。
  bool get _isSpectator =>
      (_session?.participation ?? CharacterParticipation.spectator) ==
      CharacterParticipation.spectator;

  Widget _buildAutoPlayBanner(SjColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 0),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline, size: 16, color: c.pine),
            const SizedBox(width: 6),
            Text(
              '自动连播中 · $_autoTurns / $_autoPlayLimit 幕',
              style: SjText.meta(c.inkSoft),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _autoPlay = false),
              child: const Text('停止'),
            ),
          ],
        ),
      );

  Widget _buildInputBar(SjColors c) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_autoPlay) _buildAutoPlayBanner(c),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !_sending && !_gameplayBusy,
                    decoration: InputDecoration(
                      hintText: _isSpectator ? '插话（也可以直接看下去）' : CharactersPageText.chatInputHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => _stopAutoPlayOnType(),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _sending ? null : _openSuggestions,
                  icon: const Icon(Icons.auto_fix_high, size: 20),
                  tooltip: '帮我写下一句',
                ),
                if (_isSpectator) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _sending ? null : _openDirectorSheet,
                    icon: const Icon(Icons.skip_next),
                    tooltip: '继续演出',
                  ),
                  IconButton(
                    onPressed: _sending ? null : _toggleAutoPlay,
                    icon: Icon(
                      _autoPlay ? Icons.pause_circle : Icons.play_circle,
                    ),
                    color: _autoPlay ? c.pine : null,
                    tooltip: _autoPlay ? '暂停连播' : '自动连播',
                  ),
                ],
                const SizedBox(width: 8),
                _sending
                    ? SizedBox(
                        width: 44,
                        height: 44,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: c.pine),
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
        ],
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
