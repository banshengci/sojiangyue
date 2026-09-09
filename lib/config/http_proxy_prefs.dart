import 'package:shared_preferences/shared_preferences.dart';

/// HTTP 代理配置的领域访问层。
///
/// UI 层请用 `providers/http_proxy.dart` 的响应式 Notifier。
/// [SjHttpProxyOverrides.findProxy] 在 widget 树外同步运行，
/// 使用 [enabled]/[host]/[port] 同步 getter（依赖 [ensureInitialized]）。
class HttpProxyPrefs {
  HttpProxyPrefs._();

  static const String enabledKey = 'httpProxyEnabled';
  static const String hostKey = 'httpProxyHost';
  static const String portKey = 'httpProxyPort';
  static const String testUrlKey = 'httpProxyTestUrl';

  static const int defaultPort = 7890;
  static const String defaultTestUrl = 'https://google.com';

  static SharedPreferences? _sp;

  /// 须在 `Prefs().initPrefs()` 之后调用（main 启动流程）。
  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'HttpProxyPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  // ---- 同步读（HttpOverrides 用） ----

  static bool get enabled => _require.getBool(enabledKey) ?? false;
  static String get host => _require.getString(hostKey) ?? '';
  static int get port => _require.getInt(portKey) ?? defaultPort;
  static String get testUrl => _require.getString(testUrlKey) ?? defaultTestUrl;

  // ---- 异步读写（Riverpod provider 用） ----

  static Future<bool> readEnabled() async =>
      (await _load()).getBool(enabledKey) ?? false;

  static Future<String> readHost() async =>
      (await _load()).getString(hostKey) ?? '';

  static Future<int> readPort() async =>
      (await _load()).getInt(portKey) ?? defaultPort;

  static Future<String> readTestUrl() async =>
      (await _load()).getString(testUrlKey) ?? defaultTestUrl;

  static Future<void> writeEnabled(bool value) async =>
      (await _load()).setBool(enabledKey, value);

  static Future<void> writeHost(String value) async =>
      (await _load()).setString(hostKey, value);

  static Future<void> writePort(int value) async =>
      (await _load()).setInt(portKey, value);

  static Future<void> writeTestUrl(String value) async =>
      (await _load()).setString(testUrlKey, value);

  static Future<void> writeConfig({
    required String host,
    required int port,
    required String testUrl,
  }) async {
    final sp = await _load();
    await sp.setString(hostKey, host);
    await sp.setInt(portKey, port);
    await sp.setString(
      testUrlKey,
      testUrl.isEmpty ? defaultTestUrl : testUrl,
    );
  }

  static Future<SharedPreferences> _load() async {
    return _sp = await SharedPreferences.getInstance();
  }
}
