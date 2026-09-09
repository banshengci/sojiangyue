import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/enums/page_turn_mode.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/page/reading_page.dart';
import 'package:songjiang_reader/utils/ui/status_bar.dart';
import 'package:songjiang_reader/widgets/common/sj_segmented_button.dart';
import 'package:songjiang_reader/widgets/reading_page/more_settings/page_turning/diagram.dart';
import 'package:songjiang_reader/widgets/reading_page/more_settings/page_turning/page_turn_dropdown.dart';
import 'package:songjiang_reader/widgets/reading_page/more_settings/page_turning/types_and_icons.dart';
import 'package:flutter/material.dart';

class OtherSettings extends StatefulWidget {
  const OtherSettings({super.key});

  @override
  State<OtherSettings> createState() => _OtherSettingsState();
}

class _OtherSettingsState extends State<OtherSettings> {
  @override
  Widget build(BuildContext context) {
    Widget screenTimeout() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          L10n.of(context).readingPageScreenTimeout,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        leadingAndTrailingTextStyle: TextStyle(
          fontSize: 16,
          color: Theme.of(context).textTheme.bodyLarge!.color,
        ),
        subtitle: Row(
          children: [
            Text(L10n.of(context).commonMinutes(ReadingUiPrefs.awakeTime)),
            Expanded(
              child: Slider(
                  min: 0,
                  max: 60,
                  label: ReadingUiPrefs.awakeTime.toString(),
                  value: ReadingUiPrefs.awakeTime.toDouble(),
                  onChangeEnd: (value) => setState(() {
                        readingPageKey.currentState
                            ?.setAwakeTimer(value.toInt());
                      }),
                  onChanged: (value) => setState(() {
                        ReadingUiPrefs.awakeTime = value.toInt();
                      })),
            ),
          ],
        ),
      );
    }

    ListTile fullScreen() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        trailing: Switch(
            value: ReadingUiPrefs.hideStatusBar,
            onChanged: (bool? value) => setState(() {
                  ReadingUiPrefs.saveHideStatusBar(value!);
                  if (value) {
                    hideStatusBar();
                  } else {
                    showStatusBar();
                  }
                })),
        title: Text(L10n.of(context).readingPageFullScreen),
      );
    }

    Widget pageTurningControl() {
      int currentType = ReadingStylePrefs.pageTurningType;
      ScrollController scrollController = ScrollController();
      PageTurnMode currentMode = PageTurnMode.fromCode(ReadingStylePrefs.pageTurnMode);

      return StatefulBuilder(builder: (
        BuildContext context,
        void Function(void Function()) setState,
      ) {
        void onTap(int index) {
          setState(() {
            ReadingStylePrefs.pageTurningType = index;
            currentType = index;
          });
        }

        void onModeChanged(Set<PageTurnMode> selected) {
          setState(() {
            currentMode = selected.first;
            ReadingStylePrefs.pageTurnMode = selected.first.code;
          });
        }

        void onCustomConfigChanged(int index, PageTurningType type) {
          List<int> config = ReadingStylePrefs.customPageTurnConfig;
          config[index] = type.index;
          ReadingStylePrefs.customPageTurnConfig = config;
        }

        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).readingPagePageTurningMethod,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              SjSegmentedButton<PageTurnMode>(
                segments: [
                  SegmentButtonItem(
                    value: PageTurnMode.simple,
                    label: L10n.of(context).pageTurnModeSimple,
                  ),
                  SegmentButtonItem(
                    value: PageTurnMode.custom,
                    label: L10n.of(context).pageTurnModeCustom,
                  ),
                ],
                selected: {currentMode},
                onSelectionChanged: onModeChanged,
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              if (currentMode == PageTurnMode.simple) ...[
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: pageTurningTypes.length,
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: getPageTurningDiagram(
                          context,
                          pageTurningTypes[index],
                          pageTurningIcons[index],
                          currentType == index,
                          () {
                            onTap(index);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                Text(
                  L10n.of(context).customPageTurnConfig,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    for (int row = 0; row < 3; row++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            for (int col = 0; col < 3; col++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: col < 2 ? 8.0 : 0,
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      int index = row * 3 + col;
                                      List<int> config =
                                          ReadingStylePrefs.customPageTurnConfig;
                                      return PageTurnDropdown(
                                        value: PageTurningType
                                            .values[config[index]],
                                        onChanged: (type) {
                                          if (type != null) {
                                            setState(() {
                                              onCustomConfigChanged(
                                                  index, type);
                                            });
                                          }
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      });
    }

    Widget autoTranslateSelection() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        trailing: Switch(
          value: ReadingUiPrefs.autoTranslateSelection,
          onChanged: (bool value) => setState(() {
            ReadingUiPrefs.autoTranslateSelection = value;
          }),
        ),
        title: Text(L10n.of(context).readingPageAutoTranslateSelection),
      );
    }

    ListTile autoSummaryPreviousContent() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageAutoSummaryPreviousContent),
        trailing: Switch(
          value: ReadingUiPrefs.autoSummaryPreviousContent,
          onChanged: (bool value) => setState(() {
            ReadingUiPrefs.autoSummaryPreviousContent = value;
          }),
        ),
      );
    }

    Widget autoMarkSelection() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        trailing: Switch(
          value: ReadingUiPrefs.autoMarkSelection,
          onChanged: (bool value) => setState(() {
            ReadingUiPrefs.autoMarkSelection = value;
          }),
        ),
        title: Text(L10n.of(context).readingPageAutoMarkSelection),
        subtitle: Text(L10n.of(context).readingPageAutoMarkSelectionTips),
      );
    }

    ListTile autoAdjustReadingTheme() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageAutoAdjustReadingTheme),
        subtitle: Text(L10n.of(context).readingPageAutoAdjustReadingThemeTips),
        trailing: Switch(
          value: ThemePrefs.autoAdjustReadingTheme,
          onChanged: (bool value) => setState(() {
            ThemePrefs.autoAdjustReadingTheme = value;
          }),
        ),
      );
    }

    ListTile keyboardTurnPage() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageVolumeKeyTurnPage),
        trailing: Switch(
          value: ReadingUiPrefs.volumeKeyTurnPage,
          onChanged: (bool value) => setState(() {
            ReadingUiPrefs.volumeKeyTurnPage = value;
          }),
        ),
      );
    }

    ListTile swapPageTurnArea() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageSwapPageTurnArea),
        subtitle: Text(L10n.of(context).readingPageSwapPageTurnAreaTips),
        trailing: Switch(
          value: ReadingUiPrefs.swapPageTurnArea,
          onChanged: (bool value) => setState(() {
            ReadingUiPrefs.swapPageTurnArea = value;
          }),
        ),
      );
    }

    ListTile showMenuOnHover() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageShowMenuOnHover),
        subtitle: Text(L10n.of(context).readingPageShowMenuOnHoverTips),
        trailing: Switch(
          value: ReadingUiPrefs.showMenuOnHover,
          onChanged: (bool value) => setState(() {
            ReadingUiPrefs.showMenuOnHover = value;
          }),
        ),
      );
    }

    ListTile keyboardShortcutTurnPage() {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(L10n.of(context).readingPageKeyboardShortcutTurnPage),
        subtitle:
            Text(L10n.of(context).readingPageKeyboardShortcutTurnPageTips),
        trailing: Switch(
          value: ReadingUiPrefs.keyboardShortcutTurnPage,
          onChanged: (bool value) => setState(() {
            ReadingUiPrefs.keyboardShortcutTurnPage = value;
          }),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          fullScreen(),
          if (SjPlatform.isAndroid) keyboardTurnPage(),
          // if (PageTurnMode.fromCode(ReadingStylePrefs.pageTurnMode) ==
          //     PageTurnMode.simple)
          swapPageTurnArea(),
          showMenuOnHover(),
          if (SjPlatform.isDesktop) keyboardShortcutTurnPage(),
          autoAdjustReadingTheme(),
          autoTranslateSelection(),
          autoMarkSelection(),
          autoSummaryPreviousContent(),
          screenTimeout(),
          pageTurningControl(),
        ],
      ),
    );
  }
}
