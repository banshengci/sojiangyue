/// 场景卡：一次开局的舞台。
///
/// 造梦的「场景」不是玩法，而是**情境**：在哪、什么时候、正在发生什么。
/// 它决定人物开口的第一句是"你来了"还是"外面出事了"。
///
/// 刻意做得很轻：只有名字与情境，没有复杂字段——
/// 场景是给人反复复用的，字段一多就没人愿意填了。
class SceneCard {
  const SceneCard({
    this.id,
    this.bookId,
    required this.name,
    required this.premise,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;

  /// 所属书籍；null 表示跨书通用（同一本书之外的场景）。
  final int? bookId;

  /// 场景名（如「雨夜书房」）。
  final String name;

  /// 情境描述：会作为开场设定注入对话。
  final String premise;

  final DateTime createdAt;
  final DateTime updatedAt;

  SceneCard copyWith({
    int? id,
    int? bookId,
    String? name,
    String? premise,
    DateTime? updatedAt,
  }) =>
      SceneCard(
        id: id ?? this.id,
        bookId: bookId ?? this.bookId,
        name: name ?? this.name,
        premise: premise ?? this.premise,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory SceneCard.fromMap(Map<String, dynamic> map) => SceneCard(
        id: map['id'] as int?,
        bookId: map['book_id'] as int?,
        name: map['name'] as String,
        premise: map['premise'] as String,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'book_id': bookId,
        'name': name,
        'premise': premise,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
