import 'dart:io';
import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:path_provider/path_provider.dart' as path;
import 'package:permission_handler/permission_handler.dart';

// from localsend
Future<String> getDownloadPath() async {
  switch (SjPlatform.type) {
    case SjPlatformEnum.android:
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        await Permission.manageExternalStorage.request();
      }
      return '/storage/emulated/0/Download';
    case SjPlatformEnum.ios:
      return (await path.getApplicationDocumentsDirectory()).path;
    case SjPlatformEnum.macos:
    case SjPlatformEnum.windows:
    case SjPlatformEnum.ohos:
      var downloadDir = await path.getDownloadsDirectory();
      if (downloadDir == null) {
        if (SjPlatform.isWindows) {
          downloadDir =
              Directory('${Platform.environment['HOMEPATH']}/Downloads');
          if (!downloadDir.existsSync()) {
            downloadDir = Directory(Platform.environment['HOMEPATH']!);
          }
        } else {
          downloadDir = Directory('${Platform.environment['HOME']}/Downloads');
          if (!downloadDir.existsSync()) {
            downloadDir = Directory(Platform.environment['HOME']!);
          }
        }
      }
      return downloadDir.path.replaceAll('\\', '/');
  }
}
