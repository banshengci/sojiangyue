import 'dart:ui';

import 'package:songjiang_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class SjError {
  static Future<void> init() async {
    SjLog.info('SjError init');
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      SjLog.severe(details.exceptionAsString(), details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      SjLog.severe(error.toString(), stack);
      return false;
    };
  }
}
