import 'package:shared_preferences/shared_preferences.dart';

/// 内购状态缓存的领域访问层。
/// 键在 Prefs 备份时会跳过（见 _prefsImportSkipKeys）。
class IapPrefs {
  IapPrefs._();

  static const String purchaseStatusKey = 'iapPurchaseStatus';
  static const String lastCheckTimeKey = 'iapLastCheckTime';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'IapPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static bool get purchased => _require.getBool(purchaseStatusKey) ?? false;

  static set purchased(bool value) {
    _require.setBool(purchaseStatusKey, value);
  }

  static DateTime get lastCheckTime {
    final raw = _require.getString(lastCheckTimeKey);
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static set lastCheckTime(DateTime value) {
    _require.setString(lastCheckTimeKey, value.toIso8601String());
  }
}
