import 'package:flutter/material.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';

enum PageTurningType {
  none,
  next,
  prev,
  menu,
}

Widget getPageTurningDiagram(
  BuildContext context,
  List<PageTurningType> types,
  List<int> iconPosition,
  bool selected,
  Function() onTap,
) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 100,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              selected ? Theme.of(context).colorScheme.primary : Colors.black26,
          width: 1,
        ),
      ),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
        ),
        itemBuilder: (context, index) {
          return Container(
            // 图例色原本是 Material 红/蓝/绿，与品牌调性无关；
            // 换成品牌色系内可区分的三色（松绿 / 竹青 / 松花黄），
            // 既保留"哪个色块管什么"的辨识度，也看得出是松江阅的界面。
            color: types[index] == PageTurningType.next
                ? SongJiangColors.pine.withAlpha(110)
                : types[index] == PageTurningType.prev
                    ? SongJiangColors.bamboo.withAlpha(110)
                    : types[index] == PageTurningType.menu
                        ? SongJiangColors.pollen.withAlpha(110)
                        : types[index] == PageTurningType.none
                            ? Colors.grey.withAlpha(100)
                            : Colors.white,
            child: Center(
              child: iconPosition.contains(index)
                  ? Icon(
                      index == iconPosition[0]
                          ? Icons.arrow_forward
                          : index == iconPosition[1]
                              ? Icons.arrow_back
                              : index == iconPosition[2]
                                  ? Icons.menu
                                  : null,
                      size: 10,
                    )
                  : null,
            ),
          );
        },
        itemCount: 9,
      ),
    ),
  );
}
