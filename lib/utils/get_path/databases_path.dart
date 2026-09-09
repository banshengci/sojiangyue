import 'dart:io';
import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:sqflite/sqflite.dart';

import 'get_base_path.dart';

Future<String> getSjDatabasesPath() async {
  switch (SjPlatform.type) {
    case SjPlatformEnum.android:
    case SjPlatformEnum.ohos:
      final path = await getDatabasesPath();
      return path;
    case SjPlatformEnum.windows:
    case SjPlatformEnum.macos:
    case SjPlatformEnum.ios:
      final documentsPath = await getSjDocumentsPath();
      return '$documentsPath${Platform.pathSeparator}databases';
  }
}

Future<Directory> getSjDatabasesDir() async {
  return Directory(await getSjDatabasesPath());
}
