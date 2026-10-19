import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

/// 页眉 / 页脚每一格能显示的内容。
///
/// 取值与参考阅读器（Legado）一致：书名 / 章节名 / 本章页码 / 本章进度 /
/// 全书进度 / 页码总数 / 时间 / 电量 / 时间+电量…
///
/// 新增取值要同时改三处：这里、`ReadingInfoL10n`、以及
/// `epub_player.dart` 的 `getWidget`——漏掉最后那个，那一格会画成空白，
/// 而设置页里看起来一切正常，属于最难查的一类。
enum ReadingInfoEnum {
  none,
  bookName,
  chapterTitle,
  chapterProgress,
  bookProgress,
  page,
  time,
  battery,
  batteryAndTime,
  timeBattery,
  timeBatteryPercent,
}

extension ReadingInfoL10n on ReadingInfoEnum {
  String getL10n(BuildContext context) {
    switch (this) {
      case ReadingInfoEnum.none:
        return L10n.of(context).commonNone;
      case ReadingInfoEnum.bookName:
        return L10n.of(context).readingPageReadingInfoBookName;
      case ReadingInfoEnum.chapterTitle:
        return L10n.of(context).readingPageReadingInfoChapterTitle;
      case ReadingInfoEnum.battery:
        return L10n.of(context).readingPageReadingInfoBattery;
      case ReadingInfoEnum.time:
        return L10n.of(context).readingPageReadingInfoTime;
      case ReadingInfoEnum.batteryAndTime:
        return L10n.of(context).readingPageReadingInfoBatteryAndTime;
      case ReadingInfoEnum.chapterProgress:
        return L10n.of(context).readingPageReadingInfoChapterProgress;
      case ReadingInfoEnum.bookProgress:
        return L10n.of(context).readingPageReadingInfoBookProgress;
      case ReadingInfoEnum.page:
        return L10n.of(context).readingPageReadingInfoPage;
      case ReadingInfoEnum.timeBattery:
        return L10n.of(context).readingPageReadingInfoTimeBattery;
      case ReadingInfoEnum.timeBatteryPercent:
        return L10n.of(context).readingPageReadingInfoTimeBatteryPercent;
    }
  }
}

extension ReadingInfoEnumJson on ReadingInfoEnum {
  String toJson() {
    return name;
  }

  static ReadingInfoEnum fromJson(String json) {
    return ReadingInfoEnum.values.firstWhere((e) => e.name == json);
  }
}
