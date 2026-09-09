import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/models/book_style.dart';
import 'package:songjiang_reader/models/read_theme.dart';
import 'package:songjiang_reader/utils/js/convert_dart_color_to_js.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Future<void> webviewInitialVariable(
  InAppWebViewController controller,
  String url,
  String cfi, {
  BookStyle? bookStyle,
  int? textIndent,
  String? textColor,
  String? fontName,
  String? fontPath,
  String? backgroundColor,
  bool? importing,
}) async {
  ReadTheme readTheme = AppMiscPrefs.readTheme;
  bookStyle ??= ReadingStylePrefs.bookStyle;
  textColor ??= readTheme.textColor;
  fontName ??= AppMiscPrefs.font.name;
  fontPath ??= AppMiscPrefs.font.path;
  backgroundColor ??= readTheme.backgroundColor;
  importing ??= false;

  textColor = convertDartColorToJs(textColor);
  backgroundColor = convertDartColorToJs(backgroundColor);

  String replaceSingleQuote(String value) {
    return value.replaceAll("'", "\\'");
  }

  final script = '''
      const importing = $importing
      const url = '${replaceSingleQuote(url)}'
      let initialCfi = '${replaceSingleQuote(cfi)}'
      let style = {
          fontSize: ${bookStyle.fontSize},
          fontName: '${replaceSingleQuote(fontName)}',
          fontPath: '${replaceSingleQuote(fontPath)}',
          fontWeight: ${bookStyle.fontWeight},
          letterSpacing: ${bookStyle.letterSpacing},
          spacing: ${bookStyle.lineHeight},
          paragraphSpacing: ${bookStyle.paragraphSpacing},
          textIndent: ${bookStyle.indent},
          fontColor: '#$textColor',
          backgroundColor: '#$backgroundColor',
          topMargin: ${bookStyle.topMargin},
          bottomMargin: ${bookStyle.bottomMargin},
          sideMargin: ${bookStyle.sideMargin},
          justify: true,
          hyphenate: true,
          pageTurnStyle: '${ReadingStylePrefs.pageTurnStyle.name}',
          maxColumnCount: ${bookStyle.maxColumnCount},
      }
      let readingRules = {
        convertChineseMode: '${ReadingStylePrefs.readingRules.convertChineseMode.name}',
        bionicReadingMode: ${ReadingStylePrefs.readingRules.bionicReading},
      }

      window.loadBook()
  ''';

  await controller.evaluateJavascript(source: script);
}
