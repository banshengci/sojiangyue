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

  /// 结局判定说明（何时算结束、怎么算赢）。
  final String? endingHint;

  bool get hasRuntime =>
      stats.isNotEmpty || phases.isNotEmpty || setupPrompt != null;

  String? randomSceneHint(Random random) =>
      sceneHints.isEmpty ? null : sceneHints[random.nextInt(sceneHints.length)];
}
