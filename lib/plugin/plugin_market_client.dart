// lib/plugin/plugin_market_client.dart
//
// 远程插件市场客户端（P1 平台化）：
// - 拉取插件目录（plugins-catalog.json）：配置了镜像地址则走网络，否则加载随包示例目录（离线演示）。
// - 安装插件：下载字节 → SHA256 校验和比对 → Ed25519 发布者签名验签 →
//   解析 manifest → 注册到 PluginRegistry → 落盘持久化。
// - 安全边界：缺少 SHA256 校验和、SHA256 不符、Ed25519 签名无效，或下载地址
//   非公网 https（localhost / 私有网段）的插件一律拒绝安装
//   （对齐造梦「不执行不可信代码 + 能力白名单 + 禁私有网段」哲学）。
//
// 完全复用工程既有范式：配置经 RemoteConfig(dart-define) 注入，网络用 Dio，
// 与 lib/utils/check_update.dart 的更新源实现保持一致。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:songjiang_reader/config/remote_config.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/plugin_security.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 市场目录中的单个插件条目。
class PluginMarketEntry {
  const PluginMarketEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.downloadUrl,
    required this.sha256,
    this.signerPublicKey,
    this.signatureHex,
    this.minAppVersion,
  });

  /// 插件 id（与 plugin.json 的 id 一致，用作去重主键）。
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;

  /// 下载地址：可为 `assets/...` 随包资源（离线演示）、http(s) 完整 URL，
  /// 或相对路径（需配合 PLUGIN_MIRROR_URL 解析）。
  final String downloadUrl;

  /// 官方公布的 SHA256 校验和（小写十六进制）。缺失则拒绝安装。
  final String sha256;

  /// 发布者 Ed25519 公钥（hex）。远程分发必备；随包 assets 示例可无。
  final String? signerPublicKey;

  /// 插件字节的 Ed25519 detached 签名（hex）。与 [signerPublicKey] 成对出现。
  final String? signatureHex;
  final String? minAppVersion;

  static PluginMarketEntry fromJson(Map<String, dynamic> j) => PluginMarketEntry(
        id: j['id'] as String,
        name: j['name'] as String? ?? (j['id'] as String),
        version: j['version'] as String? ?? '0.0.0',
        description: j['description'] as String? ?? '',
        author: j['author'] as String? ?? '',
        downloadUrl: j['downloadUrl'] as String,
        sha256: (j['sha256'] as String? ?? '').trim().toLowerCase(),
        signerPublicKey: (j['signerPublicKey'] as String?)?.trim(),
        signatureHex: (j['signatureHex'] as String?)?.trim().toLowerCase(),
        minAppVersion: j['minAppVersion'] as String?,
      );
}

/// 市场插件目录（plugins-catalog.json 解析结果）。
class PluginMarketCatalog {
  const PluginMarketCatalog({
    required this.schemaVersion,
    required this.updatedAt,
    required this.entries,
  });

  final String schemaVersion;
  final String updatedAt;
  final List<PluginMarketEntry> entries;

  factory PluginMarketCatalog.fromJson(Map<String, dynamic> j) =>
      PluginMarketCatalog(
        schemaVersion: j['schemaVersion'] as String? ?? '1.0',
        updatedAt: j['updatedAt'] as String? ?? '',
        entries: (j['entries'] as List? ?? [])
            .map((e) => PluginMarketEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 安装结果（供 UI 展示校验/落盘状态）。
class PluginInstallResult {
  const PluginInstallResult({
    required this.plugin,
    required this.bytes,
    required this.actualSha256,
  });
  final SongjiangPlugin plugin;
  final Uint8List bytes;
  final String actualSha256;
}

class PluginMarketClient {
  PluginMarketClient._();
  static final PluginMarketClient instance = PluginMarketClient._();

  static const String _bundledCatalogAsset = 'assets/plugins/plugins-catalog.json';

  /// 本地已安装插件的持久化目录（应用支持目录下的 plugins/）。
  Future<Directory> get _storeDir async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/plugins');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 拉取插件目录：配置镜像则联网，否则加载随包示例（离线演示模式）。
  Future<PluginMarketCatalog> fetchCatalog() async {
    final catalogUrl = RemoteConfig.pluginCatalogUrl;
    if (catalogUrl.isNotEmpty) {
      try {
        final res = await Dio().get(catalogUrl);
        final data = res.data;
        if (data is! Map) {
          throw StateError('目录响应格式错误（期望 JSON 对象）');
        }
        return PluginMarketCatalog.fromJson(data as Map<String, dynamic>);
      } catch (e, st) {
        SjLog.warning('PluginMarket: 拉取远程目录失败，回退随包示例: $e\n$st');
      }
    }
    // 离线演示：加载随包目录。
    final text = await rootBundle.loadString(_bundledCatalogAsset);
    return PluginMarketCatalog.fromJson(
        jsonDecode(text) as Map<String, dynamic>);
  }

  /// 解析条目下载地址为可读取的字节源。
  /// 返回 (source, isAsset)。
  ({String path, bool isAsset}) _resolveSource(PluginMarketEntry entry) {
    final url = entry.downloadUrl;
    if (url.startsWith('assets/')) return (path: url, isAsset: true);
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (!PluginSecurity.isSafeUrl(uri)) {
        throw StateError('条目 ${entry.id} 的下载地址被安全策略禁止（仅允许公网 https）');
      }
      return (path: url, isAsset: false);
    }
    // 相对路径：需配合镜像地址解析。
    final mirror = RemoteConfig.pluginMirrorUrl;
    if (mirror.isNotEmpty) {
      final base = mirror.endsWith('/') ? mirror : '$mirror/';
      final resolved = Uri.tryParse('$base$url');
      if (resolved != null && !PluginSecurity.isSafeUrl(resolved)) {
        throw StateError('条目 ${entry.id} 的镜像地址被安全策略禁止（仅允许公网 https）');
      }
      return (path: '$base$url', isAsset: false);
    }
    throw StateError('条目 ${entry.id} 的下载地址无法解析（缺少镜像配置）');
  }

  /// 下载/读取插件字节。
  Future<Uint8List> _fetchBytes(PluginMarketEntry entry) async {
    final (:path, :isAsset) = _resolveSource(entry);
    if (isAsset) {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    }
    final res = await Dio().get<List<int>>(path,
        options: Options(responseType: ResponseType.bytes));
    final data = res.data;
    if (data == null) throw StateError('下载返回空');
    return Uint8List.fromList(data);
  }

  /// 校验插件字节的 SHA256 是否等于官方公布值。
  String _verifySha256(Uint8List bytes, String expected) {
    final actual = sha256.convert(bytes).toString().toLowerCase();
    if (expected.isEmpty) {
      throw StateError('插件缺少 SHA256 校验和，拒绝安装（安全策略）');
    }
    if (actual != expected) {
      throw StateError(
          'SHA256 校验失败：期望 $expected，实际 $actual。插件可能被篡改，已拒绝安装。');
    }
    return actual;
  }

  /// 校验插件字节的 Ed25519 detached 签名是否由 [publicKeyHex] 签发。
  /// 解析 / 验签异常一律返回 false（拒绝安装）。
  Future<bool> _verifyEd25519(
    Uint8List bytes,
    String signatureHex,
    String publicKeyHex,
  ) async {
    try {
      final ed = Ed25519();
      final publicKey = SimplePublicKey(
        PluginSecurity.hexToBytes(publicKeyHex),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        PluginSecurity.hexToBytes(signatureHex),
        publicKey: publicKey,
      );
      return ed.verify(bytes, signature);
    } catch (e) {
      SjLog.warning('PluginMarket: Ed25519 验签异常: $e');
      return false;
    }
  }

  /// 安装一个市场条目：下载 → 防篡改(SHA256) → 发布者签名(Ed25519) →
  /// 解析 → 注册 → 落盘。
  ///
  /// 注意：本方法不阻塞 UI；校验失败会抛异常，调用方负责提示。
  /// 随包 assets 示例视为可信、可无签名；远程条目强制要求 Ed25519 签名。
  Future<PluginInstallResult> installEntry(PluginMarketEntry entry) async {
    final bytes = await _fetchBytes(entry);
    final actual = _verifySha256(bytes, entry.sha256);
    final isBundled = entry.downloadUrl.startsWith('assets/');
    if (!isBundled) {
      if (entry.signatureHex == null || entry.signerPublicKey == null) {
        throw StateError('远程插件缺少发布者签名，拒绝安装（安全策略）');
      }
      final signed = await _verifyEd25519(
        bytes,
        entry.signatureHex!,
        entry.signerPublicKey!,
      );
      if (!signed) {
        throw StateError('Ed25519 签名校验失败：插件来源不可信，已拒绝安装。');
      }
    }
    final manifest =
        PluginManifest.parse(utf8.decode(bytes)); // 校验通过才解析。
    final plugin = PluginRegistry.instance.loadManifest(manifest);
    await _persist(plugin.id, bytes);
    SjLog.info('PluginMarket: 已安装 ${plugin.id} (sha256=$actual'
        '${isBundled ? '' : ', ed25519=ok'})');
    return PluginInstallResult(plugin: plugin, bytes: bytes, actualSha256: actual);
  }

  /// 落盘插件清单（应用重启后由 PluginRegistry.ensureLoaded 读回）。
  Future<void> _persist(String pluginId, Uint8List bytes) async {
    try {
      final dir = await _storeDir;
      final file = File('${dir.path}/$pluginId.plugin.json');
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      SjLog.warning('PluginMarket: 持久化插件失败 $pluginId: $e');
    }
  }
}
