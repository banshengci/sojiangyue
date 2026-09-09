import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/bookshelf_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:songjiang_reader/widgets/common/sj_segmented_button.dart';
import 'package:songjiang_reader/widgets/settings/settings_title.dart';
import 'package:songjiang_reader/widgets/settings/simple_dialog.dart';
import 'package:songjiang_reader/widgets/settings/theme_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:songjiang_reader/widgets/settings/settings_section.dart';
import 'package:songjiang_reader/widgets/settings/settings_tile.dart';
import 'package:songjiang_reader/enums/bookshelf_folder_style.dart';

const List<Map<String, String>> languageOptions = [
  {'system': 'System'},
  {'English': 'en'},
  {'简体中文': 'zh-CN'},
  {'繁體中文': 'zh-TW'},
  {'文言文': 'zh-LZH'},
  {'Türkçe': 'tr'},
  {'Deutsch': 'de'},
  {'العربية': 'ar'},
  {'Русский': 'ru'},
  {'Français': 'fr'},
  {'Español': 'es'},
  {'Italiano': 'it'},
  {'Português': 'pt'},
  {'日本語': 'ja'},
  {'한국어': 'ko'},
  {'Română': 'ro'},
];

class AppearanceSetting extends StatefulWidget {
  const AppearanceSetting({super.key});

  @override
  State<AppearanceSetting> createState() => _AppearanceSettingState();
}

class _AppearanceSettingState extends State<AppearanceSetting> {
  @override
  Widget build(BuildContext context) {
    final languageSubtitle = AppMiscPrefs.locale == null
        ? languageOptions[0].values.first
        : languageOptions
            .firstWhere(
                (element) =>
                    element.values.first ==
                    AppMiscPrefs.locale!.languageCode +
                        (AppMiscPrefs.locale!.countryCode != null
                            ? "-${AppMiscPrefs.locale!.countryCode}"
                            : ""),
                orElse: () => languageOptions[0])
            .keys
            .first;

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsAppearanceTheme),
          tiles: [
            const CustomSettingsTile(
                child: Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: ChangeThemeMode(),
            )),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsAppearanceThemeColor),
                leading: const Icon(Icons.color_lens),
                onPressed: (context) async {
                  await showColorPickerDialog(context);
                }),
            SettingsTile.switchTile(
              title: const Text("OLED Dark Mode"),
              leading: const Icon(Icons.brightness_2),
              initialValue: ThemePrefs.trueDarkMode,
              onToggle: (bool value) {
                setState(() {
                  ThemePrefs.trueDarkMode = value;
                });
              },
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).eInkMode),
              leading: const Icon(Icons.contrast),
              initialValue: ThemePrefs.eInkMode,
              onToggle: (bool value) {
                setState(() {
                  ThemePrefs.saveThemeMode('light');
                  ThemePrefs.eInkMode = value;
                });
              },
            ),
          ],
        ),
        SettingsSection(
            title: Text(L10n.of(context).settingsAppearanceDisplay),
            tiles: [
              SettingsTile.navigation(
                  title: Text(L10n.of(context).settingsAppearanceLanguage),
                  value: Text(languageSubtitle),
                  leading: const Icon(Icons.language),
                  onPressed: (context) {
                    showLanguagePickerDialog(context);
                  }),
              SettingsTile.switchTile(
                title:
                    Text(L10n.of(context).settingsAppearanceOpenBookAnimation),
                leading: const Icon(Icons.animation),
                initialValue: BookshelfPrefs.openBookAnimation,
                onToggle: (bool value) {
                  setState(() {
                    BookshelfPrefs.openBookAnimation = value;
                  });
                },
              ),
              SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsAdvancedAutoHideBottomBar),
                leading: const Icon(Icons.vertical_align_bottom),
                initialValue: ReadingUiPrefs.autoHideBottomBar,
                onToggle: (value) {
                  ReadingUiPrefs.autoHideBottomBar = value;
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: Text(L10n.of(context).reduceVibrationFeedback),
                leading: const Icon(Icons.vibration),
                initialValue: ReadingUiPrefs.reduceVibrationFeedback,
                onToggle: (bool value) {
                  setState(() {
                    ReadingUiPrefs.reduceVibrationFeedback = value;
                  });
                },
              ),
              SettingsTile.switchTile(
                title: Text(L10n.of(context).readingPageShowActionLabels),
                leading: const Icon(Icons.subtitles_outlined),
                initialValue: ReadingUiPrefs.showActionLabels,
                onToggle: (bool value) {
                  setState(() {
                    ReadingUiPrefs.showActionLabels = value;
                  });
                },
                description:
                    Text(L10n.of(context).readingPageShowActionLabelsTips),
              ),
            ]),
        SettingsSection(
            title: Text(L10n.of(context).settingsBookshelfCover),
            tiles: [
              CustomSettingsTile(
                  child: ListTile(
                title: Text(L10n.of(context).settingsBookshelfCoverWidth),
                subtitle: Row(
                  children: [
                    Text(BookshelfPrefs.coverWidth.toStringAsFixed(0)),
                    Expanded(
                      child: Slider(
                        value: BookshelfPrefs.coverWidth,
                        onChanged: (value) {
                          setState(() {
                            BookshelfPrefs.coverWidth = value;
                          });
                        },
                        max: 260,
                        min: 80,
                        divisions: 18,
                      ),
                    ),
                  ],
                ),
              )),
              CustomSettingsTile(
                  child: ListTile(
                title: Text(L10n.of(context).settingsBookshelfFolderStyle),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SjSegmentedButton<BookshelfFolderStyle>(
                    segments: [
                      SegmentButtonItem(
                        label: L10n.of(context)
                            .settingsBookshelfFolderStyleOverlap,
                        value: BookshelfFolderStyle.stacked,
                        icon: Icon(Icons.layers),
                      ),
                      SegmentButtonItem(
                        label:
                            L10n.of(context).settingsBookshelfFolderStyleGrid,
                        value: BookshelfFolderStyle.grid2x2,
                        icon: Icon(Icons.grid_view),
                      ),
                    ],
                    selected: {BookshelfPrefs.folderStyle},
                    onSelectionChanged: (value) {
                      setState(() {
                        BookshelfPrefs.folderStyle = value.first;
                      });
                    },
                  ),
                ),
              )),
              SettingsTile.switchTile(
                title: Text(
                    L10n.of(context).settingsBookshelfDefaultCoverShowTitle),
                leading: const Icon(Icons.title),
                initialValue: BookshelfPrefs.showTitleOnDefaultCover,
                onToggle: (bool value) {
                  setState(() {
                    BookshelfPrefs.showTitleOnDefaultCover = value;
                  });
                },
              ),
              SettingsTile.switchTile(
                title: Text(
                    L10n.of(context).settingsBookshelfDefaultCoverShowAuthor),
                leading: const Icon(Icons.person),
                initialValue: BookshelfPrefs.showAuthorOnDefaultCover,
                onToggle: (bool value) {
                  setState(() {
                    BookshelfPrefs.showAuthorOnDefaultCover = value;
                  });
                },
              ),
              // SettingsTile.switchTile(
              //   title: Text(
              //       L10n.of(context).settingsAdvancedUseOriginalCoverRatio),
              //   leading: const Icon(Icons.photo_size_select_large_outlined),
              //   initialValue: Prefs().useOriginalCoverRatio,
              //   onToggle: (bool value) {
              //     setState(() {
              //       Prefs().useOriginalCoverRatio = value;
              //     });
              //   },
              // ),
            ]),
        SettingsSection(
          title: Text(L10n.of(context).settingsAppearanceBottomNavigatorShow),
          tiles: [
            SettingsTile.switchTile(
              title: Text(L10n.of(context).navBarStatistics),
              initialValue: BookshelfPrefs.bottomNavShowStatistics,
              onToggle: (bool value) {
                setState(() {
                  BookshelfPrefs.bottomNavShowStatistics = value;
                });
              },
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).navBarNotes),
              initialValue: BookshelfPrefs.bottomNavShowNote,
              onToggle: (bool value) {
                setState(() {
                  BookshelfPrefs.bottomNavShowNote = value;
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

void showLanguagePickerDialog(BuildContext context) {
  final title = L10n.of(context).settingsAppearanceLanguage;
  final saveToPrefs = AppMiscPrefs.saveLocale;

  final children = languageOptions.map((e) {
    final key = e.keys.first;
    final value = e[key]!;
    return dialogOption(key, value, saveToPrefs);
  }).toList();
  showSimpleDialog(title, saveToPrefs, children);
}

Future<void> showColorPickerDialog(BuildContext context) async {
  final currentColor = ThemePrefs.themeColor;

  Color pickedColor = currentColor;

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(L10n.of(context).settingsAppearanceThemeColor),
        content: StatefulBuilder(
          builder: (BuildContext contentContext, StateSetter setDialogState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 品牌色板快捷选择，优先呈现松江阅自己的调性
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: SongJiangColors.themePalette.map((color) {
                      final selected = pickedColor.value == color.value;
                      return GestureDetector(
                        onTap: () => setDialogState(() => pickedColor = color),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Theme.of(contentContext).colorScheme.primary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: selected
                              ? Icon(Icons.check,
                                  size: 20,
                                  color: color.computeLuminance() > 0.5
                                      ? Colors.black
                                      : Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 12),
                  ColorPicker(
                    pickerColor: pickedColor,
                    onColorChanged: (color) {
                      pickedColor = color;
                    },
                    enableAlpha: false,
                    displayThumbColor: true,
                    pickerAreaHeightPercent: 0.8,
                  ),
                ],
              ),
            );
          },
        ),
        actions: <Widget>[
          TextButton(
            child: Text(L10n.of(context).commonCancel),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: Text(L10n.of(context).commonOk),
            onPressed: () {
              ThemePrefs.saveThemeColor(pickedColor.value);
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
