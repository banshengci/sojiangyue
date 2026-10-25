// lib/models/reading_session.dart
//
// 一次「坐下来连续读一段」= 一条阅读会话（`tb_reading_sessions`，本地库）。
//
// 它补的是主库 `tb_reading_time`（只记「哪本书 × 哪天 × 多少秒」）缺的那半张版图：
// 会话粒度 + 进度区间。有了它才算得出「每小时读多少页」「通常几点读」「卡住的书」。
//
// 阈值（15 分钟续接）由调用方传入 [ReadingSessionDao.upsertContinueOrCreate]，
// 本模型不硬编码。百分比一律 0.0~1.0 小数，时长单位秒。

class ReadingSession {
  const ReadingSession({
    this.id,
    required this.bookId,
    required this.startedAt,
    required this.endedAt,
    this.durationSeconds = 0,
    this.startPercentage,
    this.endPercentage,
    this.chapterTitle,
    required this.createdAt,
  });

  final int? id;
  final int bookId;
  final DateTime startedAt;
  final DateTime endedAt;

  /// 本次会话的阅读时长（秒）。
  final int durationSeconds;

  /// 开始时的阅读进度（0.0 ~ 1.0）。
  final double? startPercentage;

  /// 结束时的阅读进度（0.0 ~ 1.0）。
  final double? endPercentage;

  final String? chapterTitle;
  final DateTime createdAt;

  ReadingSession copyWith({
    int? id,
    int? bookId,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    double? startPercentage,
    double? endPercentage,
    String? chapterTitle,
    DateTime? createdAt,
  }) =>
      ReadingSession(
        id: id ?? this.id,
        bookId: bookId ?? this.bookId,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        startPercentage: startPercentage ?? this.startPercentage,
        endPercentage: endPercentage ?? this.endPercentage,
        chapterTitle: chapterTitle ?? this.chapterTitle,
        createdAt: createdAt ?? this.createdAt,
      );

  factory ReadingSession.fromMap(Map<String, dynamic> map) => ReadingSession(
        id: map['id'] as int?,
        bookId: (map['book_id'] as num?)?.toInt() ?? 0,
        startedAt: DateTime.tryParse(map['started_at'] as String? ?? '') ??
            DateTime.now(),
        endedAt: DateTime.tryParse(map['ended_at'] as String? ?? '') ??
            DateTime.now(),
        durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
        startPercentage: (map['start_percentage'] as num?)?.toDouble(),
        endPercentage: (map['end_percentage'] as num?)?.toDouble(),
        chapterTitle: map['chapter_title'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'book_id': bookId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': durationSeconds,
        'start_percentage': startPercentage,
        'end_percentage': endPercentage,
        'chapter_title': chapterTitle,
        'created_at': createdAt.toIso8601String(),
      };
}
