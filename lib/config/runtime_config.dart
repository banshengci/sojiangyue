// lib/config/runtime_config.dart
//
// 运行时配置中心（2.5）：把 RemoteConfig 从「纯构建期 dart-define 常量」升级为
// 「可运行时拉取的 JSON 覆盖层」。端点经 RUNTIME_CONFIG_URL(dart-define) 注入；
// 未配置时本层为空，所有读取回退到构建期常量 / 本地默认值。
//
// 用于远程更新 AI 提示词模板、书源解析规则、主题与排版预设，避免为小改动反复发版。
// 端点 URL 与「功能可用性」解耦：URL 可远程配置，可用性取决于本地能力 / 授权。

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/config/remote_config.dart';
import 'package:songjiang_reader/utils/log/common.dart';

class RuntimeConfig {
  RuntimeConfig._();
  static final RuntimeConfig instance = RuntimeConfig._();

  static const String _prefKey = 'runtimeConfigOverrides';

  Map<String, dynamic> _data = const {};
  DateTime? loadedAt;
  String? lastError;

  bool get isLoaded => loadedAt != null;

  String? getString(String key) => _data[key] as String?;
  bool? getBool(String key) => _data[key] as bool?;
  int? getInt(String key) => _data[key] as int?;
  dynamic operator [](String key) => _data[key];

  /// 启动时调用：先读本地缓存，再（可选）拉取远端。
  Future<void> init() async {
    await _loadCache();
    if (RemoteConfig.runtimeConfigUrl.isNotEmpty) {
      await refresh();
    }
  }

  Future<void> _loadCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_prefKey);
      if (raw != null) {
        _data = jsonDecode(raw) as Map<String, dynamic>;
        loadedAt = DateTime.now();
      }
    } catch (e) {
      SjLog.warning('RuntimeConfig: 读缓存失败 $e');
    }
  }

  /// 拉取并合并远端配置（增量覆盖，不删除本地既有键）。
  Future<void> refresh() async {
    final url = RemoteConfig.runtimeConfigUrl;
    if (url.isEmpty) {
      lastError = '未配置 RUNTIME_CONFIG_URL';
      return;
    }
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        lastError = '远端配置格式错误';
        return;
      }
      _data = {..._data, ...decoded};
      loadedAt = DateTime.now();
      lastError = null;
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, jsonEncode(_data));
      SjLog.info('RuntimeConfig: 已更新 ${_data.length} 项覆盖');
    } catch (e) {
      lastError = e.toString();
      SjLog.warning('RuntimeConfig: 拉取失败 $e');
    }
  }
}
