import 'package:songjiang_reader/enums/reading_info.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'reading_info.freezed.dart';
part 'reading_info.g.dart';

@freezed
abstract class ReadingInfoSectionModel with _$ReadingInfoSectionModel {
  const factory ReadingInfoSectionModel({
    @Default(ReadingInfoEnum.none) ReadingInfoEnum left,
    @Default(ReadingInfoEnum.none) ReadingInfoEnum center,
    @Default(ReadingInfoEnum.none) ReadingInfoEnum right,
    @Default(0) double verticalMargin,
    @Default(20) double leftMargin,
    @Default(20) double rightMargin,
    @Default(10) double fontSize,
  }) = _ReadingInfoSectionModel;

  factory ReadingInfoSectionModel.fromJson(Map<String, dynamic> json) =>
      _$ReadingInfoSectionModelFromJson(json);
}

@freezed
abstract class ReadingInfoModel with _$ReadingInfoModel {
  const factory ReadingInfoModel({
    @Default(
      ReadingInfoSectionModel(
        left: ReadingInfoEnum.chapterTitle,
      ),
    )
    ReadingInfoSectionModel header,
    @Default(
      ReadingInfoSectionModel(
        left: ReadingInfoEnum.batteryAndTime,
        center: ReadingInfoEnum.chapterProgress,
        right: ReadingInfoEnum.bookProgress,
      ),
    )
    ReadingInfoSectionModel footer,
  }) = _ReadingInfoModel;

  factory ReadingInfoModel.fromJson(Map<String, dynamic> json) =>
      _$ReadingInfoModelFromJson(json);
}

/// 页眉 / 页脚对正文版心的侵占量。
///
/// 这两条是浮在正文上方的（见 `epub_player.dart` 的 `readingInfoWidget`），
/// 引擎不知道它们的存在，所以必须由这边算出高度、加到上下边距里；
/// 否则第一行字会被页眉压住——这个 bug 在只有「第 1 章」四个字时不明显，
/// 一旦用户把页脚排满三格就立刻露馅。
extension ReadingInfoSectionLayout on ReadingInfoSectionModel {
  /// 三格里是否至少有一格有内容。
  bool get hasContent =>
      left != ReadingInfoEnum.none ||
      center != ReadingInfoEnum.none ||
      right != ReadingInfoEnum.none;

  /// 这一条实际占掉的高度：字号行高 + 上下留白 + 一点点呼吸空间。
  double get reservedHeight => fontSize * 1.5 + verticalMargin + 6;
}

extension ReadingInfoModelLayout on ReadingInfoModel {
  /// 页眉占用的额外上边距（页眉三格全空时为 0）。
  double get reservedTop => header.hasContent ? header.reservedHeight : 0;

  /// 页脚占用的额外下边距。
  double get reservedBottom => footer.hasContent ? footer.reservedHeight : 0;
}
