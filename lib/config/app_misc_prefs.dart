import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/models/chapter_split_presets.dart';
import 'package:songjiang_reader/models/chapter_split_rule.dart';
import 'package:songjiang_reader/models/font_model.dart';
import 'package:songjiang_reader/models/read_theme.dart';
import 'package:songjiang_reader/models/window_info.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 应用杂项：locale / 窗口 / 存储路径 / 时间戳 / 章节切分 / 书字体与主题。
/// font 默认值依赖 L10n，与旧 Prefs 行为一致。
class AppMiscPrefs {
  AppMiscPrefs._();

  static const String localeKey = 'locale';
  static const String windowInfoKey = 'windowInfo';
  static const String customStoragePathKey = 'customStoragePath';
  static const String beginDateKey = 'beginDate';
  static const String lastAppVersionKey = 'lastAppVersion';
  static const String lastShowUpdateKey = 'lastShowUpdate';
  static const String lastServerPortKey = 'lastServerPort';
  static const String lastUploadBookDateKey = 'lastUploadBookDate';
  static const String readThemeKey = 'readTheme';
  static const String fontKey = 'font';
  static const String chapterSplitSelectedKey = 'chapterSplitSelectedRuleId';
  static const String chapterSplitCustomKey = 'chapterSplitCustomRules';
  static const String readingInfoKey = 'readingInfo';

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'AppMiscPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  // ---- locale ----

  static Locale? get locale {
    final localeCode = _require.getString(localeKey);
    if (localeCode == null || localeCode == 'System') return null;
    if (localeCode.contains('-')) {
      final codes = localeCode.split('-');
      return Locale(codes[0], codes[1]);
    }
    return Locale(localeCode);
  }

  static Future<void> saveLocale(String localeCode) async {
    await _require.setString(localeKey, localeCode);
  }

  // ---- window / storage ----

  static set windowInfo(WindowInfo info) {
    _require.setString(windowInfoKey, jsonEncode(info.toJson()));
  }

  static WindowInfo get windowInfo {
    final raw = _require.getString(windowInfoKey);
    if (raw == null) {
      return const WindowInfo(x: 0, y: 0, width: 0, height: 0);
    }
    return WindowInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static String? get customStoragePath =>
      _require.getString(customStoragePathKey);

  static set customStoragePath(String? value) {
    if (value == null) {
      _require.remove(customStoragePathKey);
    } else {
      _require.setString(customStoragePathKey, value);
    }
  }

  // ---- timestamps / versions ----

  static void saveBeginDate() {
    if (_require.getString(beginDateKey) == null) {
      _require.setString(beginDateKey, DateTime.now().toIso8601String());
    }
  }

  static DateTime? get beginDate {
    final raw = _require.getString(beginDateKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static String? get lastAppVersion => _require.getString(lastAppVersionKey);

  static set lastAppVersion(String? version) {
    if (version != null) {
      _require.setString(lastAppVersionKey, version);
    } else {
      _require.remove(lastAppVersionKey);
    }
  }

  static DateTime get lastShowUpdate {
    final raw = _require.getString(lastShowUpdateKey);
    if (raw == null) return DateTime(1970, 1, 1);
    return DateTime.tryParse(raw) ?? DateTime(1970, 1, 1);
  }

  static set lastShowUpdate(DateTime value) {
    _require.setString(lastShowUpdateKey, value.toIso8601String());
  }

  static int get lastServerPort =>
      _require.getInt(lastServerPortKey) ?? 0;

  static set lastServerPort(int port) {
    _require.setInt(lastServerPortKey, port);
  }

  static DateTime? get lastUploadBookDate {
    final raw = _require.getString(lastUploadBookDateKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static set lastUploadBookDate(DateTime? value) {
    if (value == null) {
      _require.remove(lastUploadBookDateKey);
    } else {
      _require.setString(lastUploadBookDateKey, value.toIso8601String());
    }
  }

  // ---- read theme ----

  static void saveReadTheme(ReadTheme readTheme) {
    _require.setString(readThemeKey, readTheme.toJson());
  }

  static ReadTheme get readTheme {
    final raw = _require.getString(readThemeKey);
    if (raw == null) {
      // 品牌默认：宣纸（暖白纸面 + 墨色字）
      return ReadTheme(
        name: '宣纸',
        backgroundColor: 'FFFBF7EE',
        textColor: 'FF2E2A24',
        backgroundImagePath: '',
      );
    }
    return ReadTheme.fromJson(raw);
  }

  // ---- font (L10n-dependent default) ----

  static set font(FontModel font) {
    _require.setString(fontKey, font.toJson());
  }

  static FontModel get font {
    final fontJson = _require.getString(fontKey);
    final context = navigatorKey.currentContext;
    if (fontJson == null) {
      return FontModel(
        label: context == null ? 'Follow book' : L10n.of(context).followBook,
        name: 'book',
        path: 'book',
      );
    }
    return FontModel.fromJson(fontJson);
  }

  // ---- chapter split ----

  static List<ChapterSplitRule> get chapterSplitCustomRules {
    final raw = _require.getString(chapterSplitCustomKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((entry) {
        if (entry is Map<String, dynamic>) {
          return ChapterSplitRule.fromMap(entry);
        }
        if (entry is Map) {
          return ChapterSplitRule.fromMap(Map<String, dynamic>.from(entry));
        }
        throw const FormatException('Invalid chapter split rule entry');
      }).toList();
    } catch (e) {
      SjLog.warning(
          'AppMiscPrefs: Failed to decode custom chapter split rules. $e');
      return const [];
    }
  }

  static set chapterSplitCustomRules(List<ChapterSplitRule> rules) {
    final encoded = jsonEncode(rules.map((rule) => rule.toMap()).toList());
    _require.setString(chapterSplitCustomKey, encoded);
  }

  static List<ChapterSplitRule> get allChapterSplitRules {
    return [...builtinChapterSplitRules, ...chapterSplitCustomRules];
  }

  static String? get chapterSplitSelectedRuleId =>
      _require.getString(chapterSplitSelectedKey);

  static set chapterSplitSelectedRuleId(String? id) {
    if (id == null) {
      _require.remove(chapterSplitSelectedKey);
    } else {
      _require.setString(chapterSplitSelectedKey, id);
    }
  }

  static ChapterSplitRule get activeChapterSplitRule {
    final selectedId = chapterSplitSelectedRuleId;
    if (selectedId != null) {
      final builtin = findBuiltinChapterSplitRuleById(selectedId);
      if (builtin != null) {
        try {
          builtin.buildRegExp();
          return builtin;
        } catch (_) {}
      }
      final custom = chapterSplitCustomRules
          .where((rule) => rule.id == selectedId)
          .toList();
      if (custom.isNotEmpty) {
        final rule = custom.first;
        try {
          rule.buildRegExp();
          return rule;
        } catch (_) {}
      }
    }
    return getDefaultChapterSplitRule();
  }

  static void selectChapterSplitRule(String id) {
    chapterSplitSelectedRuleId = id;
  }

  static void saveCustomChapterSplitRule(ChapterSplitRule rule) {
    if (rule.isBuiltin) return;
    final rules = List<ChapterSplitRule>.from(chapterSplitCustomRules);
    final index = rules.indexWhere((existing) => existing.id == rule.id);
    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }
    chapterSplitCustomRules = rules;
  }

  static void deleteCustomChapterSplitRule(String id) {
    final rules = chapterSplitCustomRules
        .where((rule) => rule.id != id)
        .toList(growable: false);
    chapterSplitCustomRules = rules;
    if (chapterSplitSelectedRuleId == id) {
      chapterSplitSelectedRuleId = kDefaultChapterSplitRuleId;
    }
  }
}
