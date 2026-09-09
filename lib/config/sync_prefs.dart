import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/sync_protocol.dart';

/// WebDAV / 同步开关配置的领域访问层。
///
/// 须在 `Prefs().initPrefs()` 之后使用。
class SyncPrefs {
  SyncPrefs._();

  static const String webdavStatusKey = 'webdavStatus';
  static const String syncProtocolKey = 'syncProtocol';
  static const String autoSyncKey = 'autoSync';
  static const String onlySyncWhenWifiKey = 'onlySyncWhenWifi';
  static const String syncCompletedToastKey = 'syncCompletedToast';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'SyncPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  // ---- status / protocol ----

  static bool get webdavStatus =>
      _require.getBool(webdavStatusKey) ?? false;

  static set webdavStatus(bool status) {
    _require.setBool(webdavStatusKey, status);
  }

  static void saveWebdavStatus(bool status) {
    webdavStatus = status;
  }

  static String? get syncProtocol => _require.getString(syncProtocolKey);

  static set syncProtocol(String? protocol) {
    if (protocol != null) {
      _require.setString(syncProtocolKey, protocol);
    } else {
      _require.remove(syncProtocolKey);
    }
  }

  // ---- per-protocol credential/info maps ----

  static Map<String, dynamic> getSyncInfo(SyncProtocol protocol) {
    final raw = _require.getString('${protocol.name}Info');
    if (raw == null) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static void setSyncInfo(SyncProtocol protocol, Map<String, dynamic>? info) {
    if (info != null) {
      _require.setString('${protocol.name}Info', jsonEncode(info));
    } else {
      _require.remove('${protocol.name}Info');
    }
  }

  // ---- switches ----

  static bool get autoSync => _require.getBool(autoSyncKey) ?? true;

  static set autoSync(bool status) {
    _require.setBool(autoSyncKey, status);
  }

  static bool get onlySyncWhenWifi =>
      _require.getBool(onlySyncWhenWifiKey) ?? false;

  static set onlySyncWhenWifi(bool status) {
    _require.setBool(onlySyncWhenWifiKey, status);
  }

  static bool get syncCompletedToast =>
      _require.getBool(syncCompletedToastKey) ?? true;

  static set syncCompletedToast(bool status) {
    _require.setBool(syncCompletedToastKey, status);
  }
}
