import 'dart:convert';
import 'dart:core';

import 'package:songjiang_reader/enums/reading_info.dart';
import 'package:songjiang_reader/enums/translation_mode.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/models/reading_info.dart';
import 'package:songjiang_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:songjiang_reader/service/translate/index.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String prefsBackupVersionKey = '__prefsBackupVersion';
const int prefsBackupSchemaVersion = 1;
const String _prefsBackupEntryTypeKey = 'type';
const String _prefsBackupEntryValueKey = 'value';

const Set<String> _prefsImportSkipKeys = {
  'iapPurchaseStatus',
  'iapLastCheckTime',
};

/// 兼容层：初始化、备份/恢复，以及尚未拆分的少量字段。
/// 大部分配置已迁至 `config/*_prefs.dart` 领域层。
class Prefs extends ChangeNotifier {
  late SharedPreferences prefs;
  static final Prefs _instance = Prefs._internal();

  factory Prefs() {
    return _instance;
  }

  Prefs._internal() {
    initPrefs();
  }

  static const String _statisticsDashboardTilesKey = 'statisticsDashboardTiles';

  Future<void> initPrefs() async {
    prefs = await SharedPreferences.getInstance();
    // 直接写 beginDate：AppMiscPrefs 可能尚未 ensureInitialized（Prefs 单例构造时也会调本方法）
    if (prefs.getString('beginDate') == null) {
      prefs.setString('beginDate', DateTime.now().toIso8601String());
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> buildPrefsBackupMap() async {
    Map<String, Object?>? encodePrefsBackupEntry(Object? value) {
      if (value is bool) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'bool',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is int) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'int',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is double) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'double',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is String) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'string',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is List) {
        final bool allStrings =
            value.every((dynamic element) => element is String);
        if (allStrings) {
          return <String, Object?>{
            _prefsBackupEntryTypeKey: 'stringList',
            _prefsBackupEntryValueKey:
                List<String>.from(value, growable: false),
          };
        }
      }
      return null;
    }

    final Map<String, dynamic> backup = <String, dynamic>{
      prefsBackupVersionKey: prefsBackupSchemaVersion,
    };
    for (final String key in prefs.getKeys()) {
      final Object? value = prefs.get(key);
      final Map<String, Object?>? encoded = encodePrefsBackupEntry(value);
      if (encoded != null) {
        backup[key] = encoded;
      }
    }
    return backup;
  }

  Future<void> applyPrefsBackupMap(Map<String, dynamic> backup) async {
    for (final MapEntry<String, dynamic> entry in backup.entries) {
      final String key = entry.key;
      if (key == prefsBackupVersionKey || _prefsImportSkipKeys.contains(key)) {
        continue;
      }
      final dynamic entryValue = entry.value;
      if (entryValue is! Map) continue;
      final dynamic type = entryValue[_prefsBackupEntryTypeKey];
      final dynamic value = entryValue[_prefsBackupEntryValueKey];
      if (type is! String) continue;
      switch (type) {
        case 'bool':
          if (value is bool) await prefs.setBool(key, value);
          break;
        case 'int':
          if (value is int) await prefs.setInt(key, value);
          break;
        case 'double':
          if (value is num) await prefs.setDouble(key, value.toDouble());
          break;
        case 'string':
          if (value is String) await prefs.setString(key, value);
          break;
        case 'stringList':
          if (value is List) {
            final List<String> list =
                value.map((dynamic v) => v as String).toList();
            await prefs.setStringList(key, list);
          }
          break;
        default:
          continue;
      }
    }
    notifyListeners();
  }

  // ---- 尚未迁出的少量字段 ----

  List<StatisticsDashboardTileType> get statisticsDashboardTiles {
    final stored = prefs.getStringList(_statisticsDashboardTilesKey);
    if (stored == null || stored.isEmpty) {
      return List<StatisticsDashboardTileType>.from(
        defaultStatisticsDashboardTiles,
      );
    }
    final mapped = stored
        .map(_statisticsDashboardTileFromName)
        .whereType<StatisticsDashboardTileType>()
        .toList();
    if (mapped.isEmpty) {
      return List<StatisticsDashboardTileType>.from(
        defaultStatisticsDashboardTiles,
      );
    }
    return mapped;
  }

  set statisticsDashboardTiles(List<StatisticsDashboardTileType> tiles) {
    prefs.setStringList(
      _statisticsDashboardTilesKey,
      tiles.map((e) => e.name).toList(),
    );
    notifyListeners();
  }

  StatisticsDashboardTileType? _statisticsDashboardTileFromName(String name) {
    try {
      return StatisticsDashboardTileType.values
          .firstWhere((element) => element.name == name);
    } catch (_) {
      return null;
    }
  }

  bool get useOriginalCoverRatio {
    return prefs.getBool('useOriginalCoverRatio') ?? false;
  }

  set useOriginalCoverRatio(bool value) {
    prefs.setBool('useOriginalCoverRatio', value);
    notifyListeners();
  }

  set readingInfo(ReadingInfoModel info) {
    prefs.setString('readingInfo', jsonEncode(info.toJson()));
    notifyListeners();
  }

  ReadingInfoModel get readingInfo {
    String? readingInfoJson = prefs.getString('readingInfo');
    if (readingInfoJson == null) {
      return ReadingInfoModel();
    }
    final Map<String, dynamic> json =
        Map<String, dynamic>.from(jsonDecode(readingInfoJson));
    if (json.containsKey('header') || json.containsKey('footer')) {
      return ReadingInfoModel.fromJson(json);
    }

    return ReadingInfoModel(
      header: ReadingInfoSectionModel(
        left: _decodeReadingInfoEnum(
          json['headerLeft'],
          ReadingInfoEnum.chapterTitle,
        ),
        center: _decodeReadingInfoEnum(
          json['headerCenter'],
          ReadingInfoEnum.none,
        ),
        right: _decodeReadingInfoEnum(
          json['headerRight'],
          ReadingInfoEnum.none,
        ),
        verticalMargin: prefs.getDouble('pageHeaderMargin') ??
            MediaQuery.of(navigatorKey.currentContext!).padding.bottom,
        leftMargin: prefs.getDouble('pageHeaderLeftMargin') ?? 20,
        rightMargin: prefs.getDouble('pageHeaderRightMargin') ?? 20,
        fontSize: prefs.getDouble('pageHeaderFontSize') ?? 10,
      ),
      footer: ReadingInfoSectionModel(
        left: _decodeReadingInfoEnum(
          json['footerLeft'],
          ReadingInfoEnum.batteryAndTime,
        ),
        center: _decodeReadingInfoEnum(
          json['footerCenter'],
          ReadingInfoEnum.chapterProgress,
        ),
        right: _decodeReadingInfoEnum(
          json['footerRight'],
          ReadingInfoEnum.bookProgress,
        ),
        verticalMargin: prefs.getDouble('pageFooterMargin') ??
            MediaQuery.of(navigatorKey.currentContext!).padding.bottom,
        leftMargin: prefs.getDouble('pageFooterLeftMargin') ?? 20,
        rightMargin: prefs.getDouble('pageFooterRightMargin') ?? 20,
        fontSize: prefs.getDouble('pageFooterFontSize') ?? 10,
      ),
    );
  }

  TranslationModeEnum get translationMode {
    return TranslationModeEnum.fromCode(
        prefs.getString('translationMode') ?? 'off');
  }

  set translationMode(TranslationModeEnum mode) {
    prefs.setString('translationMode', mode.code);
    notifyListeners();
  }

  void saveTranslateServiceConfig(
      TranslateService service, Map<String, dynamic> config) {
    prefs.setString(
        'translateServiceConfig_${service.name}', jsonEncode(config));
    notifyListeners();
  }

  Map<String, dynamic>? getTranslateServiceConfig(TranslateService service) {
    String? configJson =
        prefs.getString('translateServiceConfig_${service.name}');
    if (configJson == null) {
      return null;
    }
    return jsonDecode(configJson) as Map<String, dynamic>;
  }

  Map<String, TranslationModeEnum> get bookTranslationModes {
    String? modesJson = prefs.getString('bookTranslationModes');
    if (modesJson == null || modesJson.isEmpty) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(modesJson);
      return decoded.map(
        (key, value) =>
            MapEntry(key, TranslationModeEnum.fromCode(value as String)),
      );
    } catch (e) {
      SjLog.warning('Prefs: failed to decode bookTranslationModes. $e');
      return {};
    }
  }

  set bookTranslationModes(Map<String, TranslationModeEnum> modes) {
    final Map<String, String> encoded =
        modes.map((key, value) => MapEntry(key, value.code));
    prefs.setString('bookTranslationModes', jsonEncode(encoded));
    notifyListeners();
  }

  TranslationModeEnum getBookTranslationMode(String bookId) {
    return bookTranslationModes[bookId] ?? TranslationModeEnum.off;
  }

  void setBookTranslationMode(String bookId, TranslationModeEnum mode) {
    Map<String, TranslationModeEnum> modes = bookTranslationModes;
    if (mode == TranslationModeEnum.off) {
      modes.remove(bookId);
    } else {
      modes[bookId] = mode;
    }
    bookTranslationModes = modes;
  }
}

ReadingInfoEnum _decodeReadingInfoEnum(
  Object? value,
  ReadingInfoEnum fallback,
) {
  if (value is! String) return fallback;
  for (final item in ReadingInfoEnum.values) {
    if (item.name == value) {
      return item;
    }
  }
  return fallback;
}
