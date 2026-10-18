// lib/service/enhancement_pack/scroll_library.dart
//
// 在线书卷库：从远程目录发现并下载「书卷包」（人物 + 关系 + 世界观 + 时间线）。
//
// 为什么要它：书卷包此前只能靠别人发文件、自己导入，没有一个「发现」的地方。
// 造梦有 zaomeng-library 承担这件事，我们这边原本什么都没有。
//
// 安全取舍与插件市场保持一致：下载后**必须**校验 SHA256；
// 缺校验和、校验不符、地址非公网 https 一律拒绝。

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/plugin/plugin_security.dart';

/// 书卷库里的一个条目。
class ScrollPackEntry {
  const ScrollPackEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.downloadUrl,
    required this.sha256,
    this.bookTitle,
    this.author = '',
    this.bytes,
  });

  final String id;

  /// 书卷名（人物世界的名字）。
  final String name;

  /// 对应书名，用于提示用户挂到哪本书上。
  final String? bookTitle;
  final String description;
  final String author;
  final String downloadUrl;

  /// 下载包的 SHA256（小写十六进制）。缺失即拒绝安装。
  final String sha256;

  /// 文件大小（可选，用于展示）。
  final int? bytes;
}

/// 书卷库地址：优先 dart-define，其次用户在界面上填的地址。
class ScrollLibraryConfig {
  static const String prefsKey = 'scrollLibrary.catalogUrl';

  /// 编译期注入：`--dart-define=SCROLL_LIBRARY_URL=https://.../scrolls-catalog.json`
  static const String buildTimeUrl =
      String.fromEnvironment('SCROLL_LIBRARY_URL', defaultValue: '');

  static Future<String> resolveUrl() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString(prefsKey)?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    return buildTimeUrl;
  }

  static Future<void> saveUrl(String url) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(prefsKey, url.trim());
  }
}

/// 解析书卷库目录。
///
/// 容错是刻意的：目录由第三方维护，常见走样有
/// 「裸数组 / {items:[...]} / {packs:[...]}」三种外层，字段也可能写成驼峰或蛇形。
/// 解析不出来就跳过该条，而不是让整个库打不开。
List<ScrollPackEntry> parseScrollCatalog(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];

  dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return const [];
  }

  List<dynamic> items;
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map) {
    final rawList = decoded['items'] ?? decoded['packs'] ?? decoded['scrolls'];
    items = rawList is List ? rawList : const [];
  } else {
    return const [];
  }

  String pick(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
  }

  final out = <ScrollPackEntry>[];
  for (final item in items) {
    if (item is! Map) continue;
    final id = pick(item, ['id', 'pack_id', 'packId']);
    final name = pick(item, ['name', 'title']);
    final url = pick(item, ['downloadUrl', 'download_url', 'url']);
    final sha = pick(item, ['sha256', 'sha', 'checksum']).toLowerCase();
    // 关键字段缺一不可：没有校验和的条目直接丢弃（不做"先装上再说"）
    if (id.isEmpty || name.isEmpty || url.isEmpty || sha.isEmpty) continue;
    out.add(
      ScrollPackEntry(
        id: id,
        name: name,
        bookTitle: pick(item, ['bookTitle', 'book_title']).isEmpty
            ? null
            : pick(item, ['bookTitle', 'book_title']),
        description: pick(item, ['description', 'summary']),
        author: pick(item, ['author']),
        downloadUrl: url,
        sha256: sha,
        bytes: int.tryParse(pick(item, ['bytes', 'size'])),
      ),
    );
  }
  return out;
}

/// 书卷库客户端：拉目录、下包、校验。
class ScrollLibraryClient {
  ScrollLibraryClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// 拉取目录。地址为空时抛 [StateError]，由界面提示用户去填。
  Future<List<ScrollPackEntry>> fetchCatalog(String url) async {
    if (url.trim().isEmpty) {
      throw StateError('还没有配置书卷库地址');
    }
    if (!PluginSecurity.isSafeUrl(Uri.parse(url))) {
      throw StateError('书卷库地址必须是公网 https');
    }
    final res = await _http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 20),
        );
    if (res.statusCode != 200) {
      throw StateError('书卷库返回 HTTP ${res.statusCode}');
    }
    return parseScrollCatalog(utf8.decode(res.bodyBytes));
  }

  /// 下载并校验一个书卷包。
  ///
  /// 任何一步不符都抛错——宁可装不上，也不要装进一个被替换过的包。
  Future<Uint8List> download(ScrollPackEntry entry) async {
    if (!PluginSecurity.isSafeUrl(Uri.parse(entry.downloadUrl))) {
      throw StateError('下载地址不是公网 https');
    }
    final res = await _http.get(Uri.parse(entry.downloadUrl)).timeout(
          const Duration(seconds: 60),
        );
    if (res.statusCode != 200) {
      throw StateError('下载失败：HTTP ${res.statusCode}');
    }
    final bytes = Uint8List.fromList(res.bodyBytes);
    final actual = sha256.convert(bytes).toString().toLowerCase();
    if (actual != entry.sha256.toLowerCase()) {
      throw StateError('校验和不符，已拒绝安装');
    }
    return bytes;
  }
}
