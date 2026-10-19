import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/enums/page_turn.dart';
import 'package:songjiang_reader/enums/reading_info.dart';
import 'package:songjiang_reader/models/reading_info.dart';

/// 页眉 / 页脚与翻页方式里那些「算错、漏掉也看不出来」的地方。
///
/// 这两块的风险不在 UI：三格里错一格，用户看到的是「设置没生效」；
/// 占位高度算少了，字被压在页眉底下；枚举表漏一个值，用户一选就崩。
void main() {
  group('页眉页脚占位', () {
    test('三格全空就不占位', () {
      const section = ReadingInfoSectionModel();
      expect(section.hasContent, isFalse);
      expect(
        const ReadingInfoModel(header: section, footer: section).reservedTop,
        0,
      );
    });

    test('任一格有内容就要按字号与留白留出高度', () {
      const section = ReadingInfoSectionModel(
        right: ReadingInfoEnum.page,
        fontSize: 12,
        verticalMargin: 4,
      );
      expect(section.hasContent, isTrue);
      // 12 * 1.5 + 4 + 6 = 28
      expect(section.reservedHeight, 28);
    });

    test('页眉和页脚各自独立结算', () {
      const model = ReadingInfoModel(
        header: ReadingInfoSectionModel(fontSize: 10),
        footer: ReadingInfoSectionModel(
          left: ReadingInfoEnum.page,
          fontSize: 10,
        ),
      );
      expect(model.reservedTop, 0, reason: '页眉三格全空，不该留上边距');
      expect(model.reservedTop, isNot(model.reservedBottom));
      expect(model.reservedBottom, 21);
    });
  });

  group('阅读信息取值', () {
    test('每个取值都能走一遍 JSON 往返', () {
      // reading_info.g.dart 里手写补充的枚举表若漏掉一个取值，
      // toJson 会抛 null check，用户一选那一格就崩。这里全部走一遍。
      for (final kind in ReadingInfoEnum.values) {
        final json = ReadingInfoSectionModel(left: kind).toJson();
        final back = ReadingInfoSectionModel.fromJson(json);
        expect(back.left, kind, reason: '取值 $kind 往返后变了');
      }
    });

    test('新增的四种取值没有被漏下', () {
      expect(
        ReadingInfoEnum.values,
        containsAll(<ReadingInfoEnum>[
          ReadingInfoEnum.bookName,
          ReadingInfoEnum.page,
          ReadingInfoEnum.timeBattery,
          ReadingInfoEnum.timeBatteryPercent,
        ]),
      );
    });
  });

  group('翻页方式', () {
    test('五种方式都在，顺序与参考实现一致', () {
      expect(PageTurn.values, <PageTurn>[
        PageTurn.cover,
        PageTurn.slide,
        PageTurn.simulation,
        PageTurn.scroll,
        PageTurn.noAnimation,
      ]);
    });

    test('只有覆盖与仿真由 Flutter 侧接管过渡', () {
      final driven =
          PageTurn.values.where((e) => e.isFlutterDriven).toSet();
      expect(driven, <PageTurn>{PageTurn.cover, PageTurn.simulation});
    });

    test('接管范围内的两档必须分页，不能是滚动流', () {
      // 滚动流没有「一页」的概念，截图过渡会露馅。
      for (final turn in PageTurn.values.where((e) => e.isFlutterDriven)) {
        expect(turn, isNot(PageTurn.scroll));
      }
    });
  });
}
