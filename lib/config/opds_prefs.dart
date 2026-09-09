import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/models/opds_catalog.dart';
import 'package:uuid/uuid.dart';

/// OPDS 书源列表的领域访问层。
class OpdsPrefs {
  OpdsPrefs._();

  static const String catalogsKey = 'opdsCatalogs';
  static const _uuid = Uuid();

  static SharedPreferences? _sp;

  static Future<void> ensureInitialized() async {
    _sp = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _require {
    final sp = _sp;
    if (sp == null) {
      throw StateError(
        'OpdsPrefs.ensureInitialized() 未调用（应在 main 中 Prefs 初始化后）',
      );
    }
    return sp;
  }

  static List<OpdsCatalog> get catalogs {
    final raw = _require.getString(catalogsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(OpdsCatalog.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveCatalogs(List<OpdsCatalog> list) async {
    await _require.setString(
      catalogsKey,
      jsonEncode(list.map((c) => c.toJson()).toList()),
    );
  }

  static Future<OpdsCatalog> addCatalog({
    required String name,
    required String url,
    String? username,
    String? password,
  }) async {
    final catalog = OpdsCatalog(
      id: _uuid.v4(),
      name: name.trim(),
      url: url.trim(),
      username: username?.trim(),
      password: password,
    );
    final list = [...catalogs, catalog];
    await saveCatalogs(list);
    return catalog;
  }

  static Future<void> updateCatalog(OpdsCatalog catalog) async {
    final list = catalogs
        .map((c) => c.id == catalog.id ? catalog : c)
        .toList();
    await saveCatalogs(list);
  }

  static Future<void> removeCatalog(String id) async {
    final list = catalogs.where((c) => c.id != id).toList();
    await saveCatalogs(list);
  }
}
