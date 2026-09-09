import 'dart:io';

import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';
import 'package:path_provider/path_provider.dart';

// Future<Directory> getSjSharedPrefsDir() async {
//   switch(defaultTargetPlatform) {
//     case TargetPlatform.android:
//       // com.example.app/shared_prefs
//       final docPath = await getSjDocumentsPath();
//       final sharedPrefsDirPath = '${docPath.split('/app_flutter')[0]}/shared_prefs';
//       return Directory(sharedPrefsDirPath);
//     case TargetPlatform.windows:
//       return Directory("${(await getApplicationSupportDirectory()).path}\\shared_preferences.json");
//     default:
//       throw Exception('Unsupported platform');
//   }
// }

String getSharedPrefsFileName() {
  switch (SjPlatform.type) {
    case SjPlatformEnum.android:
      return 'FlutterSharedPreferences.xml';
    case SjPlatformEnum.windows:
      return 'shared_preferences.json';
    case SjPlatformEnum.macos:
    case SjPlatformEnum.ios:
      return 'com.songjiang.reader.plist';
    case SjPlatformEnum.ohos:
      return 'FlutterSharedPreferences';
  }
}

Future<File> getSjSharedPrefsFile() async {
  switch (SjPlatform.type) {
    case SjPlatformEnum.android:
      final docPath = await getSjDocumentsPath();
      final sharedPrefsDirPath =
          '${docPath.split('/app_flutter')[0]}/shared_prefs';
      return File('$sharedPrefsDirPath/${getSharedPrefsFileName()}');

    case SjPlatformEnum.windows:
      return File(
          "${(await getApplicationSupportDirectory()).path}\\${getSharedPrefsFileName()}");
    case SjPlatformEnum.macos:
      final baseDir =
          '${(await getSjDocumentsPath()).split('Documents')[0]}Library/Preferences';
      return File("$baseDir/${getSharedPrefsFileName()}");
    case SjPlatformEnum.ios:
      final baseDir =
          '${((await getApplicationDocumentsDirectory()).path).split('Documents')[0]}Library/Preferences';
      return File("$baseDir/${getSharedPrefsFileName()}");
    case SjPlatformEnum.ohos:
      final docPath = await getSjDocumentsPath();
      final sharedPrefsDirPath = '${docPath.split('/base')[0]}/preferences';
      return File('$sharedPrefsDirPath/${getSharedPrefsFileName()}');
  }
}
