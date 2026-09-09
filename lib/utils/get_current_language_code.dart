import 'dart:io';
import 'package:songjiang_reader/config/app_misc_prefs.dart';

String getCurrentLanguageCode() {
  String? locale = AppMiscPrefs.locale?.toLanguageTag();

  locale ??= Platform.localeName;

  if (locale.startsWith('zh_Hans') || locale.startsWith('zh-CN')) {
    return 'zh-CN';
  } else if (locale.startsWith('zh_Hant') ||
      locale.startsWith('zh-TW') ||
      locale.startsWith('zh-HK')) {
    return 'zh-TW';
  } else {
    return Platform.localeName.split('_')[0];
  }
}
