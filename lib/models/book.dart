import 'package:songjiang_reader/utils/get_path/get_base_path.dart';

class Book {
  int id;
  String title;
  String coverPath;
  String filePath;
  String lastReadPosition;
  double readingPercentage;
  String author;
  bool isDeleted;
  String? description;
  double rating;
  int groupId;
  String? md5;
  DateTime createTime;
  DateTime updateTime;
  String? seriesName;
  double? seriesIndex;

  Book(
      {required this.id,
      required this.title,
      required this.coverPath,
      required this.filePath,
      required this.lastReadPosition,
      required this.readingPercentage,
      required this.author,
      required this.isDeleted,
      this.description,
      required this.rating,
      this.groupId = 0,
      this.md5,
      required this.createTime,
      required this.updateTime,
      this.seriesName,
      this.seriesIndex});

  factory Book.mock() {
    return Book(
      id: 1,
      title: 'Mock Book',
      coverPath: '',
      filePath: '',
      lastReadPosition: '',
      readingPercentage: 0.78,
      author: '松江阅',
      isDeleted: false,
      rating: 0,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );
  }

  String get coverFullPath {
    return getBasePath(coverPath);
  }

  String get fileFullPath {
    return getBasePath(filePath);
  }

  Map<String, Object?> toMap() {
    return {
      'title': title,
      'cover_path': coverPath,
      'file_path': filePath,
      'last_read_position': lastReadPosition,
      'reading_percentage': readingPercentage,
      'author': author,
      'is_deleted': isDeleted ? 1 : 0,
      'description': description,
      'rating': rating,
      'group_id': groupId,
      'file_md5': md5,
      'create_time': createTime.toIso8601String(),
      'update_time': updateTime.toIso8601String(),
      'series_name': seriesName,
      'series_index': seriesIndex,
    };
  }

  Book copyWith({
    int? id,
    String? title,
    String? coverPath,
    String? filePath,
    String? lastReadPosition,
    double? readingPercentage,
    String? author,
    bool? isDeleted,
    String? description,
    double? rating,
    int? groupId,
    String? md5,
    DateTime? createTime,
    DateTime? updateTime,
    String? seriesName,
    double? seriesIndex,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      coverPath: coverPath ?? this.coverPath,
      filePath: filePath ?? this.filePath,
      lastReadPosition: lastReadPosition ?? this.lastReadPosition,
      readingPercentage: readingPercentage ?? this.readingPercentage,
      author: author ?? this.author,
      isDeleted: isDeleted ?? this.isDeleted,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      groupId: groupId ?? this.groupId,
      md5: md5 ?? this.md5,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
      seriesName: seriesName ?? this.seriesName,
      seriesIndex: seriesIndex ?? this.seriesIndex,
    );
  }

  factory Book.fromDb(Map<String, dynamic> map) {
    return Book(
      id: (map['id'] as int?) ?? -1,
      title: map['title'] as String? ?? '',
      coverPath: map['cover_path'] as String? ?? '',
      filePath: map['file_path'] as String? ?? '',
      lastReadPosition: map['last_read_position'] as String? ?? '',
      readingPercentage: (map['reading_percentage'] as num?)?.toDouble() ?? 0.0,
      author: map['author'] as String? ?? '',
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      description: map['description'] as String?,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      groupId: map['group_id'] as int? ?? 0,
      md5: map['file_md5'] as String?,
      // 时间字段用 tryParse 兜底：原先用 DateTime.parse，只要有**一条**记录的
      // 时间列为空或格式异常，整个 selectNotDeleteBooks() 就会抛异常，
      // 表现为书架/搜索全部空白——一条坏数据毁掉整个书架。
      createTime: _parseDbTime(map['create_time']),
      updateTime: _parseDbTime(map['update_time']),
      seriesName: map['series_name'] as String?,
      seriesIndex: (map['series_index'] as num?)?.toDouble(),
    );
  }
}

/// 容错解析数据库里的时间列（空 / 非法格式 / 毫秒时间戳都能兜住）。
DateTime _parseDbTime(Object? value) {
  if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.tryParse(value.toString()) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
