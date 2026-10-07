// lib/page/character/character_avatar.dart
//
// 人物头像的统一展示：配过图就显示图，否则回退成姓名首字。
//
// 头像文件是否存在要实时判断——用户可能在系统里删掉了图片，
// 直接读不存在的路径会抛异常。

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';

/// 头像文件存在性缓存。
///
/// 列表页每帧都要渲染头像，直接 existsSync 会变成每帧几十次同步 IO，
/// 滚动时明显卡顿。路径一旦写入就不会复用（文件名带时间戳），
/// 所以按路径缓存结果是安全的。
final Map<String, bool> _avatarExistsCache = {};

bool _avatarExists(String path) =>
    _avatarExistsCache.putIfAbsent(path, () => File(path).existsSync());

/// 图片被替换/删除后清一下缓存（编辑页保存新头像时调用）。
void invalidateAvatarCache() => _avatarExistsCache.clear();

Widget characterAvatar(
  CharacterCard card,
  SjColors c, {
  double radius = 20,
}) {
  final path = card.avatarPath;
  if (path != null && path.trim().isNotEmpty && _avatarExists(path)) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: FileImage(File(path)),
    );
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: c.frost,
    child: Text(
      card.name.isNotEmpty ? card.name[0] : '?',
      style: TextStyle(color: c.ink),
    ),
  );
}
