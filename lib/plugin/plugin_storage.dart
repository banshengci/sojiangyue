// lib/plugin/plugin_storage.dart
//
// 插件私有数据区：按插件隔离的小容量文本存储。
//
// 用途是"记住一点东西"——上次选了谁、累计拒绝了几次、用户填过的偏好。
// 刻意做得很小（单值 8 KB、最多 32 个键、合计 64 KB）：
// 插件不是数据库，需要存大块内容说明设计错了。
//
// 隔离方式：存储键带插件 id 前缀，读取时只按该前缀查询；
// 插件拿不到别的插件的键（它连键名都不知道）。

import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/utils/log/common.dart';

/// 插件私有存储。
class PluginStorage {
  /// 单个值上限（字符数）。
  static const int maxValueLength = 8 * 1024;

  /// 单插件键数量上限。
  static const int maxKeys = 32;

  /// 单插件合计上限（字符数）。
  static const int maxTotalLength = 64 * 1024;

  static const String _prefix = 'plugin.';

  static String _key(String pluginId, String key) =>
      '$_prefix$pluginId.data.$key';

  static String _keyPrefix(String pluginId) => '$_prefix$pluginId.data.';

  /// 列出该插件已有的全部键值。
  static Future<Map<String, String>> all(String pluginId) async {
    final out = <String, String>{};
    try {
      final sp = await SharedPreferences.getInstance();
      final prefix = _keyPrefix(pluginId);
      for (final k in sp.getKeys()) {
        if (!k.startsWith(prefix)) continue;
        final v = sp.getString(k);
        if (v != null) out[k.substring(prefix.length)] = v;
      }
    } catch (e) {
      SjLog.warning('Plugin: 读取私有数据失败 $pluginId: $e');
    }
    return out;
  }

  /// 读一个键。
  static Future<String?> read(String pluginId, String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getString(_key(pluginId, key));
    } catch (e) {
      SjLog.warning('Plugin: 读取私有数据失败 $pluginId.$key: $e');
      return null;
    }
  }

  /// 写一个键。超限或键名非法时抛 [PluginStorageException]。
  static Future<void> write(
    String pluginId,
    String key,
    String value,
  ) async {
    if (!_safeKey(key)) {
      throw PluginStorageException('数据键只能用字母、数字、下划线、点和连字符');
    }
    if (value.length > maxValueLength) {
      throw PluginStorageException('单个值超过 $maxValueLength 字符上限');
    }
    final existing = await all(pluginId);
    if (!existing.containsKey(key) && existing.length >= maxKeys) {
      throw PluginStorageException('键数量超过 $maxKeys 个上限');
    }
    final total = existing.entries
            .where((e) => e.key != key)
            .fold<int>(0, (sum, e) => sum + e.value.length) +
        value.length;
    if (total > maxTotalLength) {
      throw PluginStorageException('合计超过 64 KB 上限');
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key(pluginId, key), value);
    } catch (e) {
      throw PluginStorageException('写入失败：$e');
    }
  }

  /// 删除一个键。
  static Future<void> remove(String pluginId, String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_key(pluginId, key));
    } catch (e) {
      SjLog.warning('Plugin: 删除私有数据失败 $pluginId.$key: $e');
    }
  }

  /// 卸载时清空该插件的全部数据。
  static Future<void> clear(String pluginId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final prefix = _keyPrefix(pluginId);
      for (final k in sp.getKeys().where((k) => k.startsWith(prefix)).toList()) {
        await sp.remove(k);
      }
    } catch (e) {
      SjLog.warning('Plugin: 清理私有数据失败 $pluginId: $e');
    }
  }

  /// 摊平成模板变量：`storage.<key> -> 值`。
  static Map<String, String> toTemplateVars(Map<String, String> values) => {
        for (final e in values.entries) 'storage.${e.key}': e.value,
      };

  static bool _safeKey(String key) =>
      key.isNotEmpty && RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(key);
}

/// 存储约束被违反时抛出。
class PluginStorageException implements Exception {
  PluginStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}
