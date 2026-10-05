// lib/plugin/plugin_security.dart
//
// 插件安全边界：URL 沙箱 + 十六进制工具。
// 对齐造梦「能力白名单 + 禁私有网段」哲学，被市场客户端与事件分发器共用。

import 'dart:typed_data';

/// 插件下载 / 出网的安全约束。
class PluginSecurity {
  PluginSecurity._();

  /// 是否允许作为插件下载源或网络访问目标。
  ///
  /// 允许：随包 `assets`、公网 `https`。
  /// 禁止：`http`（明文）、`localhost` / 回环地址 / `0.0.0.0`、
  ///       RFC1918 私有网段（10.* / 172.16-31.* / 192.168.*）、链路本地（169.254.*）。
  static bool isSafeUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'assets' || scheme == 'asset') return true;
    if (scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0.0.0.0') {
      return false;
    }
    if (host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.startsWith('169.254.')) {
      return false;
    }
    if (_is172Private(host)) return false;
    return true;
  }

  static bool _is172Private(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    return a == 172 && b != null && b >= 16 && b <= 31;
  }

  /// 将小写十六进制串解码为字节（用于 Ed25519 公钥 / 签名）。
  static Uint8List hexToBytes(String hex) {
    final s = hex.trim().toLowerCase();
    if (s.length.isOdd) {
      throw FormatException('十六进制串长度必须为偶数: $hex');
    }
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(s.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) throw FormatException('非法十六进制字符: $hex');
      out[i] = byte;
    }
    return out;
  }
}
