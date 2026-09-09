import 'dart:io';

import 'package:flutter/foundation.dart';

enum SjPlatformEnum { android, ios, macos, windows, ohos }

class SjPlatform {
  static SjPlatformEnum get type {
    if (Platform.isAndroid && !kIsWeb) {
      return SjPlatformEnum.android;
    }
    if (Platform.isIOS && !kIsWeb) {
      return SjPlatformEnum.ios;
    }
    if (Platform.isMacOS && !kIsWeb) {
      return SjPlatformEnum.macos;
    }
    if (Platform.isWindows && !kIsWeb) {
      return SjPlatformEnum.windows;
    }
    try {
      if (Platform.operatingSystem == 'ohos') {
        return SjPlatformEnum.ohos;
      }
    } catch (_) {
      // Platform.operatingSystem might throw if not available in some environments
    }
    throw UnsupportedError('Unsupported platform');
  }

  static bool get isAndroid => type == SjPlatformEnum.android;
  static bool get isIOS => type == SjPlatformEnum.ios;
  static bool get isMacOS => type == SjPlatformEnum.macos;
  static bool get isWindows => type == SjPlatformEnum.windows;
  static bool get isOhos => type == SjPlatformEnum.ohos;

  static bool get isMobile => isAndroid || isIOS || isOhos;

  static bool get isDesktop => isWindows || isMacOS;
}
