// lib/plugin/plugin_security.dart
//
// 插件安全边界：URL 沙箱 + 十六进制工具。
// 对齐造梦「能力白名单 + 禁私有网段」哲学，被市场客户端与事件分发器共用。

import 'dart:typed_data';

/// 插件下载 / 出网的安全约束。
class PluginSecurity {
  PluginSecurity._();

  /// 受信任发布者公钥白名单（hex，小写）。经 `--dart-define=PLUGIN_SIGNER_KEYS` 编译期注入。
  ///
  /// 写法（逗号分隔）：
  ///   - `key1,key2`                       —— 全局信任这两个公钥
  ///   - `插件id:key1,插件id2:key2`         —— 按插件 id 绑定，爆炸半径更小（推荐）
  ///   - `key0,com.foo.bar:key1`           —— 可混用
  ///
  /// 关键点：这份名单只来自**构建配置**，不来自任何网络响应。被投毒的 catalog 无法扩充它，
  /// 所以"服务端能写"不再等于"客户端会信任"。
  /// 注意：插件 id 里不能含 `:`（`:` 是 id 与公钥的分隔符）。
  static const String _signerKeysRaw =
      String.fromEnvironment('PLUGIN_SIGNER_KEYS', defaultValue: '');

  /// 过渡开关：默认 false。开启后允许安装"公钥未固定"的远程条目，并打 warning。
  /// 仅用于自建镜像尚未重签期间的临时放行，**不要**在正式分发构建里打开。
  static const bool allowUnpinned =
      bool.fromEnvironment('PLUGIN_ALLOW_UNPINNED', defaultValue: false);

  static final Map<String, List<String>> _pinnedSigners =
      _parsePinnedSigners(_signerKeysRaw);

  /// 是否配置过任何固定公钥（策略冲突自洽解法的前置条件之一，见 [isSafeUrl]）。
  static bool get hasPinnedSigners => _pinnedSigners.isNotEmpty;

  /// 当前固定公钥名单（只读视图，供 UI / 日志展示）。
  static Map<String, List<String>> get pinnedSigners =>
      Map.unmodifiable(_pinnedSigners);

  static Map<String, List<String>> _parsePinnedSigners(String raw) {
    final out = <String, List<String>>{};
    for (final group in raw.split(',')) {
      final item = group.trim();
      if (item.isEmpty) continue;
      final sep = item.indexOf(':');
      if (sep <= 0) {
        // 没有 `id:` 前缀 => 全局信任。
        out.putIfAbsent('*', () => <String>[]).add(item.toLowerCase());
      } else {
        final id = item.substring(0, sep).trim();
        final key = item.substring(sep + 1).trim().toLowerCase();
        if (id.isEmpty || key.isEmpty) continue;
        out.putIfAbsent(id, () => <String>[]).add(key);
      }
    }
    return out;
  }

  /// 该插件是否由"我信任的发布者"签名（先判这个，再验签名是否有效）。
  static bool isTrustedSigner(String pluginId, String publicKeyHex) {
    final key = publicKeyHex.trim().toLowerCase();
    if (key.isEmpty) return false;
    if (_pinnedSigners['*']?.contains(key) ?? false) return true;
    return _pinnedSigners[pluginId]?.contains(key) ?? false;
  }

  /// 是否允许作为插件下载源或网络访问目标。
  ///
  /// 允许：随包 `assets`、公网 `https`。
  /// 禁止（默认）：`http`（明文）、`localhost` / 回环地址 / `0.0.0.0`、
  ///       RFC1918 私有网段（10/8、172.16-31、192.168/16）、链路本地（169.254/16）、
  ///       IPv6 回环 / 链路本地（fe80::/10）/ ULA（fc00::/7）。
  ///
  /// [trustedHosts] 是**唯一**能让上述"内网地址"被放行的名单：调用方从**用户自己的
  /// dart-define 镜像地址**解析得到它（见 `RemoteConfig.trustedMirrorHosts`），
  /// 因此攻击者控制的目录响应无法把自己加进白名单 —— 既让 NAS 自托管可用，
  /// 又不放开"任意内网主机"的 SSRF。
  ///
  /// 明文 `http` 的例外还额外要求**已固定发布者公钥**（[hasPinnedSigners]）：
  /// 铁律「先固定公钥，再允许 LAN http」。TLS 管机密性、签名管完整性，
  /// 顺序倒了就等于自己把完整性校验拆掉。
  static bool isSafeUrl(Uri uri, {Set<String> trustedHosts = const {}}) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'assets' || scheme == 'asset') return true;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    final isTrustedMirror = trustedHosts.contains(host);
    if (scheme == 'http') return isTrustedMirror && hasPinnedSigners;
    if (scheme != 'https') return false;
    if (_isLocalOrPrivateHost(host)) return isTrustedMirror;
    return true;
  }

  /// 环回 / 私有 / 链路本地 / ULA 判定（IPv4 与 IPv6 都覆盖）。
  static bool _isLocalOrPrivateHost(String host) {
    final raw = host.toLowerCase();
    if (raw == 'localhost' || raw == '0.0.0.0' || raw == '::' || raw == '::1') {
      return true;
    }
    // Uri.host 对 IPv6 字面量会带方括号
    final v6 = raw.startsWith('[') && raw.endsWith(']')
        ? raw.substring(1, raw.length - 1)
        : raw;
    if (v6.startsWith('fe80:')) return true; // 链路本地
    if (v6.startsWith('fc') || v6.startsWith('fd')) return true; // ULA fc00::/7
    if (v6.startsWith('::ffff:')) {
      // IPv4-mapped，按内嵌的 IPv4 再判一次
      return _isLocalOrPrivateHost(v6.substring('::ffff:'.length));
    }
    final parts = v6.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 127) return true; // 整个 127.0.0.0/8，不只是 127.0.0.1
    if (a == 10) return true;
    if (a == 169 && b == 254) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
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
