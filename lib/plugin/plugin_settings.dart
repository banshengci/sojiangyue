// lib/plugin/plugin_settings.dart
//
// 插件设置：由宿主渲染、由宿主保存，插件模板通过 {{config.key}} 读取。
//
// 造梦的 settings 支持 boolean / integer / enum；我们在此基础上多给一个 text
// （很多场景需要填一个词或一句提示，用 enum 硬凑很别扭）。
//
// 关键约束：设置值**只能**来自用户在界面上填的内容，插件自己不能改写它——
// 否则一个插件就能把自己的开关从"关"改成"开"。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/utils/log/common.dart';

/// 设置项类型。
enum PluginSettingType {
  boolean('boolean'),
  integer('integer'),
  enum_('enum'),
  text('text');

  const PluginSettingType(this.code);
  final String code;

  static PluginSettingType parse(String? s) => PluginSettingType.values
      .firstWhere((t) => t.code == s, orElse: () => PluginSettingType.text);
}

/// 一个设置项的声明（来自 plugin.json 的 settings[]）。
class PluginSettingDef {
  const PluginSettingDef({
    required this.key,
    required this.title,
    required this.type,
    this.defaultValue,
    this.options = const [],
    this.hint,
  });

  final String key;
  final String title;
  final PluginSettingType type;

  /// 默认值。统一以字符串存放，读取时再按类型解释。
  final String? defaultValue;

  /// enum 的可选项。
  final List<String> options;

  final String? hint;

  factory PluginSettingDef.fromJson(Map<String, dynamic> j) {
    final rawDefault = j['default'];
    return PluginSettingDef(
      key: (j['key'] ?? '').toString(),
      title: (j['title'] ?? j['key'] ?? '').toString(),
      type: PluginSettingType.parse(j['type'] as String?),
      defaultValue: rawDefault?.toString(),
      options: (j['options'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      hint: j['hint']?.toString(),
    );
  }
}

/// 插件设置的读写。
///
/// 存储键：`plugin.<pluginId>.setting.<key>`。按插件前缀隔离，
/// 插件之间互不可见；卸载时随插件一起清。
class PluginSettingsStore {
  static const String _prefix = 'plugin.';

  static String _key(String pluginId, String settingKey) =>
      '$_prefix$pluginId.setting.$settingKey';

  /// 读出该插件全部设置（缺失项用默认值补齐）。
  static Future<Map<String, String>> resolve(
    String pluginId,
    List<PluginSettingDef> defs,
  ) async {
    final out = <String, String>{};
    for (final def in defs) {
      out[def.key] = def.defaultValue ?? '';
    }
    if (defs.isEmpty) return out;
    try {
      final sp = await SharedPreferences.getInstance();
      for (final def in defs) {
        final v = sp.getString(_key(pluginId, def.key));
        if (v != null) out[def.key] = v;
      }
    } catch (e) {
      SjLog.warning('Plugin: 读取设置失败 $pluginId: $e');
    }
    return out;
  }

  /// 写入一个设置项。返回 false 表示该键不在声明里（拒绝写未声明的键）。
  static Future<bool> set(
    String pluginId,
    List<PluginSettingDef> defs,
    String key,
    String value,
  ) async {
    if (!defs.any((d) => d.key == key)) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key(pluginId, key), value);
      return true;
    } catch (e) {
      SjLog.warning('Plugin: 写入设置失败 $pluginId.$key: $e');
      return false;
    }
  }

  /// 卸载时清理该插件的全部设置。
  static Future<void> clear(String pluginId, List<PluginSettingDef> defs) async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final def in defs) {
        await sp.remove(_key(pluginId, def.key));
      }
    } catch (e) {
      SjLog.warning('Plugin: 清理设置失败 $pluginId: $e');
    }
  }

  /// 把设置摊平成模板变量：`config.<key> -> 值`。
  static Map<String, String> toTemplateVars(Map<String, String> values) => {
        for (final e in values.entries) 'config.${e.key}': e.value,
      };
}

/// 便于测试与调试：把设置渲染成一行摘要。
String describeSettings(
  List<PluginSettingDef> defs,
  Map<String, String> values,
) {
  if (defs.isEmpty) return '';
  return defs.map((d) => '${d.title}=${values[d.key] ?? d.defaultValue ?? ''}').join('，');
}

/// 校验一个值是否符合声明（界面上改动时用）。
String? validateSettingValue(PluginSettingDef def, String value) {
  switch (def.type) {
    case PluginSettingType.boolean:
      return (value == 'true' || value == 'false') ? null : '布尔值只能是 true / false';
    case PluginSettingType.integer:
      return int.tryParse(value) == null ? '必须是整数' : null;
    case PluginSettingType.enum_:
      if (def.options.isEmpty) return null;
      return def.options.contains(value) ? null : '必须是选项之一：${def.options.join(' / ')}';
    case PluginSettingType.text:
      return value.length > 2000 ? '太长了（上限 2000 字）' : null;
  }
}

/// 调试用：把字符串解析成布尔（"true"/"1" 都算真）。
bool settingAsBool(String? raw, {bool fallback = false}) {
  final v = raw?.trim().toLowerCase();
  if (v == null || v.isEmpty) return fallback;
  return v == 'true' || v == '1' || v == 'yes';
}

/// 调试用：把设置值序列化成 JSON（导出/排查时用）。
String settingsToJson(List<PluginSettingDef> defs, Map<String, String> values) =>
    jsonEncode({for (final d in defs) d.key: values[d.key] ?? d.defaultValue});
