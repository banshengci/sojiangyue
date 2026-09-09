import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/enums/version_check_type.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/utils/app_version.dart';
import 'package:flutter/cupertino.dart';
import 'package:songjiang_reader/page/onboarding_screen.dart';
import 'package:songjiang_reader/page/changelog_screen.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class InitializationCheck {
  static String? _lastVersion;
  static String? _currentVersion;

  static Future<String> get lastVersion async {
    if (_lastVersion == null) {
      await _checkVersion();
    }
    return _lastVersion!;
  }

  static Future<String> get currentVersion async {
    if (_currentVersion == null) {
      await _checkVersion();
    }
    return _currentVersion!;
  }

  static Future<void> check() async {
    final result = await _checkVersion();
    SjLog.info('Version check result: $result');
    if (result == VersionCheckType.firstLaunch) {
      _handleFirstLaunch();
    } else if (result == VersionCheckType.updated) {
      _handleUpdateAvailable();
    } else {
      _handleNormalStartup();
    }
  }

  static Future<VersionCheckType> _checkVersion() async {
    _lastVersion = AppMiscPrefs.lastAppVersion;
    _currentVersion = await getAppVersion();
    if (_lastVersion == null) {
      return VersionCheckType.firstLaunch;
    } else {
      if (_lastVersion != _currentVersion) {
        return VersionCheckType.updated;
      } else {
        return VersionCheckType.normal;
      }
    }
  }

  static Future<void> _handleFirstLaunch() async {
    SjLog.info('First launch detected, showing onboarding');
    final cv = await currentVersion;
    // wait 0.8 seconds to ensure the app is ready
    Future.delayed(const Duration(milliseconds: 800), () {
      showCupertinoSheet(
        context: navigatorKey.currentContext!,
        builder: (context) => Scaffold(
          body: OnboardingScreen(
            onComplete: () async {
              AppMiscPrefs.lastAppVersion = cv;
              Navigator.pop(context);
            },
          ),
        ),
      );
    });
  }

  static Future<void> _handleUpdateAvailable() async {
    final lv = await lastVersion;
    final cv = await currentVersion;
    SjLog.info('Version update detected: $lv -> $cv');
    Future.delayed(const Duration(milliseconds: 800), () {
      showCupertinoSheet(
        context: navigatorKey.currentContext!,
        builder: (context) => ChangelogScreen(
          lastVersion: lv,
          currentVersion: cv,
          onComplete: () {
            AppMiscPrefs.lastAppVersion = cv;
            Navigator.pop(context);
          },
        ),
      );
    });
  }

  static void _handleNormalStartup() {
    SjLog.info('Normal startup, proceeding to main app');
  }
}
