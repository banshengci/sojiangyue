import 'dart:io';
import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:path_provider/path_provider.dart';

Future<Directory> getSjCacheDir() async {
  switch (SjPlatform.type) {
    case SjPlatformEnum.android:
    case SjPlatformEnum.ohos:
    case SjPlatformEnum.windows:
    case SjPlatformEnum.macos:
    case SjPlatformEnum.ios:
      return await getApplicationCacheDirectory();
  }
}
