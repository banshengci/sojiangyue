// lib/models/gameplay_mode.dart
//
// 「玩法模式」：给角色对话套一层规则外壳。
//
// 机制参考造梦空间的类型模式包（prompts/genres/packs.yaml）的设计思想：
//   玩法包 = 提示词外壳（directive）+ 场景提示（sceneHints）
// 切换玩法时把 directive 注入对话的 system 侧设定，并从 sceneHints 里随机
// 取一个作为开局情境——同一个角色在不同玩法下会呈现完全不同的戏。
//
// 说明：本项目只借鉴其机制与玩法构思，提示词文本均为自行撰写（造梦为 AGPL-3.0）。

import 'dart:math';

import 'package:flutter/material.dart';

/// 一个玩法模式。
class GameplayMode {
  const GameplayMode({
    required this.id,
    required this.name,
    required this.icon,
    required this.summary,
    required this.directive,
    this.sceneHints = const [],
    this.tag = '',
  });

  final String id;
  final String name;
  final IconData icon;

  /// 一句话说明，展示在卡片上。
  final String summary;

  /// 注入对话的规则外壳（会拼进角色的 system 设定）。
  final String directive;

  /// 开局场景提示，开戏时随机取一条。
  final List<String> sceneHints;

  /// 分类标签（推理 / 情感 / 创作 / 氛围）。
  final String tag;

  /// 随机取一个开局场景；没有提示时返回 null。
  String? randomSceneHint(Random random) =>
      sceneHints.isEmpty ? null : sceneHints[random.nextInt(sceneHints.length)];
}
