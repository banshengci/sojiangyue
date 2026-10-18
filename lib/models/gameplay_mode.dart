// lib/models/gameplay_mode.dart
//
// 「玩法模式」：一场带状态与判定的戏，而不只是一段提示词。
//
// 设计取舍（为什么不照搬造梦的 packs.yaml）
// 造梦的类型包 = directive + scene_hints，本质是「换一段提示词」。那样做出来
// 的玩法只有壳：没有状态、没有推进、没有输赢，玩两轮就散了。
//
// 这里把它升级成一个**玩法运行时**：
//   1. 玩法自带「状态量」（好感度 / 线索 / 怀疑度 / 回合…），对话过程中会变；
//   2. 玩法可以分「幕」，按回合推进；
//   3. 玩法可以持有「暗牌」（剧本杀的真相、海龟汤的汤底）——只给模型看，
//      不给用户看，用户要靠对话把它问出来；
//   4. 玩法可以有结局判定。
//
// 状态变更是由模型在回复尾部输出一个状态块来驱动的（见 GameplayRuntime），
// 因此玩家能真切看到「刚才那句话让好感掉了 5」。

import 'dart:math';

import 'package:flutter/material.dart';

/// 玩法模式里可用的图标名 → IconData 映射。
///
/// 玩法包是纯数据（JSON），没法直接写 IconData，所以用名字引用图标。
/// 认不出的名字回退成一个中性图标——缺图标不该让整包装不上。
const Map<String, IconData> kGameplayIconNames = {
  'search': Icons.search_outlined,
  'theater': Icons.theater_comedy_outlined,
  'heart': Icons.favorite_border,
  'mail': Icons.mail_outline,
  'debate': Icons.forum_outlined,
  'book': Icons.menu_book_outlined,
  'gift': Icons.card_giftcard_outlined,
  'group': Icons.groups_outlined,
  'castle': Icons.castle_outlined,
  'forest': Icons.forest_outlined,
  'swords': Icons.gavel_outlined,
  'crown': Icons.workspace_premium_outlined,
  'school': Icons.school_outlined,
  'business': Icons.business_center_outlined,
  'rocket': Icons.rocket_launch_outlined,
  'potion': Icons.science_outlined,
  'compass': Icons.explore_outlined,
  'ghost': Icons.visibility_outlined,
};

IconData gameplayIconByName(String? name) =>
    kGameplayIconNames[name] ?? Icons.auto_awesome_outlined;

/// 把 IconData 反查成名字（导出玩法包时用）；找不到就退回 'search'。
String gameplayIconNameOf(IconData icon) {
  for (final e in kGameplayIconNames.entries) {
    if (e.value.codePoint == icon.codePoint) return e.key;
  }
  return 'search';
}

/// 一个可追踪的状态量定义。
class GameplayStatDef {
  const GameplayStatDef({
    required this.key,
    required this.name,
    this.initial = 0,
    this.min = 0,
    this.max = 100,
    this.hint = '',
    this.isScore = false,
    this.perMember = false,
  });

  final String key;
  final String name;
  final int initial;
  final int min;
  final int max;

  /// 给模型看的说明：这个值代表什么、什么时候该增减。
  final String hint;

  /// 是否作为「胜负分」展示（会突出显示）。
  final bool isScore;

  /// 是否**按成员**分别记录（如「好感」：对谁都不同）。
  ///
  /// 线索、神志这类天生是集体的值保持 false；
  /// 群聊场景里，perMember 的值会以「好感|林黛玉」的形式出现在状态块中。
  final bool perMember;

  factory GameplayStatDef.fromJson(Map<String, dynamic> j) => GameplayStatDef(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? j['key'] ?? '').toString(),
        initial: (j['initial'] as num?)?.toInt() ?? 0,
        min: (j['min'] as num?)?.toInt() ?? 0,
        max: (j['max'] as num?)?.toInt() ?? 100,
        hint: (j['hint'] ?? '').toString(),
        isScore: j['isScore'] == true,
        perMember: j['perMember'] == true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'initial': initial,
        'min': min,
        'max': max,
        if (hint.isNotEmpty) 'hint': hint,
        if (isScore) 'isScore': true,
        if (perMember) 'perMember': true,
      };
}

/// 一场玩法。
class GameplayMode {
  const GameplayMode({
    required this.id,
    required this.name,
    required this.icon,
    required this.summary,
    required this.directive,
    this.sceneHints = const [],
    this.tag = '',
    this.stats = const [],
    this.phases = const [],
    this.setupPrompt,
    this.endingHint,
    this.secretLabel,
    this.secretScope,
  });

  final String id;
  final String name;
  final IconData icon;

  /// 一句话说明，展示在卡片上。
  final String summary;

  /// 规则外壳：本场的基调与硬约束。
  final String directive;

  /// 开局场景提示，开戏时随机取一条。
  final List<String> sceneHints;

  /// 分类标签。
  final String tag;

  /// 可追踪的状态量。
  final List<GameplayStatDef> stats;

  /// 分幕名（按回合推进）；为空表示不分幕。
  final List<String> phases;

  /// 开局前先让模型生成的「暗牌」指令。
  ///
  /// 例如剧本杀要先生成案件真相、海龟汤要先生成汤底。生成结果只给模型看。
  final String? setupPrompt;

  /// 暗牌的展示名（如「本案真相」「汤底」），用于对局结束后的揭晓。
  final String? secretLabel;

  /// 知情范围：谁有资格知道暗牌（一句话描述，如「只有凶手本人与其主使」）。
  ///
  /// 没有它，模型会让所有角色都知道真相——剧本杀就废了。
  final String? secretScope;

  /// 结局判定说明（何时算结束、怎么算赢）。
  final String? endingHint;

  bool get hasRuntime =>
      stats.isNotEmpty || phases.isNotEmpty || setupPrompt != null;

  String? randomSceneHint(Random random) =>
      sceneHints.isEmpty ? null : sceneHints[random.nextInt(sceneHints.length)];

  /// 从玩法包里的 JSON 还原一个玩法。
  ///
  /// 这是「玩法可以安装」的前提：玩法包是纯数据，必须能变成运行时的
  /// [GameplayMode] 才能开一局。缺 id 或 directive 的包直接判非法——
  /// 没有规则外壳的玩法开出来只是个空壳。
  factory GameplayMode.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString().trim();
    final directive = (j['directive'] ?? '').toString().trim();
    if (id.isEmpty) throw FormatException('玩法缺少 id');
    if (directive.isEmpty) throw FormatException('玩法 $id 缺少 directive');
    return GameplayMode(
      id: id,
      name: (j['name'] ?? id).toString(),
      icon: gameplayIconByName(j['icon'] as String?),
      summary: (j['summary'] ?? '').toString(),
      directive: directive,
      sceneHints: ((j['sceneHints'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      tag: (j['tag'] ?? '').toString(),
      stats: ((j['stats'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => GameplayStatDef.fromJson(e.cast<String, dynamic>()))
          .where((s) => s.key.isNotEmpty)
          .toList(),
      phases: ((j['phases'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      setupPrompt: (j['setupPrompt'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['setupPrompt'] as String?,
      secretLabel: (j['secretLabel'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['secretLabel'] as String?,
      secretScope: (j['secretScope'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['secretScope'] as String?,
      endingHint: (j['endingHint'] as String?)?.trim().isEmpty ?? true
          ? null
          : j['endingHint'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': gameplayIconNameOf(icon),
        'summary': summary,
        'tag': tag,
        'directive': directive,
        if (sceneHints.isNotEmpty) 'sceneHints': sceneHints,
        if (stats.isNotEmpty) 'stats': stats.map((s) => s.toJson()).toList(),
        if (phases.isNotEmpty) 'phases': phases,
        if (setupPrompt != null) 'setupPrompt': setupPrompt,
        if (secretLabel != null) 'secretLabel': secretLabel,
        if (secretScope != null) 'secretScope': secretScope,
        if (endingHint != null) 'endingHint': endingHint,
      };
}
