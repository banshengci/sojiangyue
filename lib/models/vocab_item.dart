/// 生词 / 难句本条目。
class VocabItem {
  VocabItem({
    this.id,
    required this.term,
    this.gloss,
    this.bookId,
    this.bookTitle,
    this.chapter,
    required this.createTime,
    this.reviewCount = 0,
    this.lastReviewTime,
  });

  int? id;
  String term;
  String? gloss;
  int? bookId;
  String? bookTitle;
  String? chapter;
  DateTime createTime;
  int reviewCount;
  DateTime? lastReviewTime;

  factory VocabItem.fromMap(Map<String, dynamic> map) {
    return VocabItem(
      id: map['id'] as int?,
      term: map['term'] as String,
      gloss: map['gloss'] as String?,
      bookId: map['book_id'] as int?,
      bookTitle: map['book_title'] as String?,
      chapter: map['chapter'] as String?,
      createTime: DateTime.tryParse(map['create_time'] as String? ?? '') ??
          DateTime.now(),
      reviewCount: map['review_count'] as int? ?? 0,
      lastReviewTime: DateTime.tryParse(map['last_review_time'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'term': term,
      'gloss': gloss,
      'book_id': bookId,
      'book_title': bookTitle,
      'chapter': chapter,
      'create_time': createTime.toIso8601String(),
      'review_count': reviewCount,
      'last_review_time': lastReviewTime?.toIso8601String(),
    };
  }
}
