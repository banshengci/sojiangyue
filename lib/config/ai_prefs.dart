import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/enums/ai_chat_display_mode.dart';
import 'package:songjiang_reader/enums/ai_panel_position.dart';
import 'package:songjiang_reader/enums/ai_prompts.dart';
import 'package:songjiang_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:songjiang_reader/models/user_prompt.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// AI 配置 / 工具 / 提示词 / 面板参数的领域访问层。
class AiPrefs {
  AiPrefs._();

  static const String configPrefix = 'aiConfig_';
  static const String promptPrefix = 'aiPrompt_';
  static const String selectedServiceKey = 'selectedAiService';
  static const String providersKey = 'aiProviders';
  static const String enabledToolsKey = 'enabledAiTools';
  static const String userPromptsKey = 'userPrompts';
  static const String rpmKey = 'aiRpm';
  static const String legacyRpmKey = 'fullTextTranslateRpm';
  static const String maxCacheKey = 'maxAiCacheCount';
  static const String chatFontSizeKey = 'aiChatFontSize';
  static const String panelPositionKey = 'aiPanelPosition';
  static const String panelWidthKey = 'aiPanelWidth';
  static const String panelHeightKey = 'aiPanelHeight';
  static const String chatDisplayModeKey = 'aiChatDisplayMode';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'AiPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  // ---- service config ----

  static void saveConfig(String identifier, Map<String, String> config) {
    _require.setString('$configPrefix$identifier', jsonEncode(config));
  }

  static Map<String, String> getConfig(String identifier) {
    final raw = _require.getString('$configPrefix$identifier');
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v.toString()));
  }

  static void deleteConfig(String identifier) {
    _require.remove('$configPrefix$identifier');
  }

  static String get selectedServiceId =>
      _require.getString(selectedServiceKey) ?? 'openai';

  static set selectedServiceId(String identifier) {
    _require.setString(selectedServiceKey, identifier);
  }

  // ---- providers list (raw JSON) ----

  static void saveProviders(List<dynamic> providers) {
    final jsonList = providers.map((p) {
      if (p is Map<String, dynamic>) return p;
      return p.toJson();
    }).toList();
    _require.setString(providersKey, jsonEncode(jsonList));
  }

  static List<dynamic> getProviders() {
    final jsonString = _require.getString(providersKey);
    if (jsonString == null) return [];
    try {
      return jsonDecode(jsonString) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  // ---- prompts ----

  static void savePrompt(AiPrompts identifier, String prompt) {
    _require.setString('$promptPrefix${identifier.name}', prompt);
  }

  static String getPrompt(AiPrompts identifier) {
    final raw = _require.getString('$promptPrefix${identifier.name}');
    return raw ?? identifier.getPrompt();
  }

  static void deletePrompt(AiPrompts identifier) {
    _require.remove('$promptPrefix${identifier.name}');
  }

  // ---- tools ----

  static List<String> get enabledToolIds {
    final stored = _require.getStringList(enabledToolsKey);
    if (stored == null) return AiToolRegistry.defaultEnabledToolIds();
    if (stored.isEmpty) return const [];
    final sanitized = AiToolRegistry.sanitizeIds(stored);
    if (sanitized.isEmpty && stored.isNotEmpty) {
      return AiToolRegistry.defaultEnabledToolIds();
    }
    return sanitized;
  }

  static set enabledToolIds(List<String> ids) {
    _require.setStringList(enabledToolsKey, AiToolRegistry.sanitizeIds(ids));
  }

  static bool isToolEnabled(String id) => enabledToolIds.contains(id);

  static void resetEnabledTools() {
    _require.remove(enabledToolsKey);
  }

  // ---- user prompts ----

  static List<UserPrompt> get userPrompts {
    final jsonString = _require.getString(userPromptsKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => UserPrompt.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      SjLog.severe('AiPrefs: failed to load user prompts: $e');
      return [];
    }
  }

  static set userPrompts(List<UserPrompt> prompts) {
    final jsonList = prompts.map((p) => p.toJson()).toList();
    _require.setString(userPromptsKey, jsonEncode(jsonList));
  }

  // ---- rpm / cache / font size ----

  static int get rpm {
    final legacy = _require.getInt(legacyRpmKey);
    if (legacy != null) {
      _require.setInt(rpmKey, legacy);
      _require.remove(legacyRpmKey);
      return legacy;
    }
    return _require.getInt(rpmKey) ?? 0;
  }

  static set rpm(int value) {
    _require.setInt(rpmKey, value);
  }

  static int get maxCacheCount => _require.getInt(maxCacheKey) ?? 300;

  static set maxCacheCount(int count) {
    _require.setInt(maxCacheKey, count);
  }

  static double get chatFontSize =>
      _require.getDouble(chatFontSizeKey) ?? 14.0;

  static set chatFontSize(double size) {
    _require.setDouble(chatFontSizeKey, size);
  }

  // ---- panel ----

  static AiPanelPositionEnum get aiPanelPosition =>
      AiPanelPositionEnum.fromCode(
          _require.getString(panelPositionKey) ?? 'right');

  static set aiPanelPosition(AiPanelPositionEnum position) {
    _require.setString(panelPositionKey, position.code);
  }

  static double get aiPanelWidth =>
      _require.getDouble(panelWidthKey) ?? 300;

  static set aiPanelWidth(double width) {
    _require.setDouble(panelWidthKey, width);
  }

  static double get aiPanelHeight =>
      _require.getDouble(panelHeightKey) ?? 300;

  static set aiPanelHeight(double height) {
    _require.setDouble(panelHeightKey, height);
  }

  static AiChatDisplayMode get aiChatDisplayMode =>
      AiChatDisplayMode.fromCode(
          _require.getString(chatDisplayModeKey) ?? 'adaptive');

  static set aiChatDisplayMode(AiChatDisplayMode mode) {
    _require.setString(chatDisplayModeKey, mode.code);
  }
}
