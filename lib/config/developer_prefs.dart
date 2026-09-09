import 'package:shared_preferences/shared_preferences.dart';

/// 开发者选项与日志启动清理开关的领域访问层。
class DeveloperPrefs {
  DeveloperPrefs._();

  static const String developerOptionsKey = 'developerOptionsEnabled';
  static const String clearLogWhenStartKey = 'clearLogWhenStart';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'DeveloperPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static bool get developerOptionsEnabled =>
      _require.getBool(developerOptionsKey) ?? false;

  static set developerOptionsEnabled(bool value) {
    _require.setBool(developerOptionsKey, value);
  }

  static bool get clearLogWhenStart =>
      _require.getBool(clearLogWhenStartKey) ?? true;

  static set clearLogWhenStart(bool status) {
    _require.setBool(clearLogWhenStartKey, status);
  }
}
