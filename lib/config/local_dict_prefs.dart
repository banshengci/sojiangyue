import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 本地词典：加载用户提供的 JSON 词典，划词优先离线查询，失败再走 AI。
///
/// 词典格式：
/// ```json
/// { "hello": "你好", "serendipity": "意外发现美好事物的能力" }
/// ```
class LocalDictPrefs {
  LocalDictPrefs._();

  static const String pathKey = 'localDictPath';

  static SharedPreferences? _sp;
  static Map<String, String>? _cache;
  static String? _cachePath;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'LocalDictPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static String? get path => _require.getString(pathKey);

  static set path(String? value) {
    final normalized = (value == null || value.isEmpty) ? null : value;
    final current = _require.getString(pathKey);
    if (normalized == null) {
      _require.remove(pathKey);
      _cache = null;
      _cachePath = null;
      return;
    }
    _require.setString(pathKey, normalized);
    if (current != normalized) {
      _cache = null;
      _cachePath = null;
    }
  }

  static Future<bool> loadFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final map = <String, String>{};
      decoded.forEach((key, value) {
        if (value is String && value.trim().isNotEmpty) {
          map[key.trim()] = value.trim();
        }
      });
      if (map.isEmpty) return false;
      _cache = map;
      _cachePath = filePath;
      path = filePath;
      SjLog.info('LocalDict loaded: ${map.length} entries from $filePath');
      return true;
    } catch (e) {
      SjLog.severe('LocalDict load failed: $e');
      return false;
    }
  }

  static Future<Map<String, String>> _ensureCache() async {
    final p = path;
    if (p == null || p.isEmpty) return {};
    if (_cache != null && _cachePath == p) return _cache!;
    await loadFromFile(p);
    return _cache ?? {};
  }

  /// 查询词条：精确 → 忽略大小写 → 去空白。最多查前 6 个词（短语）。
  static Future<String?> lookup(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final dict = await _ensureCache();
    if (dict.isEmpty) return null;

    if (dict.containsKey(text)) return dict[text];

    final lower = text.toLowerCase();
    for (final e in dict.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }

    // 多词：优先整句，再取前几个词
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > 1) {
      if (dict.containsKey(words.join(' '))) return dict[words.join(' ')];
      final head = words.take(words.length.clamp(1, 6)).join(' ');
      if (dict.containsKey(head)) return dict[head];
      for (final e in dict.entries) {
        if (e.key.toLowerCase() == head.toLowerCase()) return e.value;
      }
    }
    return null;
  }

  static Future<int> get entryCount async {
    final dict = await _ensureCache();
    return dict.length;
  }

  static void clearCache() {
    _cache = null;
    _cachePath = null;
  }
}
