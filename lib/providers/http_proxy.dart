import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:songjiang_reader/config/http_proxy_prefs.dart';

part 'http_proxy.g.dart';

/// HTTP 代理设置的响应式状态。
@riverpod
class HttpProxyNotifier extends _$HttpProxyNotifier {
  @override
  Future<HttpProxyConfig> build() async {
    return HttpProxyConfig(
      enabled: await HttpProxyPrefs.readEnabled(),
      host: await HttpProxyPrefs.readHost(),
      port: await HttpProxyPrefs.readPort(),
      testUrl: await HttpProxyPrefs.readTestUrl(),
    );
  }

  Future<void> setEnabled(bool enabled) async {
    await HttpProxyPrefs.writeEnabled(enabled);
    state = AsyncData(state.requireValue.copyWith(enabled: enabled));
  }

  Future<void> saveConfig({
    required String host,
    required int port,
    required String testUrl,
  }) async {
    await HttpProxyPrefs.writeConfig(
      host: host,
      port: port,
      testUrl: testUrl,
    );
    state = AsyncData(state.requireValue.copyWith(
      host: host,
      port: port,
      testUrl: testUrl.isEmpty ? HttpProxyPrefs.defaultTestUrl : testUrl,
    ));
  }
}

class HttpProxyConfig {
  const HttpProxyConfig({
    required this.enabled,
    required this.host,
    required this.port,
    required this.testUrl,
  });

  final bool enabled;
  final String host;
  final int port;
  final String testUrl;

  HttpProxyConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? testUrl,
  }) {
    return HttpProxyConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      testUrl: testUrl ?? this.testUrl,
    );
  }
}
