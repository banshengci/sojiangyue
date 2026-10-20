// lib/service/gameplay/gameplay_runtime.dart
//
// 玩法运行时：让玩法真的有「状态」和「推进」。
//
// 工作方式：
//   1. 每轮对话前，把玩法规则 + 当前状态 + 暗牌 + 分幕进度拼进角色的 system 侧设定；
//   2. 要求模型在回复末尾附一个状态块 `<sj-state>{...}</sj-state>`，声明本回合
//      哪些状态量变了、变了多少；
//   3. 运行时把状态块**从正文里剥掉**（读者看不到），把数值结算进状态，
//      并推进回合/分幕、记录事件。
//
// 这样「好感 +8」「线索 +1」是真实累计的，而不是嘴上说说。

import 'dart:convert';

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_setup.dart';
import 'package:songjiang_reader/utils/log/common.dart';

const String kStateOpen = '<sj-state>';
const String kStateClose = '</sj-state>';

/// 一轮的解析结果。
class GameplayTurn {
  const GameplayTurn({
    required this.displayText,
    this.deltas = const {},
    this.note,
    this.ended = false,
    this.advancePhase = false,
  });

  /// 剥掉状态块之后的正文（用于展示与落库）。
  final String displayText;

  /// 本回合的状态变化量。
  final Map<String, int> deltas;

  /// 本回合做了什么（一句话）。
  final String? note;

  /// 模型是否声明本局结束。
  final bool ended;

  /// 模型是否认为该进下一幕了。
  ///
  /// 分幕不再按回合数硬推：那样玩家什么都没干，三回合也自动换幕，
  /// 「幕」就只是个装饰。改成由剧情节点触发。
  final bool advancePhase;

  bool get hasChanges => deltas.isNotEmpty;
}

class GameplayRuntime {
  GameplayRuntime._();

  /// 玩法技能的插件 id。
  ///
  /// 加前缀是为了不和用户从市场装的插件撞 id——玩法技能是宿主的，
  /// 不该占掉 `com.xxx.yyy` 这类命名空间。
  static String pluginIdFor(GameplayMode mode) => 'gameplay.${mode.id}';

  /// 内置通用判定技能的工具 id。
  static const String statJudgeToolId = 'stat-judge';

  /// 这一局实际要跑的回合技能。
  ///
  /// 自定义的优先；否则看玩法有没有打开通用判定（且它真有状态量可判）。
  static String? turnToolIdFor(GameplayMode mode) {
    if (mode.turnTool != null) return mode.turnTool;
    if (mode.statJudge && mode.stats.isNotEmpty) return statJudgeToolId;
    return null;
  }

  /// 按玩法自己的状态量生成通用判定技能。
  ///
  /// 状态量的 `hint` 本来就写着「什么时候该增减」，直接拿它当判据——
  /// 不必给 15 个玩法各写一段判定提示词，也不会各写各的走偏。
  static Map<String, dynamic> buildStatJudgeSpec(GameplayMode mode) {
    final lines = <String>[
      for (final d in mode.stats)
        '- ${d.name}（${d.key}）：范围 ${d.min}~${d.max}，'
            '${d.perMember ? '按人记，键写成「${d.name}|姓名」' : '全场共享'}。'
            '${d.hint}',
    ];
    final sample = mode.stats.isEmpty ? '状态名' : mode.stats.first.name;
    return {
      'id': statJudgeToolId,
      'displayName': '状态判定',
      'description': '读这一回合的正文，判定各状态量该增减多少',
      'behavior': 'aiPrompt',
      'prompt': '你是「${mode.name}」玩法的状态判定器。'
          '读下面的角色回复，按每条状态的说明判断本回合该加减多少。\n\n'
          '状态量：\n${lines.join('\n')}\n\n'
          '当前数值：{{statsLine}}\n'
          '在场的人：{{members}}\n\n'
          '规则：\n'
          '- 只报真的发生变化的那几项；没变就不写\n'
          '- 普通互动 ±3~8，重要转折 ±10~25\n'
          '- 按人记的状态必须写成「状态名|人名」，人名只能从上面在场的人里选\n'
          '- 不要复述正文，不要解释\n\n'
          '玩家这一回合：{{playerInput}}\n'
          '角色回复：\n{{text}}\n\n'
          '只输出 JSON，例如 {"$sample": 5, "note": "一句话说明为什么"}',
    };
  }

  /// 把玩法声明的技能编译成插件清单；没声明就返回 null。
  ///
  /// 玩法原先只能给一段 [GameplayMode.directive]，写不了机制。这里让它能带：
  /// - `scriptTools`：声明式工具（复用 PluginToolSpec）
  /// - `enhancers`：开局即注入主对话的增强规则
  /// - `rules`：before_generation / after_turn 事件规则
  /// - `statJudge`：按状态量自动生成的通用判定技能
  ///
  /// 全部复用现有插件契约，不新造协议——玩法包与插件包走同一套东西。
  static PluginManifest? buildPluginManifest(GameplayMode mode) {
    final tools = <Map<String, dynamic>>[
      ...mode.scriptTools,
      if (turnToolIdFor(mode) == statJudgeToolId) buildStatJudgeSpec(mode),
    ];
    if (tools.isEmpty && mode.enhancers.isEmpty && mode.rules.isEmpty) {
      return null;
    }
    return PluginManifest.fromJson({
      'schemaVersion': '1.0',
      'id': pluginIdFor(mode),
      'name': '${mode.name} · 技能',
      'version': '1.0.0',
      'description': mode.summary,
      'author': '松江阅',
      // 声明式工具（llmChain / aiPrompt）都要调 AI；
      // 规则里带 set_storage 才申请写权限——最小授权，不白给。
      'permissions': [
        'ai.query',
        if (_needsStorageWrite(mode)) 'storage.write',
      ],
      'hooks': <Map<String, dynamic>>[],
      'tools': tools,
      'enhancers': mode.enhancers,
      'rules': mode.rules,
    });
  }

  /// 玩法规则里有没有写插件私有存储的动作。
  ///
  /// 有才申请 `storage.write`：`PluginRuleRunner` 是按 manifest 的权限放行的，
  /// 不声明就会被静默丢掉，玩法作者会以为写进去了。
  static bool _needsStorageWrite(GameplayMode mode) {
    for (final rule in mode.rules) {
      final actions = rule['actions'];
      if (actions is! List) continue;
      for (final a in actions) {
        if (a is Map && a['type']?.toString() == 'set_storage') return true;
      }
    }
    return false;
  }

  /// 跑一次玩法声明的「每回合技能」，把返回的 JSON 变成状态变化量。
  ///
  /// 意义：状态量不该由正在演戏的模型自己在正文末尾报——那等于让演员
  /// 给自己打分。挂一个独立技能去判，和判官是同一个思路。
  ///
  /// 没声明 [GameplayMode.turnTool]、或技能执行失败时返回空结果，
  /// 绝不阻断这一回合。
  static Future<GameplayTurn> runTurnTool({
    required GameplayMode mode,
    required GameplaySession session,
    required String replyText,
    List<String> members = const [],
    /// 玩家这一回合说了什么。旁观/继续演出时为空。
    ///
    /// 推理类玩法必须看这一句：海龟汤的回复只有「是/否」，光看回复判不出
    /// 玩家离汤底有多近；剧本杀也要知道玩家问的是不是关键处。
    String playerInput = '',
    /// 暗牌（剧本杀的真相 / 海龟汤的汤底）。判"离真相多远"要有对照。
    String secret = '',
  }) async {
    final toolId = turnToolIdFor(mode);
    if (toolId == null) return const GameplayTurn(displayText: '');
    if (replyText.trim().isEmpty && playerInput.trim().isEmpty) {
      return const GameplayTurn(displayText: '');
    }
    try {
      final raw = await PluginRegistry.instance.runDeclarativeTool(
        pluginIdFor(mode),
        toolId,
        {
          'text': replyText.trim(),
          'turn': session.turn,
          'stats': session.stats,
          'statsLine': [
            for (final e in session.stats.entries) '${e.key}=${e.value}',
          ].join('，'),
          'members': members.join('、'),
          // 注意别用 input 当键名：{{input}} 是模板里「整个 JSON」的保留占位符
          'playerInput': playerInput.trim(),
          'secret': secret.trim(),
        },
      );
      final turn = parseSkillOutput(raw);
      if (turn.hasChanges || turn.note != null) {
        SjLog.info(
          'Gameplay: 技能 $toolId 判定 deltas=${turn.deltas} note=${turn.note}',
        );
      }
      return turn;
    } catch (e) {
      SjLog.warning('Gameplay: 回合技能 $toolId 执行失败（已忽略）: $e');
      return const GameplayTurn(displayText: '');
    }
  }

  /// 解析技能返回的 JSON：`{"awareness": 15, "note": "一句话"}`。
  ///
  /// 允许模型在 JSON 前后带话（和判官一样的宽容度）；解析不出就返回空结果。
  static GameplayTurn parseSkillOutput(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return const GameplayTurn(displayText: '');
    }
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      if (decoded is! Map) return const GameplayTurn(displayText: '');
      final deltas = <String, int>{};
      String? note;
      decoded.forEach((k, v) {
        final key = k.toString();
        if (key == 'note') {
          final t = v?.toString().trim() ?? '';
          if (t.isNotEmpty) note = t;
          return;
        }
        final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
        // 保留 0：技能明确说「这一项没变」时，要能压掉模型自报的数值
        // （覆盖语义见 [overrideWith]）。丢掉 0 就等于技能无法否决模型。
        if (n != null) deltas[key] = n;
      });
      return GameplayTurn(displayText: '', deltas: deltas, note: note);
    } catch (e) {
      SjLog.warning('Gameplay: 技能返回不是合法 JSON: $raw ($e)');
      return const GameplayTurn(displayText: '');
    }
  }

  /// 技能的结论**覆盖**模型自报的同名项（不是相加）。
  ///
  /// 为什么不能相加：玩法开着 [GameplayMode.turnTool] 时，模型往往也会在
  /// 状态块里自己报一遍同样的状态量。两边相加就翻倍了。
  /// 技能是独立判的，比正在演戏的模型可信，所以同名项以它为准。
  ///
  /// 比较前要把键归一化：模型爱写 key（`sanity`），技能爱写名字（`神志`），
  /// 直接按字符串比会对不上，结果是两边都算一遍。
  static GameplayTurn overrideWith(
    GameplayTurn base,
    GameplayTurn skill, {
    GameplayMode? mode,
  }) {
    if (!skill.hasChanges && skill.note == null) return base;
    final nameToKey = <String, String>{
      for (final d in mode?.stats ?? const <GameplayStatDef>[]) d.name: d.key,
      for (final d in mode?.stats ?? const <GameplayStatDef>[]) d.key: d.key,
    };

    final deltas = <String, int>{};
    base.deltas.forEach((k, v) => deltas[_keyOf(k, nameToKey)] = v);
    skill.deltas.forEach((k, v) => deltas[_keyOf(k, nameToKey)] = v);

    return GameplayTurn(
      displayText: base.displayText,
      deltas: deltas,
      note: skill.note ?? base.note,
      ended: base.ended,
      advancePhase: base.advancePhase,
    );
  }

  /// 把「好感」/「好感|姬动」/`affection` 统一成 `affection` / `affection|姬动`。
  static String _keyOf(String raw, Map<String, String> nameToKey) {
    if (nameToKey.isEmpty) return raw;
    final sep = raw.indexOf('|');
    if (sep <= 0) return nameToKey[raw] ?? raw;
    final head = raw.substring(0, sep);
    final mapped = nameToKey[head];
    return mapped == null ? raw : '$mapped${raw.substring(sep)}';
  }

  /// 组装注入给模型的玩法设定。
  static String buildDirective({
    required GameplayMode mode,
    required GameplaySession session,
    List<String> members = const [],
  }) {
    final buf = StringBuffer();

    buf.writeln('## 本场玩法：${mode.name}');
    buf.writeln(mode.directive.trim());
    buf.writeln();

    if (mode.stats.isNotEmpty) {
      buf.writeln('## 可追踪状态（会随剧情变化）');
      for (final def in mode.stats) {
        if (def.perMember && members.isNotEmpty) {
          final per = session.memberStats[def.key] ?? const <String, int>{};
          final detail =
              members.map((m) => '$m ${per[m] ?? def.initial}').join('，');
          buf.writeln('- ${def.name}（${def.key}）：**按人分别记**，'
              '当前 $detail；范围 ${def.min}~${def.max}。${def.hint}');
        } else {
          final cur = session.stats[def.key] ?? def.initial;
          buf.writeln(
              '- ${def.name}（${def.key}）：当前 $cur，范围 ${def.min}~${def.max}。${def.hint}');
        }
      }
      buf.writeln();
    }

    if (mode.phases.isNotEmpty) {
      final idx = session.phaseIndex.clamp(0, mode.phases.length - 1);
      buf.writeln('## 当前进度');
      buf.writeln(
          '第 ${idx + 1} 幕 / 共 ${mode.phases.length} 幕：${mode.phases[idx]}'
          '（已进行 ${session.turn} 轮）');
      if (idx + 1 < mode.phases.length) {
        buf.writeln('这一幕演到位了就自然过渡到下一幕：${mode.phases[idx + 1]}。'
            '过渡时在状态块里加 `"next": true`，不要只靠回合数——玩家没推动剧情就该停在原地。');
      }
      buf.writeln();
    }

    if (mode.endings.isNotEmpty) {
      final nameOf = {for (final d in mode.stats) d.key: d.name};
      buf.writeln('## 收局条件（程序判定，达到就结束）');
      for (final e in mode.endings) {
        final name = nameOf[e.statKey] ?? e.statKey;
        final cond = e.atLeast != null
            ? '$name ≥ ${e.atLeast}'
            : '$name ≤ ${e.atMost}';
        buf.writeln('- $cond：${e.text}');
      }
      buf.writeln('条件没满足就继续演，**不要提前收局**；真的收局时把这一回合写完整。');
      buf.writeln();
    }

    // 已跨过的门槛：让模型知道关系/局势已经变了，别再按开局演。
    final unlocked = <String>[];
    for (var i = 0; i < mode.thresholds.length; i++) {
      if (session.stats['@t$i'] == 1) unlocked.add(mode.thresholds[i].text);
    }
    if (unlocked.isNotEmpty) {
      buf.writeln('## 已经发生的转折（不可撤回，后续按这个演）');
      for (final t in unlocked) {
        buf.writeln('- $t');
      }
      buf.writeln();
    }

    if (mode.judged) {
      buf.writeln('## 判定说明');
      buf.writeln('玩家有没有违规，由独立的判官系统判定，结论会直接结算；'
          '你**不要**在状态块里写「违规」「识破」这类判定结果，只管把后果演出来。');
      buf.writeln();
    }

    final secret = session.secret;
    if (secret != null && secret.trim().isNotEmpty) {
      buf.writeln('## 暗牌（只有你知道，绝对不能直接说出来）');
      buf.writeln(secret.trim());
      buf.writeln('对方必须靠提问与推理把它问出来。你只能在对话中给线索，'
          '不能主动交底，也不能因为对方反复追问就提前说出来。');
      buf.writeln();

      // 知情范围：没有这条，模型会让所有角色都知道真相（剧本杀就废了）
      buf.writeln(mode.secretScope == null || mode.secretScope!.trim().isEmpty
          ? '- 知情范围：默认无人知情，只有你作为叙述者掌握全貌。'
          : '- 知情范围：${mode.secretScope!.trim()}。'
              '除此之外的角色一律不知情——不得暗示、不得据此行动、不得表现出知道。');
      buf.writeln();
    }

    if (session.log.isNotEmpty) {
      buf.writeln('## 前情（最近的推进）');
      for (final e in session.log.reversed.take(5).toList().reversed) {
        buf.writeln('- 第 ${e.turn} 轮：${e.text}');
      }
      buf.writeln();
    }

    buf.writeln('## 输出要求（必须遵守）');
    if (mode.stats.isNotEmpty) {
      buf.writeln('每次回复的**最后另起一行**输出本回合的状态变化，格式：');
      buf.writeln(
          '$kStateOpen{"好感": 5, "note": "一句话说明这轮为什么变"}$kStateClose');
      buf.writeln('规则：');
      buf.writeln('- 键用上面列出的状态名，只写发生变化的那几项；全都变就都写，没变就写 `$kStateOpen{}$kStateClose`');
      buf.writeln('- 变化幅度：普通互动 ±3~8，重要转折 ±10~25');
      buf.writeln('- 这个块会被程序读取并从正文中删掉，读者看不到，所以不要解释它、不要把它写进剧情');
      buf.writeln('- 除最后这一行外，正文里不要再出现任何 `$kStateOpen` 字样');
      if (members.isNotEmpty && mode.stats.any((d) => d.perMember)) {
        final who = members.isEmpty ? '人物名' : members.first;
        buf.writeln(
            '- **按人分别记的状态**，键写成「状态名|人物名」，例如 `"好感|$who": 5`；'
            '只写「好感」会被当成全场共享的值');
      }
    }
    if (mode.endingHint != null && mode.endingHint!.trim().isNotEmpty) {
      buf.writeln(mode.endingHint!.trim());
      buf.writeln(
          '真到了收尾的时候，可以在状态块里加 `"ended": true`；'
          '但硬性结局（如神志耗尽、违规到顶）由程序按上面的条件判，不靠你自觉。');
    }

    return buf.toString().trim();
  }

  /// 从模型回复中剥离状态块并解析。
  ///
  /// [streaming] 为真表示这是流式过程中的中间文本：状态块往往只写了一半
  /// （只有 `<sj-state>` 没有闭合标签），此时**不解析、也不记日志**，
  /// 只把状态块之前的部分作为正文展示，避免每帧刷一条解析失败日志。
  static GameplayTurn parse(String raw, {bool streaming = false}) {
    final start = raw.indexOf(kStateOpen);
    if (start < 0) {
      return GameplayTurn(displayText: raw.trim());
    }
    final end = raw.indexOf(kStateClose, start);
    if (end < 0) {
      // 状态块还没写完（或模型格式不完整）：截掉它，正文照常显示
      if (!streaming) {
        SjLog.warning('GameplayRuntime: 状态块未闭合，本回合按无变化处理');
      }
      return GameplayTurn(displayText: raw.substring(0, start).trim());
    }

    final jsonText = raw.substring(start + kStateOpen.length, end);
    // 正文 = 状态块之前 + 状态块之后
    final before = raw.substring(0, start);
    final after = raw.substring(end + kStateClose.length);
    final display = (before + after).trim();

    final deltas = <String, int>{};
    String? note;
    var ended = false;
    var advancePhase = false;
    try {
      final decoded = jsonDecode(jsonText.trim());
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final key = k.toString();
          if (key == 'note') {
            final t = v?.toString().trim() ?? '';
            if (t.isNotEmpty) note = t;
            return;
          }
          if (key == 'ended') {
            ended = v == true || v?.toString() == 'true';
            return;
          }
          if (key == 'next') {
            advancePhase = v == true || v?.toString() == 'true';
            return;
          }
          final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
          if (n != null && n != 0) deltas[key] = n;
        });
      }
    } catch (e) {
      SjLog.warning('GameplayRuntime: 状态块解析失败: $jsonText ($e)');
    }

    return GameplayTurn(
      displayText: display,
      deltas: deltas,
      note: note,
      ended: ended,
      advancePhase: advancePhase,
    );
  }

  /// 把本回合的变化结算进会话状态并推进。
  ///
  /// 返回结算后的会话、**由程序判定**的结局（如果这一回合撞上了结局条件），
  /// 以及这一回合新触发的门槛事件旁白。
  /// 结局一定要在这里定：模型在状态块里写 `"ended": true` 只是建议，
  /// 它可以一直不写，玩家就永远赢不了也输不了。
  static ({
    GameplaySession session,
    GameplayEnding? ending,
    List<String> events,
  }) apply({
    required GameplayMode mode,
    required GameplaySession session,
    required GameplayTurn turn,
  }) {
    final stats = Map<String, int>.from(session.stats);
    for (final def in mode.stats) {
      stats.putIfAbsent(def.key, () => def.initial);
    }

    // 按成员的关系值：外层 key 是状态，内层是「谁 → 多少」
    final memberStats = <String, Map<String, int>>{
      for (final e in session.memberStats.entries)
        e.key: Map<String, int>.from(e.value),
    };

    // 状态名 → key（模型可能用中文名）
    final nameToKey = {
      for (final d in mode.stats) d.name: d.key,
      for (final d in mode.stats) d.key: d.key,
    };

    turn.deltas.forEach((rawKey, delta) {
      // 「好感|林黛玉」：按成员结算
      final sep = rawKey.indexOf('|');
      if (sep > 0) {
        final statPart = nameToKey[rawKey.substring(0, sep)] ??
            rawKey.substring(0, sep);
        final member = rawKey.substring(sep + 1).trim();
        final def = mode.stats.where((d) => d.key == statPart).firstOrNull;
        if (def != null && def.perMember && member.isNotEmpty) {
          final inner = memberStats.putIfAbsent(statPart, () => {});
          final cur = inner[member] ?? def.initial;
          inner[member] = (cur + delta).clamp(def.min, def.max);
          return;
        }
        // perMember 状态但没给成员名：落到下面的全场逻辑，至少不丢数据
      }

      final key = nameToKey[rawKey] ?? rawKey;
      final def = mode.stats.where((d) => d.key == key).firstOrNull;
      final current = stats[key] ?? def?.initial ?? 0;
      final next = current + delta;
      stats[key] = def == null ? next : next.clamp(def.min, def.max);
    });

    final newTurn = session.turn + 1;
    // 分幕：只在模型标记「该进下一幕」时推进，或本回合撞上结局时推到最后一幕。
    var phase = session.phaseIndex;
    if (mode.phases.isNotEmpty) {
      if (turn.advancePhase && !session.ended) {
        phase = (phase + 1).clamp(0, mode.phases.length - 1);
      }
      phase = phase.clamp(0, mode.phases.length - 1);
    }

    // 门槛事件：跨线就补一段旁白，并把「已解锁」记在 stats 的 @t 标记里，
    // 这样下一轮的设定能让模型知道关系/局势已经变了。
    final events = <String>[];
    for (var i = 0; i < mode.thresholds.length; i++) {
      final t = mode.thresholds[i];
      if (stats['@t$i'] == 1) continue;
      var hit = false;
      final def = mode.stats.where((d) => d.key == t.statKey).firstOrNull;
      if (def != null && def.perMember) {
        final inner = memberStats[t.statKey] ?? const <String, int>{};
        hit = inner.values.any(t.crossed);
      } else {
        hit = t.crossed(stats[t.statKey] ?? def?.initial ?? 0);
      }
      if (!hit) continue;
      stats['@t$i'] = 1;
      events.add(t.text);
    }

    // 结局：程序按状态阈值判，不看模型脸色
    GameplayEnding? ending;
    for (final e in mode.endings) {
      if (_endingHit(e, mode, stats, memberStats)) {
        ending = e;
        break;
      }
    }
    // 模型自己说结束了，也算——但优先级低于按状态判出来的结局
    final ended = session.ended || ending != null || turn.ended;
    if (ending != null && mode.phases.isNotEmpty) {
      phase = mode.phases.length - 1;
    }

    final log = List<GameplayEvent>.from(session.log);
    if (turn.note != null && turn.note!.isNotEmpty) {
      log.add(GameplayEvent(turn: newTurn, text: turn.note!));
    }
    // 先记过程（门槛转折），再记结果（收局）——日志读起来才是时间顺序
    for (final e in events) {
      log.add(GameplayEvent(turn: newTurn, text: e));
    }
    if (ending != null) {
      log.add(GameplayEvent(turn: newTurn, text: '本局结束：${ending.text}'));
    }
    // 只留最近 20 条，避免无限膨胀
    while (log.length > 20) {
      log.removeAt(0);
    }
    return (
      session: session.copyWith(
        stats: stats,
        memberStats: memberStats,
        turn: newTurn,
        phaseIndex: phase,
        log: log,
        ended: ended,
        updatedAt: DateTime.now(),
      ),
      ending: ending,
      events: events,
    );
  }

  /// 结局条件是否命中。
  ///
  /// 「按人对谁」的状态（恋爱里的好感）不能只看集体值——那种值本身恒为初始值，
  /// 按它判结局永远不会触发。这里改成：任一人到线就算。
  static bool _endingHit(
    GameplayEnding ending,
    GameplayMode mode,
    Map<String, int> stats,
    Map<String, Map<String, int>> memberStats,
  ) {
    final def = mode.stats.where((d) => d.key == ending.statKey).firstOrNull;
    if (def != null && def.perMember) {
      final inner = memberStats[ending.statKey] ?? const <String, int>{};
      if (inner.isEmpty) return false;
      return inner.values.any(
        (v) => ending.matches({ending.statKey: v}, initial: (_) => def.initial),
      );
    }
    return ending.matches(
      stats,
      initial: (_) => def?.initial ?? 0,
    );
  }

  /// 合并两次解析结果（模型正文一轮 + 判官判定一轮）。  ///
  /// 判官在生成回复**之前**跑，结论要先结算进本局，但回合数只该加一次，
  /// 所以把判官的 deltas 并进模型那一轮再一起 apply。
  static GameplayTurn merge(GameplayTurn base, {Map<String, int> deltas = const {}, String? note}) {
    if (deltas.isEmpty && (note == null || note.isEmpty)) return base;
    final merged = Map<String, int>.from(base.deltas);
    deltas.forEach((k, v) => merged[k] = (merged[k] ?? 0) + v);
    return GameplayTurn(
      displayText: base.displayText,
      deltas: merged,
      note: (note != null && note.isNotEmpty) ? note : base.note,
      ended: base.ended,
      advancePhase: base.advancePhase,
    );
  }

  /// 生成开局用的暗牌（剧本杀的真相 / 海龟汤的汤底）。
  ///
  /// 返回给模型的提示词；调用方拿到文本后请求模型补全。
  static String buildSetupPrompt({
    required GameplayMode mode,
    required String characterName,
    String? bookTitle,
    String? scene,
  }) {
    final buf = StringBuffer();
    buf.writeln(mode.setupPrompt!.trim());
    buf.writeln();
    buf.writeln('出场人物：$characterName'
        '${bookTitle == null || bookTitle.isEmpty ? '' : '（出自《$bookTitle》）'}');
    if (scene != null && scene.isNotEmpty) {
      buf.writeln('场景：$scene');
    }
    buf.writeln();
    buf.writeln('输出格式（必须照这个来，三个标记都要出现）：');
    buf.writeln(GameplaySetup.publicTag);
    buf.writeln('玩家一开始就该知道的事：场景/处境/摆在眼前的局面。一两句话，不要剧透真相。');
    buf.writeln(GameplaySetup.rulesTag);
    buf.writeln('这一局玩家必须遵守的硬规则，每条一行，用「1. 」开头；没有就写「无」。');
    buf.writeln(GameplaySetup.secretTag);
    buf.writeln('只有你知道的真相：凶手与手法 / 汤底 / 哪条规则是致命的，以及违反后会怎样。');
    buf.writeln();
    buf.writeln('要求：');
    buf.writeln('- 只输出这三段，不要解释、不要写对话、不要在标记外面加别的内容');
    buf.writeln('- 内容要具体到可以支撑一场追问（有人名、有细节、有可被追问的破绽）');
    buf.writeln('- 全文控制在 300 字以内');
    return buf.toString().trim();
  }
}
