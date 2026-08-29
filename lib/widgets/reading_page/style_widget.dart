import 'dart:io';

import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/models/font_model.dart';
import 'package:songjiang_reader/page/reading_page.dart';
import 'package:songjiang_reader/page/settings_page/subpage/fonts.dart';
import 'package:songjiang_reader/service/book_player/book_player_server.dart';
import 'package:songjiang_reader/service/font.dart';
import 'package:songjiang_reader/utils/font_parser.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/widgets/icon_and_text.dart';
import 'package:songjiang_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:songjiang_reader/widgets/reading_page/widget_title.dart';
import 'package:songjiang_reader/dao/theme.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/models/read_theme.dart';
import 'package:songjiang_reader/page/book_player/epub_player.dart';
import 'package:songjiang_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

enum PageTurn {
  noAnimation,
  slide,
  scroll;

  String getLabel(BuildContext context) {
    switch (this) {
      case PageTurn.noAnimation:
        return L10n.of(context).noAnimation;
      case PageTurn.slide:
        return L10n.of(context).slide;
      case PageTurn.scroll:
        return L10n.of(context).scroll;
    }
  }
}

class StyleWidget extends StatefulWidget {
  const StyleWidget({
    super.key,
    required this.themes,
    required this.epubPlayerKey,
    required this.setCurrentPage,
    required this.hideAppBarAndBottomBar,
  });

  final List<ReadTheme> themes;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function setCurrentPage;
  final Function hideAppBarAndBottomBar;

  @override
  StyleWidgetState createState() => StyleWidgetState();
}

class StyleWidgetState extends State<StyleWidget> {
  BookStyle bookStyle = Prefs().bookStyle;
  int? currentThemeId = Prefs().readTheme.id;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          widgetTitle(L10n.of(context).readingPageStyle, ReadingSettings.theme),
          sliders(),
          const SizedBox(height: 10),
          fontAndPageTurn(),
          const Divider(),
          Row(
            children: [
              Expanded(child: themeSelector()),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () {
                  widget.setCurrentPage(const BgimgSelector());
                },
                icon: const Icon(Icons.arrow_forward_ios),
                iconAlignment: IconAlignment.end,
                label: Text(L10n.of(context).readingPageStyleBackground),
              )
            ],
          ),
        ],
      ),
    );
  }

  List<FontModel> fonts() {
    Directory fontDir = getFontDir();
    List<FontModel> fontList = [
      FontModel(
        label: L10n.of(context).downloadFonts,
        name: 'download',
        path: 'download',
      ),
      FontModel(
        label: L10n.of(context).addNewFont,
        name: 'newFont',
        path: 'newFount',
      ),
      FontModel(
        label: L10n.of(context).followBook,
        name: 'book',
        path: 'book',
      ),
      FontModel(
        label: L10n.of(context).systemFont,
        name: 'system',
        path: 'system',
      ),
    ];
    // fontDir.listSync().forEach((element) {
    //   if (element is File) {
    //     fontList.add(FontModel(
    //       label: getFontNameFromFile(element),
    //       name: 'customFont' + ,
    //       path:
    //           'http://127.0.0.1:${Server().port}/fonts/${element.path.split('/').last}',
    //     ));
    //   }
    // });
    // name = 'customFont' + index
    for (int i = 0; i < fontDir.listSync().length; i++) {
      File element = fontDir.listSync()[i] as File;
      fontList.add(FontModel(
        label: getFontNameFromFile(element),
        name: 'customFont$i',
        path:
            'http://127.0.0.1:${Server().port}/fonts/${element.path.split(Platform.pathSeparator).last}',
      ));
    }

    return fontList;
  }

  Widget fontAndPageTurn() {
    FontModel? font = fonts().firstWhere(
        (element) => element.path == Prefs().font.path,
        orElse: () => FontModel(
            label: L10n.of(context).followBook, name: 'book', path: 'book'));

    Widget? leadingIcon(String name) {
      if (name == 'download') {
        return const Icon(Icons.download);
      } else if (name == 'newFont') {
        return const Icon(Icons.add);
      }
      return null;
    }

    return Row(children: [
      Expanded(
        child: DropdownMenu<PageTurn>(
          label: Text(L10n.of(context).readingPagePageTurningMethod),
          initialSelection: Prefs().pageTurnStyle,
          expandedInsets: const EdgeInsets.only(right: 5),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          onSelected: (PageTurn? value) {
            if (value != null) {
              Prefs().pageTurnStyle = value;
              epubPlayerKey.currentState!.changePageTurnStyle(value);
            }
          },
          dropdownMenuEntries: PageTurn.values
              .map((e) => DropdownMenuEntry(
                    value: e,
                    label: e.getLabel(context),
                  ))
              .toList(),
        ),
      ),
      Expanded(
        child: DropdownMenu<FontModel>(
          label: Text(L10n.of(context).font),
          expandedInsets: const EdgeInsets.only(left: 5),
          initialSelection: font,
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          onSelected: (FontModel? font) async {
            if (font == null) return;
            if (font.name == 'newFont') {
              widget.hideAppBarAndBottomBar(false);
              await importFont();
              return;
            } else if (font.name == 'download') {
              widget.hideAppBarAndBottomBar(false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const FontsSettingPage()),
              );
              return;
            } else {
              epubPlayerKey.currentState!.changeFont(font);
              Prefs().font = font;
            }
          },
          dropdownMenuEntries: fonts()
              .map((font) => DropdownMenuEntry(
                    value: font,
                    label: font.label,
                    leadingIcon: leadingIcon(font.name),
                  ))
              .toList(),
        ),
      ),
    ]);
  }

  Padding sliders() {
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: Column(
        children: [
          fontSizeSlider(),
          lineHeightAndParagraphSpacingSlider(),
        ],
      ),
    );
  }

  Row lineHeightAndParagraphSpacingSlider() {
    bool enabled = !Prefs().useBookStyles;
    return Row(
      children: [
        IconAndText(
          icon: const Icon(Icons.line_weight),
          text: L10n.of(context).readingPageLineSpacing,
        ),
        Expanded(
          child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              value: bookStyle.lineHeight,
              onChanged: enabled
                  ? (double value) {
                      setState(() {
                        bookStyle.lineHeight = value;
                        widget.epubPlayerKey.currentState!
                            .changeStyle(bookStyle);
                        Prefs().saveBookStyleToPrefs(bookStyle);
                      });
                    }
                  : null,
              min: 0,
              max: 3,
              divisions: 10,
              label: (bookStyle.lineHeight / 3 * 10).round().toString()),
        ),
        IconAndText(
          icon: const Icon(Icons.height),
          text: L10n.of(context).readingPageParagraphSpacing,
        ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: bookStyle.paragraphSpacing,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.paragraphSpacing = value;
                      widget.epubPlayerKey.currentState!.changeStyle(bookStyle);
                      Prefs().saveBookStyleToPrefs(bookStyle);
                    });
                  }
                : null,
            min: 0,
            max: 5,
            divisions: 10,
            label: (bookStyle.paragraphSpacing / 5 * 10).round().toString(),
          ),
        ),
      ],
    );
  }

  Row fontSizeSlider() {
    bool enabled = !Prefs().useBookStyles;
    return Row(
      children: [
        IconAndText(
          icon: const Icon(Icons.format_size),
          text: L10n.of(context).readingPageFontSize,
        ),
        Expanded(
          child: Slider(
            value: bookStyle.fontSize,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.fontSize = value;
                      widget.epubPlayerKey.currentState!.changeStyle(bookStyle);
                      Prefs().saveBookStyleToPrefs(bookStyle);
                    });
                  }
                : null,
            min: 0.5,
            max: 3.0,
            divisions: 25,
            label: bookStyle.fontSize.toStringAsFixed(2),
          ),
        ),
      ],
    );
  }

  /// 用户自建主题没有名字时的回退显示。
  static const String _customThemeName = '自定义';

  /// 新建主题的初始配色：取品牌「松烟」，而不是原来的中性灰黑。
  static ReadTheme _newThemeDraft() => ReadTheme(
      name: _customThemeName,
      backgroundColor: 'ff121815',
      textColor: 'ffe6ede4',
      backgroundImagePath: '');

  SizedBox themeSelector() {
    const size = 44.0;
    const paddingSize = 5.0;
    const labelHeight = 18.0;
    EdgeInsetsGeometry padding = const EdgeInsets.all(paddingSize);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: size + paddingSize * 2 + labelHeight,
      child: ListView.builder(
        itemCount: widget.themes.length + 1,
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          if (index == widget.themes.length) {
            // add a new theme
            return Padding(
              padding: padding,
              child: SizedBox(
                width: size + paddingSize * 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        padding: padding,
                        width: size,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: scheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () async {
                            final draft = _newThemeDraft();
                            int currId = await themeDao.insertTheme(draft);
                            widget.setCurrentPage(ThemeChangeWidget(
                              readTheme: draft.copyWith(id: currId),
                              setCurrentPage: widget.setCurrentPage,
                            ));
                          },
                          child: Icon(Icons.add,
                              size: size / 2, color: scheme.onSurfaceVariant),
                        )),
                    const SizedBox(height: labelHeight),
                  ],
                ),
              ),
            );
          }
          // theme list
          final theme = widget.themes[index];
          final selected = index + 1 == currentThemeId;
          final bg = Color(int.parse('0x${theme.backgroundColor}'));
          final fg = Color(int.parse('0x${theme.textColor}'));

          void openEditor() {
            setState(() {
              widget.setCurrentPage(ThemeChangeWidget(
                readTheme: theme,
                setCurrentPage: widget.setCurrentPage,
              ));
            });
          }

          return Padding(
            padding: padding,
            child: SizedBox(
              width: size + paddingSize * 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: padding,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.outlineVariant,
                        width: selected ? 3 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: scheme.primary.withAlpha(70),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                    height: size,
                    width: size,
                    child: InkWell(
                      onTap: () {
                        Prefs().saveReadThemeToPrefs(theme);
                        widget.epubPlayerKey.currentState!.changeTheme(theme);
                        setState(() {
                          currentThemeId = theme.id;
                        });
                      },
                      onSecondaryTap: openEditor,
                      onLongPress: openEditor,
                      child: Center(
                        // 用「阅」字做主题预览，比原来的 "A" 更贴合中文阅读器
                        child: Text(
                          "阅",
                          style: TextStyle(
                            color: fg,
                            fontSize: size / 2.4,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: labelHeight - 2,
                    child: Text(
                      theme.name.isNotEmpty ? theme.name : _customThemeName,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ThemeChangeWidget extends StatefulWidget {
  const ThemeChangeWidget({
    super.key,
    required this.readTheme,
    required this.setCurrentPage,
  });

  final ReadTheme readTheme;
  final Function setCurrentPage;

  @override
  State<ThemeChangeWidget> createState() => _ThemeChangeWidgetState();
}

class _ThemeChangeWidgetState extends State<ThemeChangeWidget> {
  late ReadTheme readTheme;

  @override
  void initState() {
    super.initState();
    readTheme = widget.readTheme;
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconButton(
        onPressed: () async {
          String? pickingColor =
              await showColorPickerDialog(readTheme.backgroundColor);
          if (pickingColor != '') {
            setState(() {
              readTheme.backgroundColor = pickingColor!;
            });
            themeDao.updateTheme(readTheme);
          }
        },
        icon: Icon(Icons.circle,
            size: 80,
            color: Color(int.parse('0x${readTheme.backgroundColor}'))),
      ),
      IconButton(
          onPressed: () async {
            String? pickingColor =
                await showColorPickerDialog(readTheme.textColor);
            if (pickingColor != '') {
              setState(() {
                readTheme.textColor = pickingColor!;
              });
              themeDao.updateTheme(readTheme);
            }
          },
          icon: Icon(Icons.text_fields,
              size: 60, color: Color(int.parse('0x${readTheme.textColor}')))),
      Expanded(
        child: TextButton.icon(
          onPressed: _promptRename,
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: Text(
            readTheme.name.isNotEmpty ? readTheme.name : '自定义',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      IconButton(
        onPressed: () {
          themeDao.deleteTheme(readTheme.id!);
          widget.setCurrentPage(const SizedBox(height: 1));
          // setState(() {});
        },
        icon: const Icon(
          Icons.delete,
          size: 40,
        ),
      ),
    ]);
  }

  /// 给主题起个名字（预置主题为宣纸 / 松烟 / 竹月…，自建主题可自行命名）
  Future<void> _promptRename() async {
    final controller = TextEditingController(text: readTheme.name);
    final name = await showDialog<String>(
      context: navigatorKey.currentState!.overlay!.context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('主题名称'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 8,
            decoration: const InputDecoration(hintText: '例如：夜读、竹月'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;
    setState(() {
      readTheme = readTheme.copyWith(name: name);
    });
    await themeDao.updateTheme(readTheme);
  }

  Future<String?> showColorPickerDialog(String currColor) async {
    Color pickedColor = Color(int.parse('0x$currColor'));

    await showDialog<void>(
      context: navigatorKey.currentState!.overlay!.context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: SingleChildScrollView(
            child: ColorPicker(
              hexInputBar: true,
              pickerColor: pickedColor,
              onColorChanged: (Color color) {
                pickedColor = color;
              },
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(pickedColor.value.toRadixString(16));
              },
            ),
          ],
        );
      },
    );

    return pickedColor.value.toRadixString(16);
  }
}
