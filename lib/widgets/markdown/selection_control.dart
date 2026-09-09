import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';

TextSelectionControls selectionControls() {
  switch (SjPlatform.type) {
    case SjPlatformEnum.ios:
    case SjPlatformEnum.macos:
      return CupertinoTextSelectionControls();
    case SjPlatformEnum.android:
    case SjPlatformEnum.ohos:
    case SjPlatformEnum.windows:
      return MaterialTextSelectionControls();
  }
}
