/// 角色卡 / 人物关系 / 世界观设定 / 世界时间线 数据模型。
///
/// 设计对齐「造梦」44 字段 schema 的子集，裁剪为读书人真正关心的字段；
/// 关系保留造梦五元组 trust / affection / powerGap / conflictPoint / hiddenAttitude。
/// 模型写法对齐既有 VocabItem：fromMap / toMap，JSON 字段做容错。

import 'dart:convert';

/// 一本书按章节切好的文本片段，供蒸馏服务逐章抽取。
class BookChapter {
  BookChapter({required this.title, required this.text});

  final String title;
  final String text;

  Map<String, dynamic> toJson() => {'title': title, 'text': text};

  factory BookChapter.fromJson(Map<String, dynamic> json) => BookChapter(
        title: json['title'] as String,
        text: json['text'] as String,
      );
}

/// 角色卡。importance 0-100 用于关系图节点大小排序。
class CharacterCard {
  CharacterCard({
    this.id,
    required this.bookId,
    required this.name,
    this.aliases,
    this.gender,
    this.role,
    this.importance = 50,
    this.personality,
    this.background,
    this.motivation,
    this.appearance,
    this.firstAppearanceChapter,
    this.description,
    this.avatarPath,
    this.source = 'ai_distill',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;
  final String name;
  final List<String>? aliases;
  final String? gender;
  final String? role;
  final int importance;
  final String? personality;
  final String? background;
  final String? motivation;
  final String? appearance;
  final String? firstAppearanceChapter;
  final String? description;

  /// 人物头像的本地文件路径（读者自己配的，可为空）。
  final String? avatarPath;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CharacterCard.fromMap(Map<String, dynamic> map) => CharacterCard(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        name: map['name'] as String,
        aliases: _parseStringList(map['aliases']),
        gender: map['gender'] as String?,
        role: map['role'] as String?,
        importance: (map['importance'] as int?) ?? 50,
        personality: map['personality'] as String?,
        background: map['background'] as String?,
        motivation: map['motivation'] as String?,
        appearance: map['appearance'] as String?,
        firstAppearanceChapter: map['first_appearance_chapter'] as String?,
        description: map['description'] as String?,
        avatarPath: map['avatar_path'] as String?,
        source: (map['source'] as String?) ?? 'ai_distill',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'name': name,
        'aliases': aliases == null ? null : jsonEncode(aliases),
        'gender': gender,
        'role': role,
        'importance': importance,
        'personality': personality,
        'background': background,
        'motivation': motivation,
        'appearance': appearance,
        'first_appearance_chapter': firstAppearanceChapter,
        'description': description,
        'avatar_path': avatarPath,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// 传 null 表示该字段不变；要清空请显式传空字符串 / 空列表。
  CharacterCard copyWith({
    String? name,
    List<String>? aliases,
    String? gender,
    String? role,
    int? importance,
    String? personality,
    String? background,
    String? motivation,
    String? appearance,
    String? firstAppearanceChapter,
    String? description,
    String? avatarPath,
    String? source,
    DateTime? updatedAt,
  }) =>
      CharacterCard(
        id: id,
        bookId: bookId,
        name: name ?? this.name,
        aliases: aliases ?? this.aliases,
        gender: gender ?? this.gender,
        role: role ?? this.role,
        importance: importance ?? this.importance,
        personality: personality ?? this.personality,
        background: background ?? this.background,
        motivation: motivation ?? this.motivation,
        appearance: appearance ?? this.appearance,
        firstAppearanceChapter:
            firstAppearanceChapter ?? this.firstAppearanceChapter,
        description: description ?? this.description,
        avatarPath: avatarPath ?? this.avatarPath,
        source: source ?? this.source,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );
}

List<String>? _parseStringList(Object? raw) {
  if (raw == null) return null;
  if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList(growable: false);
      }
    } catch (_) {
      return null;
    }
  }
  if (raw is List) {
    return raw.map((e) => e.toString()).toList(growable: false);
  }
  return null;
}

/// 人物关系。五元组沿用造梦：trust / affection / powerGap / conflictPoint / hiddenAttitude。
class CharacterRelation {
  CharacterRelation({
    this.id,
    required this.bookId,
    required this.sourceName,
    required this.targetName,
    this.relationType,
    this.trust = 0,
    this.affection = 0,
    this.powerGap = 0,
    this.conflictPoint,
    this.hiddenAttitude,
    this.note,
    this.source = 'ai_distill',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;
  final String sourceName;
  final String targetName;
  final String? relationType;
  final int trust;
  final int affection;
  final int powerGap;
  final String? conflictPoint;
  final String? hiddenAttitude;
  final String? note;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CharacterRelation.fromMap(Map<String, dynamic> map) =>
      CharacterRelation(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        sourceName: map['source_name'] as String,
        targetName: map['target_name'] as String,
        relationType: map['relation_type'] as String?,
        trust: (map['trust'] as int?) ?? 0,
        affection: (map['affection'] as int?) ?? 0,
        powerGap: (map['power_gap'] as int?) ?? 0,
        conflictPoint: map['conflict_point'] as String?,
        hiddenAttitude: map['hidden_attitude'] as String?,
        note: map['note'] as String?,
        source: (map['source'] as String?) ?? 'ai_distill',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'source_name': sourceName,
        'target_name': targetName,
        'relation_type': relationType,
        'trust': trust,
        'affection': affection,
        'power_gap': powerGap,
        'conflict_point': conflictPoint,
        'hidden_attitude': hiddenAttitude,
        'note': note,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 世界观设定（势力 / 地点 / 组织 / 概念 / 物品 / 功法等）。
class WorldSetting {
  WorldSetting({
    this.id,
    required this.bookId,
    required this.category,
    required this.name,
    this.description,
    this.source = 'ai_distill',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;
  final String category;
  final String name;
  final String? description;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WorldSetting.fromMap(Map<String, dynamic> map) => WorldSetting(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        category: map['category'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        source: (map['source'] as String?) ?? 'ai_distill',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'category': category,
        'name': name,
        'description': description,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 世界时间线事件。
class TimelineEvent {
  TimelineEvent({
    this.id,
    required this.bookId,
    this.chapter,
    required this.title,
    this.description,
    this.timeNote,
    this.source = 'ai_distill',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;
  final String? chapter;
  final String title;
  final String? description;
  final String? timeNote;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TimelineEvent.fromMap(Map<String, dynamic> map) => TimelineEvent(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        chapter: map['chapter'] as String?,
        title: map['title'] as String,
        description: map['description'] as String?,
        timeNote: map['time_note'] as String?,
        source: (map['source'] as String?) ?? 'ai_distill',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'chapter': chapter,
        'title': title,
        'description': description,
        'time_note': timeNote,
        'source': source,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
