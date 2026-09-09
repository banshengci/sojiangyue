import 'dart:io';

import 'package:songjiang_reader/config/http_proxy_prefs.dart';

class SjHttpProxyOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
        return 'DIRECT';
      }

      if (!HttpProxyPrefs.enabled) {
        return 'DIRECT';
      }

      final proxyHost = HttpProxyPrefs.host.trim();
      final proxyPort = HttpProxyPrefs.port;
      if (proxyHost.isEmpty || proxyPort <= 0) {
        return 'DIRECT';
      }

      return 'PROXY $proxyHost:$proxyPort; DIRECT';
    };
    return client;
  }

  static Future<bool> testProxy(String host, int port, String testUrl) async {
    try {
      final uri = Uri.parse(testUrl);
      final client = HttpClient();
      client.findProxy = (_) => 'PROXY $host:$port; DIRECT';
      client.connectionTimeout = const Duration(seconds: 8);

      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 8),
          );
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      await response.drain<void>();
      client.close();
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }
}
