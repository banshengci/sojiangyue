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
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/dao/gameplay_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_catalog.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_judge.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_setup.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/service/character/character_chat_service.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/empty_state_hint.dart';

import 'characters_page_strings.dart';
import 'character_avatar.dart';
import 'character_relation_sheet.dart';
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

  /// 判官对本轮的结论（违规了就把后果要求塞进这一轮的设定）。
  String? _judgeDirective;

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

  /// 本场用的玩法。
  ///
  /// 优先用调用方传进来的（从玩法中心开局）；从会话列表进来时调用方不知道
  /// 这是哪一局玩法，就在 [_initGameplay] 里按库里那局存档的 modeId 反查回来。
  /// 页面内一律读这个字段，不要再读 `widget.gameplayMode`——否则从列表进来的
  /// 对局会「看得见历史、玩法却整个失效」。
  GameplayMode? _gameplayMode;

  /// 本页装进插件注册表的玩法技能 id（没装过为 null）。
  ///
  /// 分支用 pushReplacement，新旧两页会短暂共存；用一个静态引用计数
  /// 保证后装的不会被前一页的 dispose 顺手卸掉。
  String? _installedSkillId;
  static final Map<String, int> _skillRefs = {};

  /// 在场人物卡（按姓名索引），气泡头像用。
  ///
  /// 跨书场景里说话的人可能来自别的书，所以按 `bookId:姓名` 逐个补。
  Map<String, CharacterCard> _cards = const {};

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
      if (_gameplayMode != null && _gameplay != null)
        GameplayRuntime.buildDirective(
          mode: _gameplayMode!,
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

      if (_judgeDirective != null && _judgeDirective!.trim().isNotEmpty)
        _judgeDirective!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  @override
  void dispose() {
    // 离开页面必须停连播：否则会在后台继续烧 token
    _autoPlay = false;
    _releaseGameplaySkills();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 把玩法自带的技能装进插件注册表。
  ///
  /// 装完立刻把它的增强器与规则对本局打开——它们本来就是这一局的一部分，
  /// 不该让玩家再去菜单里逐条勾选。
  void _installGameplaySkills(GameplayMode mode, int sessionId) {
    if (!mode.hasSkills) return;
    final id = GameplayRuntime.pluginIdFor(mode);
    if (_installedSkillId == id) return;
    try {
      final manifest = GameplayRuntime.buildPluginManifest(mode);
      if (manifest == null) return;
      PluginRegistry.instance.loadManifest(manifest);
      for (final e in manifest.enhancers) {
        PluginRegistry.instance.setEnhancerEnabledIn(
          sessionId,
          manifest.id,
          e.id,
          true,
        );
      }
      for (final r in manifest.rules) {
        PluginRegistry.instance.setRuleEnabled(manifest.id, r.id, true);
      }
      // 增强规则在 _init 里读过一次，装完要重新读，否则本局第一句话吃不到
      _sessionEnhancerRules =
          PluginRegistry.instance.enhancerRulesForSession(sessionId);
      _installedSkillId = id;
      _skillRefs[id] = (_skillRefs[id] ?? 0) + 1;
      SjLog.info(
        'Gameplay: 装载玩法技能 $id'
        '（工具 ${manifest.tools.length}，增强 ${manifest.enhancers.length}，'
        '规则 ${manifest.rules.length}）',
      );
    } catch (e) {
      SjLog.warning('Gameplay: 装载玩法技能失败（按无技能处理）: $e');
    }
  }

  /// 卸掉本页装的玩法技能（引用计数归零才真的卸）。
  void _releaseGameplaySkills() {
    final id = _installedSkillId;
    if (id == null) return;
    _installedSkillId = null;
    final left = (_skillRefs[id] ?? 1) - 1;
    if (left > 0) {
      _skillRefs[id] = left;
      return;
    }
    _skillRefs.remove(id);
    try {
      PluginRegistry.instance.unload(id);
    } catch (e) {
      SjLog.warning('Gameplay: 卸载玩法技能失败: $e');
    }
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
      final cards = await _loadCards(session);
      if (!mounted) return;
      setState(() {
        _session = session;
        _messages = messages;
        _cards = cards;
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

  /// 把在场人物卡读出来（气泡头像用）。
  ///
  /// 失败就当没有头像——退回首字头像，不该因为读卡失败让对话打不开。
  Future<Map<String, CharacterCard>> _loadCards(
    CharacterChatSession session,
  ) async {
    final out = <String, CharacterCard>{};
    try {
      final byBook = <int, List<CharacterCard>>{};
      Future<List<CharacterCard>> cardsOf(int bookId) async {
        final cached = byBook[bookId];
        if (cached != null) return cached;
        final list = await characterDao.getCharacters(bookId);
        byBook[bookId] = list;
        return list;
      }

      for (final ref in parseMemberRefs(session.characterName, session.bookId)) {
        for (final c in await cardsOf(ref.bookId)) {
          out[c.name] = c;
        }
      }
      // 单人会话没有成员编码时，退回按本书全量加载
      if (out.isEmpty) {
        for (final c in await cardsOf(session.bookId)) {
          out[c.name] = c;
        }
      }
    } catch (e) {
      SjLog.warning('CharacterChat: 读取人物卡失败（头像退回首字）: $e');
    }
    return out;
  }

  /// 初始化玩法运行时：加载或新建本局状态，需要暗牌则先生成。
  Future<void> _initGameplay(CharacterChatSession session) async {
    // 三条来路：调用方指定（玩法中心）→ 本页已知（清空重开）→ 库里存档反查（会话列表）
    final mode = _gameplayMode ??
        widget.gameplayMode ??
        await _restoreGameplayMode(session);
    if (mode == null) return;

    final existing = await gameplayDao.getByChatSession(session.id!);
    if (existing != null) {
      if (!mounted) return;
      setState(() {
        _gameplayMode = mode;
        _gameplay = existing;
      });
      _installGameplaySkills(mode, session.id!);
      // 存档在、但暗牌没写出来（开局时没配 AI / 调用失败）：
      // 这一局其实没法玩——判官没有规则可判，指认没有真相可比。
      // 以前这里直接 return，玩家只能自己去菜单里点「重新生成本局设定」。
      if (mode.setupPrompt != null &&
          (existing.secret?.trim().isEmpty ?? true)) {
        await _setupSecret();
      }
      return;
    }

    var fresh = GameplaySession(
      chatSessionId: session.id!,
      modeId: mode.id,
      stats: {for (final d in mode.stats) d.key: d.initial},
    );
    fresh = fresh.copyWith(id: await gameplayDao.save(fresh));
    if (!mounted) return;
    setState(() {
      _gameplayMode = mode;
      _gameplay = fresh;
    });
    _installGameplaySkills(mode, session.id!);

    // 玩法有暗牌（剧本杀真相 / 海龟汤汤底）时，开局先让模型写出来
    if (mode.setupPrompt != null) await _setupSecret();
  }

  /// 从库里那局存档反查玩法。
  ///
  /// 会话表本身不记「这是哪一局玩法」，但 `gameplay_session` 按 chatSessionId
  /// 存着 modeId。会话列表点进来时调用方只给了 session，就靠这一手把玩法接回来。
  /// 找不到（普通对话、或玩法包已被卸载）时返回 null，页面退化成普通对话。
  Future<GameplayMode?> _restoreGameplayMode(
    CharacterChatSession session,
  ) async {
    if (session.id == null) return null;
    try {
      final existing = await gameplayDao.getByChatSession(session.id!);
      if (existing == null) return null;
      final catalog = await GameplayCatalog.load();
      GameplayMode? mode;
      for (final m in catalog.all) {
        if (m.id == existing.modeId) {
          mode = m;
          break;
        }
      }
      if (mode == null) {
        SjLog.warning('Gameplay: 存档里的玩法 ${existing.modeId} 已不存在，按普通对话处理');
        return null;
      }
      SjLog.info('Gameplay: 从存档恢复玩法 ${mode.id}（会话 ${session.id}）');
      return mode;
    } catch (e) {
      SjLog.warning('Gameplay: 恢复玩法失败，按普通对话处理: $e');
      return null;
    }
  }

  /// 生成暗牌。
  Future<void> _setupSecret() async {
    final mode = _gameplayMode;
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

  /// 往对话里插一条旁白（落库 + 上屏）。
  ///
  /// 门槛事件、收局、指认结果都走这里：它们是**程序**说的话，
  /// 不该混进角色的气泡里，否则玩家分不清"谁在说"。
  Future<void> _appendNarrator(String text) async {
    final state = _gameplay;
    if (state == null) return;
    final id = await characterChatDao.appendMessage(
      sessionId: state.chatSessionId,
      role: CharacterChatRole.narrator,
      content: text,
    );
    if (!mounted) return;
    setState(() {
      _messages = [
        ..._messages,
        CharacterChatMessage(
          id: id,
          sessionId: state.chatSessionId,
          role: CharacterChatRole.narrator,
          content: text,
          createdAt: DateTime.now(),
        ),
      ];
    });
    _scrollToEnd();
  }

  /// 重新生成本局设定（老存档没有分段标记时用得上）。
  Future<void> _regenerateSetup() async {
    final mode = _gameplayMode;
    final state = _gameplay;
    if (mode == null || state == null || mode.setupPrompt == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成本局设定'),
        content: const Text('会换一套规则/真相，对话记录保留。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(CharactersPageText.chatCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _gameplayBusy = true);
    try {
      final raw = _session?.characterName ?? widget.characterName ?? '主角';
      final names = onStageNames(raw);
      final secret = await _service.generateGameplaySecret(
        mode: mode,
        characterName: names.isEmpty ? raw : names.join('、'),
        bookTitle: widget.bookTitle,
        scene: widget.opening,
      );
      _gameplay = state.copyWith(secret: secret, revealed: false);
      await gameplayDao.save(_gameplay!);
      if (!mounted) return;
      setState(() {});
      SjToast.show('本局设定已重新生成');
    } catch (e) {
      SjLog.warning('Gameplay: 重新生成开局失败: $e');
      if (mounted) SjToast.show('生成失败：$e');
    } finally {
      if (mounted) setState(() => _gameplayBusy = false);
    }
  }

  /// 指认：玩家提交凶手与手法，判官对照暗牌判定。
  ///
  /// 这是剧本杀真正的「动作」——没有它，玩家说什么都只是聊天。
  Future<void> _accuse() async {
    final mode = _gameplayMode;
    final state = _gameplay;
    if (mode == null || state == null || state.ended) return;
    if (state.secret == null || state.secret!.trim().isEmpty) {
      SjToast.show('这一局还没有可对照的真相');
      return;
    }

    final suspectCtrl = TextEditingController();
    final methodCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(mode.accusationLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: suspectCtrl,
              decoration:
                  InputDecoration(labelText: mode.accusationSuspectLabel),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: methodCtrl,
              decoration:
                  InputDecoration(labelText: mode.accusationMethodLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(CharactersPageText.chatCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(mode.accusationLabel),
          ),
        ],
      ),
    );
    final suspect = suspectCtrl.text.trim();
    suspectCtrl.dispose();
    final method = methodCtrl.text.trim();
    methodCtrl.dispose();
    if (confirmed != true || suspect.isEmpty || !mounted) return;

    setState(() => _gameplayBusy = true);
    try {
      final setup = GameplaySetup.parse(state.secret);
      final result = await GameplayJudge.accuse(
        setup: setup,
        suspect: suspect,
        method: method,
      );
      // 先说判定结果，再结算——对错要在收局旁白之前出现，读着才顺
      if (!mounted) return;
      await _appendNarrator(
        result.correct
            ? '【指认】${result.feedback.isEmpty ? '你说对了。' : result.feedback}'
            : '【指认】${result.feedback.isEmpty ? '不对。' : result.feedback}',
      );
      // 说对了：把「胜负分」直接推到赢的阈值，交给收局条件判；
      // 说错了：退一步，还有机会。胜负分取这一档玩法里那条赢的结局。
      final winEnding = mode.endings.where((e) => e.win).firstOrNull;
      final verdictStat = winEnding?.statKey ?? 'suspicion';
      final winTarget = winEnding?.atLeast ?? 100;
      await _applyGameplayTurn(
        GameplayTurn(
          displayText: '',
          deltas: {verdictStat: result.correct ? winTarget : -15},
          note: result.correct ? '指认正确：$suspect' : '指认错误：$suspect',
        ),
      );
    } catch (e) {
      if (mounted) SjToast.show('判定失败：$e');
    } finally {
      if (mounted) setState(() => _gameplayBusy = false);
    }
  }

  /// 揭晓暗牌（对局后的复盘）。
  Future<void> _revealSecret() async {
    final raw = _gameplay?.secret;
    if (raw == null || raw.isEmpty) return;
    // 开局设定现在分三段，这里只该给玩家看「暗牌」那段，
    // 否则会把【公开】【规则】的标记一起甩到脸上。
    final setup = GameplaySetup.parse(raw);
    final secret = setup.secret.isNotEmpty ? setup.secret : raw;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = SjColors.of(ctx);
        return AlertDialog(
          title: Text(_gameplayMode?.secretLabel ?? '揭晓真相'),
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

  /// 本场规则：公开信息 + 玩家必须遵守的硬规则（暗牌只在已揭晓时出现）。
  ///
  /// 这一屏是「玩法」和「普通聊天」的分界线：规则怪谈的乐趣全在于
  /// 玩家拿着规则去试探，规则不在玩家手里，玩法就只剩氛围描写。
  Future<void> _showRules() async {
    final raw = _gameplay?.secret;
    if (raw == null || raw.trim().isEmpty) return;
    final setup = GameplaySetup.parse(raw);
    final revealed = _gameplay?.revealed ?? false;
    final c = SjColors.of(context);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_gameplayMode?.name ?? '本场'} · 规则',
                style: SjText.cardTitle(c.ink),
              ),
              if (setup.publicBrief.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(setup.publicBrief, style: SjText.body(c.ink)),
              ],
              if (setup.rules.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('必须遵守', style: SjText.meta(c.inkSoft)),
                const SizedBox(height: 6),
                for (var i = 0; i < setup.rules.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ',
                            style: SjText.meta(c.inkSoft)),
                        Expanded(
                          child: Text(
                            setup.rules[i],
                            style: SjText.body(c.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (revealed && setup.secret.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  _gameplayMode?.secretLabel ?? '真相',
                  style: SjText.meta(c.inkSoft),
                ),
                const SizedBox(height: 6),
                Text(setup.secret, style: SjText.body(c.ink)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 玩法对回复格式的硬约束。
  ///
  /// 海龟汤的全部难度在于「只能回答是 / 否 / 与此无关」——模型只要多解释一句，
  /// 玩家就不用猜了，这一局也就废了。所以这里不靠提示词自律，直接切。
  String _enforceGameplayReply(String text) {
    if (_gameplayMode?.id != 'haigui-soup') return text;
    return parseYesNo(text) ?? text;
  }

  /// 结算本回合：把状态变化累加进本局。
  ///
  /// 结局由运行时按状态阈值判定（不是模型说了算）；真收局了就补一条旁白，
  /// 并顺手把暗牌揭开——不然玩家只看到「结束了」，却不知道自己错过了什么。
  /// 门槛跨线时也会补旁白：数字变化必须有后果，否则状态栏只是装饰。
  Future<void> _applyGameplayTurn(GameplayTurn turn) async {
    final mode = _gameplayMode;
    final session = _gameplay;
    if (mode == null || session == null) return;
    if (!turn.hasChanges &&
        !turn.ended &&
        !turn.advancePhase &&
        turn.note == null) {
      // 一句日志：模型这回合没写状态块（或写了空块）。
      // 没有这条，出问题时只能靠截图猜"觉醒度到底动没动"。
      SjLog.info('Gameplay: turn=${session.turn + 1} 本回合无状态变化');
      return;
    }
    final result = GameplayRuntime.apply(
      mode: mode,
      session: session,
      turn: turn,
    );
    _gameplay = result.session;
    await gameplayDao.save(_gameplay!);
    if (!mounted) return;
    setState(() {});

    SjLog.info(
      'Gameplay: turn=${result.session.turn} '
      'phase=${result.session.phaseIndex + 1}/${mode.phases.length} '
      'deltas=${turn.deltas} stats=${result.session.stats} '
      'events=${result.events.length} ended=${result.session.ended}',
    );

    // 门槛事件先播（它是过程），结局最后播（它是收尾）
    for (final event in result.events) {
      if (!mounted) return;
      SjLog.info('Gameplay: 跨过门槛「$event」');
      await _appendNarrator('【转折】$event');
    }

    final ending = result.ending;
    if (ending == null) return;
    SjLog.info('Gameplay: 收局 —— ${ending.text}');
    if (!_gameplay!.revealed) {
      _gameplay = _gameplay!.copyWith(revealed: true);
      await gameplayDao.save(_gameplay!);
    }
    if (!mounted) return;
    await _appendNarrator('【本局结束】${ending.text}');
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

    // 判官：在生成回复**之前**判定玩家这一句有没有违规。
    // 放在之后就没用了——后果要这一轮就发生，而不是下一轮补一句"你刚才违规了"。
    var judgeDeltas = <String, int>{};
    String? judgeNote;
    _judgeDirective = null;
    final judgeMode = _gameplayMode;
    if (judgeMode != null &&
        judgeMode.judged &&
        !advancing &&
        text.isNotEmpty &&
        _gameplay != null) {
      final setup = GameplaySetup.parse(_gameplay!.secret);
      if (setup.rules.isNotEmpty) {
        setState(() => _gameplayBusy = true);
        try {
          final verdict = await GameplayJudge.checkViolation(
            mode: judgeMode,
            setup: setup,
            playerAction: text,
          );
          if (verdict.violated) {
            final rule = setup.rules[verdict.violatedRule! - 1];
            // 扣什么由玩法自己定：规则怪谈扣神志，剧本杀/海龟汤扣主计分量
            judgeDeltas = GameplayJudge.penaltyFor(
              judgeMode,
              fatal: verdict.fatal,
            );
            judgeNote = '违反规则 ${verdict.violatedRule}：$rule';
            _judgeDirective = '【判官】玩家刚刚违反了第 ${verdict.violatedRule} 条规则'
                '（$rule）${verdict.fatal ? '，而且是致命的那条' : ''}。'
                '本回合必须让后果立刻发生（不合常理的异象、环境变化、旁人的反应），'
                '不要只是口头提醒，也不要写出"违反了规则"这几个字。';
          }
        } finally {
          if (mounted) setState(() => _gameplayBusy = false);
        }
      }
    }

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
      //
      // 写库失败不该让整个回合崩掉：界面上这一句已经在，先继续生成，
      // 只把错误记下来（以前它裸在 try 外面，一抛就穿到全局错误处理）。
      try {
        await _service.saveUserMessage(session.id!, text);
      } catch (e) {
        SjLog.warning('CharacterChat: 读者这一句没存下来: $e');
      }
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

      // 从原始文本里解析状态块，正文用于展示与落库。
      // 判官的结算（违规 +1、神志受损）并进这一轮，回合数只加一次。
      var turn = GameplayRuntime.merge(
        GameplayRuntime.parse(_streamingRaw),
        deltas: judgeDeltas,
        note: judgeNote,
      );
      final reply = _enforceGameplayReply(turn.displayText);
      if (reply.isEmpty) {
        throw StateError('模型没有返回内容');
      }
      // 玩法自带的「每回合技能」：状态量由独立技能判，而不是让正在演戏的
      // 模型自己在正文末尾报。没声明 turnTool 的玩法不会有这次额外调用。
      //
      // 顺序是有讲究的：先并入判官（违规次数 + 违规的神志惩罚），再让技能覆盖。
      // 技能看到的是这一回合**已经演出后果**的正文，所以它判的神志已经包含了
      // 违规的惊吓；再叠一次判官的 -8 就是双算。但技能不碰 violations，
      // 判官记的违规次数会原样保留。
      final skillMode = _gameplayMode;
      final skillState = _gameplay;
      if (skillMode != null &&
          skillState != null &&
          GameplayRuntime.turnToolIdFor(skillMode) != null) {
        final judged = await GameplayRuntime.runTurnTool(
          mode: skillMode,
          session: skillState,
          // 用剥离状态块后的原话，不要用 _enforceGameplayReply 的结果：
          // 海龟汤会被截成「是/否」，技能拿着两个字什么也判不出来。
          replyText: turn.displayText,
          // 按人记的状态要写「好感|姬动」，技能得知道有谁在场
          members: onStageNames(session.characterName),
          // 推理类玩法要看玩家问的是什么；暗牌给它做对照
          playerInput: _lastUserInput,
          secret: GameplaySetup.parse(skillState.secret).secret,
        );
        turn = GameplayRuntime.overrideWith(turn, judged, mode: skillMode);
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
      SjLog.warning('CharacterChat: 本轮失败: $e');
      setState(() => _error = _friendlyError(e));
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
      try {
        await _advance();
      } catch (e) {
        // 连播是 unawaited 起的，异常漏出去就是一条全局未捕获错误
        SjLog.warning('CharacterChat: 连播中断: $e');
        break;
      }
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
    // 判官结论只属于那一轮，重走这一轮时不能带过来
    _judgeDirective = null;
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
      final reply = _enforceGameplayReply(turn.displayText);
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
            gameplayMode: _gameplayMode,
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
          gameplayMode: _gameplayMode,
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
    if (_gameplayMode != null) {
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
        bottom: (_gameplayMode != null && _gameplay != null)
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
                case 'accuse':
                  await _accuse();
                case 'regen':
                  await _regenerateSetup();
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
              if (_gameplayMode?.accusation ?? false)
                PopupMenuItem<String>(
                  value: 'accuse',
                  enabled: !_sending &&
                      _gameplay != null &&
                      !(_gameplay?.ended ?? false),
                  child: Text('${_gameplayMode?.accusationLabel ?? '指认'}…'),
                ),
              if (_gameplayMode?.setupPrompt != null)
                const PopupMenuItem<String>(
                  value: 'regen',
                  child: Text('重新生成本局设定'),
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
                              return _buildSpoken(
                                _streaming,
                                firstSpeaker: null,
                                streaming: true,
                              );
                            }
                            final m = _messages[i];
                            if (m.role == CharacterChatRole.narrator) {
                              return _NarratorLine(text: m.content);
                            }
                            return GestureDetector(
                              onLongPress: () => _onBubbleLongPress(m),
                              child: m.role == CharacterChatRole.user
                                  ? _Bubble(text: m.content, isUser: true)
                                  : _buildSpoken(
                                      m.content,
                                      firstSpeaker: m.speaker,
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

  /// 渲染一段角色回复：按「姓名：」切成多张卡片，纯括注走旁白行。
  ///
  /// 落库仍然是一回合一条（原因见 [splitSpokenBlock] 的注释），这里只改观感：
  /// 以前一回合里弗瑞、姬动、陈思璇轮着说话，会整段堆进第一张卡片，
  /// 看起来像那个人替全场说了话。
  Widget _buildSpoken(
    String text, {
    String? firstSpeaker,
    bool streaming = false,
  }) {
    final names = onStageNames(_session?.characterName ?? '');
    final segments = splitSpokenBlock(
      text,
      firstSpeaker: firstSpeaker,
      onStage: names,
    );

    // 空内容：流式期间显示「正在想…」
    if (segments.isEmpty) {
      return _Bubble(text: text, isUser: false, streaming: streaming);
    }

    if (segments.length == 1) {
      final only = segments.first;
      if (only.isNarration) return _NarratorLine(text: only.text);
      final who = only.speaker.isEmpty ? (firstSpeaker ?? '') : only.speaker;
      return _CharacterBubble(
        text: only.text,
        speaker: who,
        card: _cards[who],
        streaming: streaming,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < segments.length; i++)
          if (segments[i].isNarration)
            _NarratorLine(text: segments[i].text)
          else
            _CharacterBubble(
              text: segments[i].text,
              speaker: segments[i].speaker,
              card: _cards[segments[i].speaker],
              // 只有最后一段可能是半截话
              streaming: streaming && i == segments.length - 1,
            ),
      ],
    );
  }

  /// 玩法状态条：玩法名 · 进度幕 · 各状态量 · 揭晓入口。
  /// 打开「关系」面板：在场这几位彼此什么态度。
  void _showRelations() {
    final session = _session;
    if (session == null) return;
    showCharacterRelationSheet(
      context,
      bookId: session.bookId,
      members: onStageNames(session.characterName),
      mode: _gameplayMode,
      state: _gameplay,
    );
  }

  Widget _buildGameplayBar(SjColors c) {    final mode = _gameplayMode!;
    final state = _gameplay!;
    // 按成员的状态（好感/信任）需要知道有谁在场
    final members = onStageNames(
      _session?.characterName ?? widget.characterName ?? '',
    );
    final phase = mode.phases.isEmpty
        ? null
        : mode.phases[state.phaseIndex.clamp(0, mode.phases.length - 1)];
    final setup = GameplaySetup.parse(state.secret);

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
            // 规则一直摆在玩家手边：这是玩法能不能玩起来的关键。
            // 没有规则但有公开信息（海龟汤的汤面）时，也要能点开看。
            if (setup.hasVisible) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _showRules,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rule_outlined, size: 12, color: c.pine),
                    const SizedBox(width: 3),
                    Text(
                      setup.rules.isEmpty ? '须知' : '规则 ${setup.rules.length} 条',
                      style: SjText.meta(c.pine),
                    ),
                  ],
                ),
              ),
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
            // 关系面板：谁对谁什么态度。
            // 提示词里那份「各怀心思」只给模型看，玩家只能从台词里猜；
            // 摆一个入口在这儿，猜得到才叫有戏。
            if (members.length > 1) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _showRelations,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.diversity_3, size: 12, color: c.pine),
                    const SizedBox(width: 3),
                    Text('关系', style: SjText.meta(c.pine)),
                  ],
                ),
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

  /// 把异常翻成人话。
  ///
  /// 原始信息（`ClientException: Connection closed while receiving data,
  /// uri=https://…`）只进日志——糊在错误条上，用户既看不懂也不知道该做什么。
  String _friendlyError(Object e) {
    if (e is CharacterChatException) return e.message;
    if (e is TimeoutException) {
      return '模型响应超时了。检查网络，或到「设置 → AI」换个服务再试。';
    }
    final raw = e.toString();
    if (raw.contains('Connection closed') ||
        raw.contains('SocketException') ||
        raw.contains('Connection refused') ||
        raw.contains('Connection reset')) {
      return '连接被中断了，模型服务没有响应。检查网络后重试。';
    }
    if (raw.contains('401') || raw.contains('Unauthorized')) {
      return 'API 密钥好像不对，去「设置 → AI」核对一下。';
    }
    if (raw.contains('429')) {
      return '请求太频繁了，歇一会儿再试。';
    }
    // 兜底截断：别让一整串英文堆栈占满错误条
    final short = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
    return '这一轮没生成出来：$short';
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

/// 旁白行（开局情境 / 门槛 / 收局）：左边一个小三角，不占气泡。
///
/// 原来是居中斜体。中文斜体不好看，而且一段场景描写居中之后每行都要重新找
/// 起点，读着累；改成左对齐、带个「▶」的引导符，和剧本里的舞台提示一致。
class _NarratorLine extends StatelessWidget {
  const _NarratorLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.play_arrow_rounded, size: 13, color: c.inkSoft),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              text,
              style: SjText.meta(c.inkSoft).copyWith(height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条角色发言：左侧头像 + 上方姓名 + 气泡。
///
/// 名字原先压在气泡里，一段戏里四五个人轮流说话时很难一眼看出谁在说；
/// 头像放在左边之后，扫一眼就知道换人了。
class _CharacterBubble extends StatelessWidget {
  const _CharacterBubble({
    required this.text,
    required this.speaker,
    this.card,
    this.streaming = false,
  });

  final String text;
  final String speaker;

  /// 有卡片就用真头像，没有就退回首字。
  final CharacterCard? card;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final name = speaker.trim();
    final card = this.card;

    final avatar = card != null
        ? characterAvatar(card, c, radius: 17)
        : CircleAvatar(
            radius: 17,
            backgroundColor: c.frost,
            child: Text(
              name.isEmpty ? '·' : name.substring(0, 1),
              style: SjText.meta(c.ink),
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 3),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SjText.meta(c.inkSoft),
                    ),
                  ),
                _Bubble(
                  text: text,
                  isUser: false,
                  streaming: streaming,
                  // 头像占了 42，气泡别顶到右边
                  maxWidthFactor: 0.7,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 消息气泡：读者在右，书中人在左。
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.isUser,
    this.streaming = false,
    this.maxWidthFactor = 0.78,
  });

  final String text;
  final bool isUser;
  final bool streaming;
  final double maxWidthFactor;

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
          maxWidth: MediaQuery.of(context).size.width * maxWidthFactor,
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
        child: Text(
          text.isEmpty && streaming ? CharactersPageText.chatThinking : text,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: fg,
          ),
        ),
      ),
    );
  }
}
