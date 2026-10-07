// lib/models/character_extras.dart
//
// 造梦补齐能力的数据模型：自设卡 / 开局模板、穿越场景、原著知识、剧情回顾。

import 'dart:convert';

/// 自设卡的两种用途。
enum SelfCardKind {
  /// 自设卡：读者自己写的一句设定、一个场面。
  selfCard('self'),

  /// 开局模板：对话开始时的情境设定，可带入角色对话。
  opening('opening');

  const SelfCardKind(this.code);

  final String code;

  static SelfCardKind fromCode(String? code) => SelfCardKind.values
      .firstWhere((k) => k.code == code, orElse: () => SelfCardKind.selfCard);
}

/// 自设卡 / 开局模板。
class SelfCard {
  const SelfCard({
    this.id,
    required this.bookId,
    this.kind = SelfCardKind.selfCard,
    required this.title,
    required this.content,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;
  final SelfCardKind kind;
  final String title;
  final String content;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  SelfCard copyWith({
    String? title,
    String? content,
    SelfCardKind? kind,
    List<String>? tags,
    DateTime? updatedAt,
  }) =>
      SelfCard(
        id: id,
        bookId: bookId,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        content: content ?? this.content,
        tags: tags ?? this.tags,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory SelfCard.fromMap(Map<String, dynamic> map) => SelfCard(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        kind: SelfCardKind.fromCode(map['kind'] as String?),
        title: map['title'] as String? ?? '',
        content: map['content'] as String? ?? '',
        tags: (map['tags'] as String? ?? '')
            .split(RegExp(r'[,，]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'kind': kind.code,
        'title': title,
        'content': content,
        'tags': tags.join(','),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 穿越场景中的一位出场人物（可来自任意一本书）。
class CrossoverMember {
  const CrossoverMember({
    required this.bookId,
    required this.characterName,
    this.bookTitle,
  });

  final int bookId;
  final String characterName;
  final String? bookTitle;

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'name': characterName,
        if (bookTitle != null) 'book': bookTitle,
      };

  factory CrossoverMember.fromJson(Map<String, dynamic> j) => CrossoverMember(
        bookId: (j['bookId'] as num?)?.toInt() ?? 0,
        characterName: j['name'] as String? ?? '',
        bookTitle: j['book'] as String?,
      );

  /// 展示用：《书名》·人物
  String get label => bookTitle == null || bookTitle!.isEmpty
      ? characterName
      : '《$bookTitle》·$characterName';
}

/// 穿越联动场景：不同书的人物同场。
class CrossoverScene {
  const CrossoverScene({
    this.id,
    required this.name,
    required this.members,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final List<CrossoverMember> members;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<String> get characterNames =>
      members.map((m) => m.characterName).toList();

  CrossoverScene copyWith({
    String? name,
    List<CrossoverMember>? members,
    String? note,
    DateTime? updatedAt,
  }) =>
      CrossoverScene(
        id: id,
        name: name ?? this.name,
        members: members ?? this.members,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory CrossoverScene.fromMap(Map<String, dynamic> map) {
    final raw = map['members'] as String? ?? '[]';
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      list = const [];
    }
    return CrossoverScene(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      members: list
          .map((e) => CrossoverMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      note: map['note'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'members': jsonEncode(members.map((m) => m.toJson()).toList()),
        if (note != null) 'note': note,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 原著知识条目（从全书抽取的可检索知识点）。
class KnowledgeItem {
  const KnowledgeItem({
    this.id,
    required this.bookId,
    required this.topic,
    required this.summary,
    this.chapter,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;
  final String topic;
  final String summary;
  final String? chapter;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory KnowledgeItem.fromMap(Map<String, dynamic> map) => KnowledgeItem(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        topic: map['topic'] as String? ?? '',
        summary: map['summary'] as String? ?? '',
        chapter: map['chapter'] as String?,
        createdAt:
            DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'topic': topic,
        'summary': summary,
        if (chapter != null) 'chapter': chapter,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// 剧情回顾（前情提要）缓存。
class StoryRecap {
  const StoryRecap({
    this.id,
    required this.bookId,
    required this.chapterIndex,
    this.chapterTitle,
    required this.content,
    required this.createdAt,
  });

  final int? id;
  final int bookId;

  /// 回顾到「第几章之前」，0 表示全书开篇前（无前情）。
  final int chapterIndex;
  final String? chapterTitle;
  final String content;
  final DateTime createdAt;

  factory StoryRecap.fromMap(Map<String, dynamic> map) => StoryRecap(
        id: map['id'] as int?,
        bookId: map['book_id'] as int,
        chapterIndex: (map['chapter_index'] as num?)?.toInt() ?? 0,
        chapterTitle: map['chapter_title'] as String?,
        content: map['content'] as String? ?? '',
        createdAt:
            DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        if (chapterTitle != null) 'chapter_title': chapterTitle,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };
}
