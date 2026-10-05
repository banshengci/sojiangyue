// lib/service/gameplay/gameplay_pack_market_client.dart
//
// 玩法包市场客户端（3.3 分发闭环）：与 2.3 插件市场共用同一安全模型——
// SHA256 防篡改校验 + URL 沙箱（仅允许公网 https / 随包 assets）。
//
// 目录来源：配置 GAMEPACK_MIRROR_URL 则联网拉取 gameplay-catalog.json，
// 否则加载随包示例目录（离线演示）。条目下载地址支持 assets/ 相对路径（随包）
// 或经镜像根解析的相对路径（私有部署）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:songjiang_reader/config/remote_config.dart';
import 'package:songjiang_reader/plugin/plugin_security.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_models.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_service.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 玩法包市场目录条目。
class GameplayPackMarketEntry {
  const GameplayPackMarketEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.packType,
    required this.downloadUrl,
    required this.sha256,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String packType;
  final String downloadUrl;

  /// 官方公布的 SHA256 校验和（小写十六进制）。缺失则拒绝安装。
  final String sha256;

  factory GameplayPackMarketEntry.fromJson(Map<String, dynamic> j) =>
      GameplayPackMarketEntry(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? (j['id'] as String? ?? ''),
        version: (j['version'] as String?) ?? '1.0.0',
        description: (j['description'] as String?) ?? '',
        author: (j['author'] as String?) ?? '',
        packType: (j['packType'] as String?) ?? '',
        downloadUrl: (j['downloadUrl'] as String?) ?? '',
        sha256: ((j['sha256'] as String? ?? '').trim().toLowerCase()),
      );
}

/// 玩法包市场目录。
class GameplayPackMarketCatalog {
  const GameplayPackMarketCatalog({required this.entries});

  final List<GameplayPackMarketEntry> entries;

  factory GameplayPackMarketCatalog.fromJson(Map<String, dynamic> j) =>
      GameplayPackMarketCatalog(
        entries: (j['entries'] as List? ?? [])
            .map((e) => GameplayPackMarketEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class GameplayPackMarketClient {
  GameplayPackMarketClient._();

  static final GameplayPackMarketClient instance = GameplayPackMarketClient._();

  static const String _bundledCatalogAsset =
      'assets/gameplay/gameplay-catalog.json';

  /// 计算字节的 SHA256（小写十六进制），供安装校验与契约测试复用。
  static String computeSha256(Uint8List bytes) =>
      sha256.convert(bytes).toString().toLowerCase();

  /// 拉取玩法包目录：配置镜像则联网，否则加载随包示例（离线演示模式）。
  Future<GameplayPackMarketCatalog> fetchCatalog() async {
    final url = RemoteConfig.gamepackCatalogUrl;
    if (url.isNotEmpty) {
      try {
        final res = await Dio().get(url);
        final data = res.data;
        if (data is! Map) {
          throw StateError('目录响应格式错误（期望 JSON 对象）');
        }
        return GameplayPackMarketCatalog.fromJson(data as Map<String, dynamic>);
      } catch (e, st) {
        SjLog.warning('GamepackMarket: 拉取远程目录失败，回退随包示例: $e\n$st');
      }
    }
    final text = await rootBundle.loadString(_bundledCatalogAsset);
    return GameplayPackMarketCatalog.fromJson(
        jsonDecode(text) as Map<String, dynamic>);
  }

  /// 解析条目下载地址为可读取的字节源。返回 (path, isAsset)。
  ({String path, bool isAsset}) _resolveSource(GameplayPackMarketEntry entry) {
    final url = entry.downloadUrl;
    if (url.startsWith('assets/')) return (path: url, isAsset: true);
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (!PluginSecurity.isSafeUrl(uri)) {
        throw StateError('条目 ${entry.id} 的下载地址被安全策略禁止（仅允许公网 https）');
      }
      return (path: url, isAsset: false);
    }
    final mirror = RemoteConfig.gamepackMirrorUrl;
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

  /// 下载 / 读取条目字节。
  Future<Uint8List> _fetchBytes(GameplayPackMarketEntry entry) async {
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

  /// 安装一个市场条目：下载 → 防篡改(SHA256) → 解析 → 落盘。
  /// 校验失败会抛异常，调用方负责提示；返回实际 SHA256。
  Future<String> installEntry(GameplayPackMarketEntry entry) async {
    final bytes = await _fetchBytes(entry);
    final actual = computeSha256(bytes);
    if (entry.sha256.isEmpty) {
      throw StateError('玩法包缺少 SHA256 校验和，拒绝安装（安全策略）');
    }
    if (actual != entry.sha256) {
      throw StateError(
          'SHA256 校验失败：期望 ${entry.sha256}，实际 $actual。'
          '玩法包可能被篡改，已拒绝安装。');
    }
    final manifest = await GameplayPackService.instance.importPack(bytes);
    await GameplayPackService.instance.saveInstalled(manifest);
    return actual;
  }
}
