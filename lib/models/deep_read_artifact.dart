// lib/models/deep_read_artifact.dart
//
// AI 深读产物（导读 / 自测题 / 前情回顾 / 章节摘要），存在本地库
// `tb_deep_read_artifacts`，永不参与 WebDAV 同步（产品决策 #3）。
//
// 唯一键 = 书 × 章节 × 类型（见 [DeepReadDao.getByKey]）。

/// 深读产物类型。按 [Enum.name] 字符串持久化到 `kind` 列。
///
/// ⚠️ 新成员一律**追加在末尾**：持久化按 name，追加安全；插在中间会改变旧值的
/// 排序语义。读取时对未知字符串有兜底（见 [fromName]）。
enum DeepReadKind {
  /// 读前导读（整书级或章节级）。
  preview,

  /// 自测题（`content` 为题目 JSON，见 deep_read_quiz.dart）。
  quiz,

  /// 前情回顾。
  recap,

  /// 章节摘要。
  summary;

  /// 字符串 → 枚举，未知值兜底为 [DeepReadKind.preview]（不让整表崩）。
  static DeepReadKind fromName(String? name) => DeepReadKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => DeepReadKind.preview,
      );
}

/// 深读产物的一行（对应 `tb_deep_read_artifacts`）。
class DeepReadArtifact {
  const DeepReadArtifact({
    this.id,
    required this.bookId,
    this.chapterHref = '',
    this.chapterTitle,
    required this.kind,
    this.format = 'markdown',
    required this.content,
    this.model,
    this.score,
    this.total,
    this.answeredAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int bookId;

  /// 章节 href；整书级产物归一化为 `''`。
  final String chapterHref;
  final String? chapterTitle;
  final DeepReadKind kind;

  /// `markdown` | `json` | `text`。
  final String format;

  /// 唯一真源：正文或题目 JSON。
  final String content;

  /// 生成模型名（可空）。
  final String? model;

  /// 镜像列：答对题数（仅 kind = quiz）。
  final int? score;

  /// 镜像列：总题数。
  final int? total;

  /// 镜像列：最近作答时间。
  final DateTime? answeredAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  DeepReadArtifact copyWith({
    int? id,
    int? bookId,
    String? chapterHref,
    String? chapterTitle,
    DeepReadKind? kind,
    String? format,
    String? content,
    String? model,
    int? score,
    int? total,
    DateTime? answeredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      DeepReadArtifact(
        id: id ?? this.id,
        bookId: bookId ?? this.bookId,
        chapterHref: chapterHref ?? this.chapterHref,
        chapterTitle: chapterTitle ?? this.chapterTitle,
        kind: kind ?? this.kind,
        format: format ?? this.format,
        content: content ?? this.content,
        model: model ?? this.model,
        score: score ?? this.score,
        total: total ?? this.total,
        answeredAt: answeredAt ?? this.answeredAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory DeepReadArtifact.fromMap(Map<String, dynamic> map) => DeepReadArtifact(
        id: map['id'] as int?,
        bookId: (map['book_id'] as num?)?.toInt() ?? 0,
        chapterHref: map['chapter_href'] as String? ?? '',
        chapterTitle: map['chapter_title'] as String?,
        kind: DeepReadKind.fromName(map['kind'] as String?),
        format: map['format'] as String? ?? 'markdown',
        content: map['content'] as String? ?? '',
        model: map['model'] as String?,
        score: (map['score'] as num?)?.toInt(),
        total: (map['total'] as num?)?.toInt(),
        answeredAt: DateTime.tryParse(map['answered_at'] as String? ?? ''),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'chapter_href': chapterHref,
        'chapter_title': chapterTitle,
        'kind': kind.name,
        'format': format,
        'content': content,
        'model': model,
        'score': score,
        'total': total,
        'answered_at': answeredAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
