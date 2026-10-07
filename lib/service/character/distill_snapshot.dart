// lib/service/character/distill_snapshot.dart
//
// 蒸馏快照：记录一本书「上次蒸馏过哪些内容」，用于增量蒸馏。
//
// 为什么不用原来的 DistillResumeState：它按 **切片下标** 记录已完成，
// 一旦章节增删或字数阈值调整，下标就会整体错位，导致跳过真正没蒸馏过的
// 内容（或重复蒸馏）。这里改为记录**切片内容的哈希**——内容没变就跳过，
// 内容变了才重跑，与它在书中的第几段无关。
//
// 存 SharedPreferences（与 DistillResumeState 同层），键为 distillSnapshot_<bookId>。

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一本书的蒸馏快照。
class DistillSnapshot {
  const DistillSnapshot({
    required this.hashes,
    required this.updatedAt,
    this.chunkCount = 0,
  });

  /// 上次已处理切片的内容哈希集合。
  final Set<String> hashes;
  final DateTime updatedAt;

  /// 上次蒸馏时的切片总数（用于 UI 展示"新增 N 段"）。
  final int chunkCount;

  bool get isEmpty => hashes.isEmpty;

  Map<String, dynamic> toJson() => {
        'hashes': hashes.toList(),
        'updatedAt': updatedAt.toIso8601String(),
        'chunkCount': chunkCount,
      };

  factory DistillSnapshot.fromJson(Map<String, dynamic> json) =>
      DistillSnapshot(
        hashes: (json['hashes'] as List? ?? [])
            .map((e) => e.toString())
            .toSet(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        chunkCount: (json['chunkCount'] as num?)?.toInt() ?? 0,
      );

  static final DistillSnapshot empty = DistillSnapshot(
    hashes: const <String>{},
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// 一段文本的内容指纹。
String chunkFingerprint(String text) =>
    sha1.convert(utf8.encode(text)).toString();

/// 快照读写（SharedPreferences，bookId 维度）。
///
/// [scope] 用于区分不同用途的蒸馏（人物图谱 / 原著知识 等），
/// 否则两类内容会共用一个快照导致互相误判为"已处理"。
class DistillSnapshotStore {
  static const String _prefix = 'distillSnapshot_';

  static String _key(int bookId, String scope) => '$_prefix${scope}_$bookId';

  static Future<DistillSnapshot> load(
    int bookId, {
    String scope = 'characters',
  }) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(bookId, scope));
    if (raw == null) return DistillSnapshot.empty;
    try {
      return DistillSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return DistillSnapshot.empty;
    }
  }

  static Future<void> save(
    int bookId,
    DistillSnapshot snapshot, {
    String scope = 'characters',
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key(bookId, scope), jsonEncode(snapshot.toJson()));
  }

  static Future<void> clear(int bookId, {String scope = 'characters'}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key(bookId, scope));
  }
}
