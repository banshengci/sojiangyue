import 'dart:io';
import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String documentPath = '';

/// Check if a path is accessible (can read and write)
Future<bool> _isPathAccessible(String path) async {
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) return false;

    // Try to create and delete a test file to verify write permission
    final testFile = File('$path${Platform.pathSeparator}.songjiang_permission_test');
    await testFile.writeAsString('test');
    await testFile.delete();
    return true;
  } catch (e) {
    SjLog.warning('Path not accessible: $path, error: $e');
    return false;
  }
}

Future<String> getSjDocumentsPath() async {
  // Windows only: Check for custom storage path first
  if (SjPlatform.isWindows) {
    final customPath = AppMiscPrefs.customStoragePath;
    if (customPath != null) {
      // Verify the path is still accessible (permission may have been revoked)
      if (await _isPathAccessible(customPath)) {
        return customPath;
      } else {
        // Permission lost, clear the custom path
        SjLog.warning(
            'Custom storage path no longer accessible, resetting to default');
        AppMiscPrefs.customStoragePath = null;
      }
    }
  }

  final directory = await getApplicationDocumentsDirectory();
  switch (SjPlatform.type) {
    case SjPlatformEnum.android:
    case SjPlatformEnum.ohos:
      return directory.path;
    case SjPlatformEnum.windows:
      return (await getApplicationSupportDirectory()).path;
    case SjPlatformEnum.macos:
      return (await getApplicationSupportDirectory()).path;
    case SjPlatformEnum.ios:
      return (await getApplicationSupportDirectory()).path;
  }
}

Future<Directory> getSjDocumentDir() async {
  return Directory(await getSjDocumentsPath());
}

/// 初始化文档根目录与子目录。
///
/// 必须返回 Future 以便调用方 await：本函数为 async，若声明成 void，
/// 调用方无法等待其完成，随后立刻调用 [getBasePath] 会拿到空的
/// documentPath，在安卓上表现为导入/保存书籍失败。
Future<void> initBasePath() async {
  Directory appDocDir = await getSjDocumentDir();
  documentPath = appDocDir.path;
  debugPrint('documentPath: $documentPath');
  final fileDir = getFileDir();
  final coverDir = getCoverDir();
  final fontDir = getFontDir();
  final bgimgDir = getBgimgDir();
  if (!fileDir.existsSync()) {
    fileDir.createSync(recursive: true);
  }
  if (!coverDir.existsSync()) {
    coverDir.createSync(recursive: true);
  }
  if (!fontDir.existsSync()) {
    fontDir.createSync(recursive: true);
  }
  if (!bgimgDir.existsSync()) {
    bgimgDir.createSync(recursive: true);
  }
}

String getBasePath(String path) {
  // the path that in database using "/"
  path.replaceAll("/", Platform.pathSeparator);
  return '$documentPath${Platform.pathSeparator}$path';
}

Directory getFontDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}font');
}

Directory getCoverDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}cover');
}

Directory getFileDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}file');
}

Directory getBgimgDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}bgimg');
}
