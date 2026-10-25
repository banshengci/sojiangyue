// lib/models/character_profile.dart
//
// 角色养成档案：读者与某位书中人物之间「羁绊」的展示态。
//
// 作用域是「读者 × 角色」全局共享（产品决策 #1）：同一人物在跨书茶馆与多本书里
// 共用同一条羁绊，一份感情连续累积。因此唯一键是 [CharacterProfile.characterName]。
//
// 关键设计：档案值是**聚合结果**，真源是贡献账本 `tb_character_profile_events`
// （见 character_profile_event.dart）。账本刻意不建外键，因此即便用户清理了对话
// 连同对局行，羁绊也不会回退（产品裁定「羁绊一经获得即保留」）。

import 'dart:convert';

/// 羁绊里程碑的定义：达到 [affection] 点即解锁 [name]（[key] 用于持久化与国际化）。
class BondMilestoneDef {
  const BondMilestoneDef(this.affection, this.key, this.name);

  /// 解锁所需的最低累计好感。
  final int affection;

  /// 稳定标识（写入 JSON，供 UI 精确匹配，不随文案变化）。
  final String key;

  /// 展示名。
  final String name;
}

/// 羁绊档位表：从低到高。下标 + 1 即 [CharacterProfile.bondLevel]。
///
/// 集中在此处（§7.8 常量表），调整档位只需改这一处。
const List<BondMilestoneDef> kBondMilestones = [
  BondMilestoneDef(0, 'first_meet', '初识'),
  BondMilestoneDef(10, 'break_ice', '破冰'),
  BondMilestoneDef(30, 'heart_to_heart', '交心'),
  BondMilestoneDef(60, 'confidant', '知己'),
  BondMilestoneDef(120, 'sworn_friend', '莫逆'),
  BondMilestoneDef(240, 'soulmate', '灵魂之交'),
];

/// 一个已解锁的羁绊里程碑（`milestones` JSON 列的元素）。
class BondMilestone {
  const BondMilestone({
    required this.key,
    required this.name,
    this.affection = 0,
    this.at,
  });

  final String key;
  final String name;

  /// 解锁时的累计好感。
  final int affection;

  /// 解锁时间（可空；聚合时统一取账本的最近结算时间）。
  final DateTime? at;

  factory BondMilestone.fromJson(Map<String, dynamic> j) => BondMilestone(
        key: j['key'] as String? ?? '',
        name: j['name'] as String? ?? '',
        affection: (j['affection'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse(j['at'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'affection': affection,
        'at': at?.toIso8601String(),
      };

  /// 按累计好感推导「已解锁的里程碑列表」（从低到高）。
  ///
  /// 纯函数，无副作用，service 与 DAO 聚合共用同一口径。
  static List<BondMilestone> milestonesOf(int affection, DateTime? at) {
    final list = <BondMilestone>[];
    for (final def in kBondMilestones) {
      if (affection >= def.affection) {
        list.add(BondMilestone(
          key: def.key,
          name: def.name,
          affection: def.affection,
          at: at,
        ));
      } else {
        break;
      }
    }
    return list;
  }
}

/// 角色养成档案的一行（对应 `tb_character_profile`）。
class CharacterProfile {
  const CharacterProfile({
    this.id,
    required this.characterName,
    this.bookId,
    this.bookTitle,
    this.bondLevel = 1,
    this.affectionTotal = 0,
    this.sessionCount = 0,
    this.turnCount = 0,
    this.lastPlayedAt,
    this.milestones = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;

  /// 人物姓名，全局唯一（决策 #1）。
  final String characterName;

  /// 最近一次交互所在的书（仅展示用，可空，不参与唯一键、不建外键）。
  final int? bookId;
  final String? bookTitle;

  /// 羁绊等级（1 基）。等于 [bondLevelOf]（[affectionTotal]）的结果。
  final int bondLevel;

  /// 累计好感（账本里 `affection_delta` 之和，恒 ≥ 0 → 单调不减）。
  final int affectionTotal;

  /// 对局数（账本行数）。UI 文案只能是「对局数」，禁止写「对话数」（§7.3.2）。
  final int sessionCount;

  /// 总回合数（账本 `turn_count` 之和）。UI 文案只能是「总回合」。
  final int turnCount;

  final DateTime? lastPlayedAt;
  final List<BondMilestone> milestones;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 由累计好感推导羁绊等级（1 基，1 ~ [kBondMilestones].length）。
  static int bondLevelOf(int affection) {
    var level = 1;
    for (var i = 0; i < kBondMilestones.length; i++) {
      if (affection >= kBondMilestones[i].affection) {
        level = i + 1;
      } else {
        break;
      }
    }
    return level;
  }

  /// 距离下一档的进度（0.0 ~ 1.0）；已封顶返回 1.0。
  ///
  /// 用 [bondLevelOf]（而非可能失配的 [bondLevel] 字段）从 [affectionTotal] 现算，
  /// 保证与档位表同构。
  double progressToNextLevel() {
    final level = bondLevelOf(affectionTotal);
    if (level >= kBondMilestones.length) return 1.0;
    final current = kBondMilestones[level - 1].affection;
    final next = kBondMilestones[level].affection;
    if (next <= current) return 1.0;
    final ratio = (affectionTotal - current) / (next - current);
    return ratio.clamp(0.0, 1.0);
  }

  CharacterProfile copyWith({
    int? id,
    String? characterName,
    int? bookId,
    String? bookTitle,
    int? bondLevel,
    int? affectionTotal,
    int? sessionCount,
    int? turnCount,
    DateTime? lastPlayedAt,
    List<BondMilestone>? milestones,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      CharacterProfile(
        id: id ?? this.id,
        characterName: characterName ?? this.characterName,
        bookId: bookId ?? this.bookId,
        bookTitle: bookTitle ?? this.bookTitle,
        bondLevel: bondLevel ?? this.bondLevel,
        affectionTotal: affectionTotal ?? this.affectionTotal,
        sessionCount: sessionCount ?? this.sessionCount,
        turnCount: turnCount ?? this.turnCount,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        milestones: milestones ?? this.milestones,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory CharacterProfile.fromMap(Map<String, dynamic> map) {
    // milestones 是 JSON 列：非法 JSON / 结构异常一律兜底为空列表，
    // 不能让一行坏数据毁掉整个人物档案页（照抄 GameplaySession.fromMap 的容错）。
    List<BondMilestone> milestones = const [];
    try {
      final decoded = jsonDecode(map['milestones'] as String? ?? '{}');
      final rawItems = decoded is Map ? decoded['items'] : decoded;
      if (rawItems is List) {
        milestones = rawItems
            .whereType<Map>()
            .map((e) => BondMilestone.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {
      milestones = const [];
    }

    return CharacterProfile(
      id: map['id'] as int?,
      characterName: map['character_name'] as String? ?? '',
      bookId: (map['book_id'] as num?)?.toInt(),
      bookTitle: map['book_title'] as String?,
      bondLevel: (map['bond_level'] as num?)?.toInt() ?? 1,
      affectionTotal: (map['affection_total'] as num?)?.toInt() ?? 0,
      sessionCount: (map['session_count'] as num?)?.toInt() ?? 0,
      turnCount: (map['turn_count'] as num?)?.toInt() ?? 0,
      lastPlayedAt: DateTime.tryParse(map['last_played_at'] as String? ?? ''),
      milestones: milestones,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'character_name': characterName,
        'book_id': bookId,
        'book_title': bookTitle,
        'bond_level': bondLevel,
        'affection_total': affectionTotal,
        'session_count': sessionCount,
        'turn_count': turnCount,
        'last_played_at': lastPlayedAt?.toIso8601String(),
        'milestones':
            jsonEncode({'items': milestones.map((m) => m.toJson()).toList()}),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
