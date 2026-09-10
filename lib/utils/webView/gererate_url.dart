import 'dart:convert';

import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/bgimg_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/models/read_theme.dart';
import 'package:songjiang_reader/service/book_player/book_player_server.dart';
import 'package:songjiang_reader/utils/js/convert_dart_color_to_js.dart';

String generateUrl(
  String url,
  String cfi, {
  BookStyle? bookStyle,
  int? textIndent,
  String? textColor,
  String? fontName,
  String? fontPath,
  String? backgroundColor,
  bool? importing,
  bool isDarkMode = false,
  double safeTop = 0,
  double safeBottom = 0,
}) {
  String indexHtmlPath =
      "http://127.0.0.1:${Server().port}/foliate-js/index.html";

  ReadTheme readTheme = AppMiscPrefs.readTheme;
  bookStyle ??= ReadingStylePrefs.bookStyle;
  textColor ??= readTheme.textColor;
  fontName ??= AppMiscPrefs.font.name;
  fontPath ??= AppMiscPrefs.font.path;
  backgroundColor ??= readTheme.backgroundColor;
  importing ??= false;

  textColor = convertDartColorToJs(textColor);
  backgroundColor = convertDartColorToJs(backgroundColor);

  // Get effective background image URL using the new method
  String bgimgUrl = BgimgPrefs.bgimg.getEffectiveUrl(
        isDarkMode: isDarkMode,
        autoAdjust: ThemePrefs.autoAdjustReadingTheme,
      );
  // const importing = $importing
  // const url = '${replaceSingleQuote(url)}'
  // let initialCfi = '${replaceSingleQuote(cfi)}'
  // let style = {
  //     fontSize: ${bookStyle.fontSize},
  //     fontName: '${replaceSingleQuote(fontName)}',
  //     fontPath: '${replaceSingleQuote(fontPath)}',
  //     fontWeight: ${bookStyle.fontWeight},
  //     letterSpacing: ${bookStyle.letterSpacing},
  //     spacing: ${bookStyle.lineHeight},
  //     paragraphSpacing: ${bookStyle.paragraphSpacing},
  //     textIndent: ${bookStyle.indent},
  //     fontColor: '#$textColor',
  //     backgroundColor: '#$backgroundColor',
  //     topMargin: ${bookStyle.topMargin},
  //     bottomMargin: ${bookStyle.bottomMargin},
  //     sideMargin: ${bookStyle.sideMargin},
  //     justify: true,
  //     hyphenate: true,
  //     pageTurnStyle: '${ReadingStylePrefs.pageTurnStyle.name}',
  //     maxColumnCount: ${bookStyle.maxColumnCount},
  // }

  // let readingRules = {
  //   convertChineseMode: '${ReadingStylePrefs.readingRules.convertChineseMode.name}',
  //   bionicReadingMode: ${ReadingStylePrefs.readingRules.bionicReading},
  // }

  Map<String, dynamic> style = {
    'fontSize': bookStyle.fontSize,
    'fontName': fontName,
    'fontPath': fontPath,
    'fontWeight': bookStyle.fontWeight,
    'letterSpacing': bookStyle.letterSpacing,
    'spacing': bookStyle.lineHeight,
    'paragraphSpacing': bookStyle.paragraphSpacing,
    'textIndent': bookStyle.indent,
    'fontColor': '#$textColor',
    'backgroundColor': '#$backgroundColor',
    'topMargin': bookStyle.topMargin + safeTop,
    'bottomMargin': bookStyle.bottomMargin + safeBottom,
    'sideMargin': bookStyle.sideMargin,
    'justify': true,
    'hyphenate': false,
    'pageTurnStyle': ReadingStylePrefs.pageTurnStyle.name,
    'maxColumnCount': bookStyle.maxColumnCount,
    'columnThreshold': bookStyle.columnThreshold,
    'writingMode': ReadingStylePrefs.writingMode.code,
    'textAlign': ReadingStylePrefs.textAlignment.code,
    'backgroundImage': bgimgUrl,
    'bgimgBlur': BgimgPrefs.bgimg.blur,
    'bgimgOpacity': BgimgPrefs.bgimg.opacity,
    'bgimgFit': BgimgPrefs.fit.code,
    'allowScript': ReadingUiPrefs.enableJsForEpub,
    'customCSS': ReadingUiPrefs.customCss,
    'customCSSEnabled': ReadingUiPrefs.customCssEnabled,
    'useBookStyles': ReadingStylePrefs.useBookStyles,
    'headingFontSize': bookStyle.headingFontSize,
    'codeHighlightTheme': ReadingUiPrefs.codeHighlightTheme.code,
  };

  Map<String, dynamic> readingRules = {
    'convertChineseMode': ReadingStylePrefs.readingRules.convertChineseMode.name,
    'bionicReadingMode': ReadingStylePrefs.readingRules.bionicReading,
  };

  Map<String, dynamic> params = {
    'importing': importing,
    'url': url,
    'initialCfi': cfi,
    'style': style,
    'readingRules': readingRules,
  };

  String query = '';

  for (var key in params.keys) {
    query += '$key=${Uri.encodeComponent(jsonEncode(params[key]))}&';
  }
  //remove last &
  query = query.substring(0, query.length - 1);

  // query += 'importing=$importing';
  // query += '&url=$url';
  // query += '&initialCfi=$cfi';
  // query += '&style=$style';
  // query += '&readingRules=$readingRules';
  // query += '&style=$style';
  // query += '&readingRules=$readingRules';

  final uri = '$indexHtmlPath?$query';

  return uri;
}
