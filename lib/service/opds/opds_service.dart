import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:songjiang_reader/models/opds_catalog.dart';
import 'package:songjiang_reader/utils/get_path/get_temp_dir.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:xml/xml.dart';

/// OPDS（Open Publication Distribution System）客户端。
///
/// 解析 Atom catalog feed，支持获取子目录与下载 acquisition 资源。
class OpdsService {
  OpdsService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Options _options(OpdsCatalog catalog) {
    final headers = <String, dynamic>{
      'Accept': 'application/atom+xml, application/xml, text/xml, */*',
    };
    if (catalog.hasAuth) {
      final token = base64Encode(
        utf8.encode('${catalog.username ?? ''}:${catalog.password ?? ''}'),
      );
      headers['Authorization'] = 'Basic $token';
    }
    return Options(headers: headers);
  }

  /// 拉取并解析一个 OPDS feed。
  Future<OpdsFeed> loadFeed(
    OpdsCatalog catalog,
    String url, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    SjLog.info('OPDS load: $url');
    final response = await _dio.get<List<int>>(
      url,
      options: _options(catalog)
        ..receiveTimeout = timeout
        ..connectTimeout = timeout,
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Empty OPDS response');
    }
    final xmlText = _decodeXml(bytes);
    return parseFeedXml(xmlText, baseUrl: url);
  }

  /// 从根 URL 加载（相对链接按 baseUrl 解析）。
  Future<OpdsFeed> loadRoot(OpdsCatalog catalog) =>
      loadFeed(catalog, catalog.url);

  Future<OpdsFeed> openNavigation(
    OpdsCatalog catalog,
    String subsectionUrl,
  ) =>
      loadFeed(catalog, subsectionUrl);

  /// 下载 acquisition 资源到临时目录，返回本地文件。
  Future<File> downloadAcquisition(
    OpdsCatalog catalog,
    OpdsAcquisitionLink link, {
    void Function(int received, int total)? onProgress,
  }) async {
    final tempDir = await getSjTempDir();
    var name = _fileNameFromUrl(link.href);
    if (!name.contains('.')) {
      name = '$name.${link.fileExtension}';
    }
    // 避免覆盖
    var targetPath = p.join(tempDir.path, name);
    var i = 1;
    while (await File(targetPath).exists()) {
      final base = p.basenameWithoutExtension(name);
      final ext = p.extension(name);
      targetPath = p.join(tempDir.path, '${base}_$i$ext');
      i++;
    }

    final cancelToken = CancelToken();
    await _dio.download(
      link.href,
      targetPath,
      options: _options(catalog),
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
    SjLog.info('OPDS downloaded: $targetPath');
    return File(targetPath);
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url;
    final name = p.basename(path);
    if (name.isEmpty || name == '/' || name.contains('?')) {
      return 'book_${DateTime.now().millisecondsSinceEpoch}';
    }
    return Uri.decodeComponent(name);
  }

  String _decodeXml(List<int> bytes) {
    // 尝试 UTF-8，失败再试 Latin-1（OPDS 常见编码）
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}

const String _opdsAcquisition = 'http://opds-spec.org/acquisition';
const String _opdsImage = 'http://opds-spec.org/image';
const String _opdsImageThumb = 'http://opds-spec.org/image/thumbnail';
const String _opdsSubsection = 'subsection';

/// 解析 OPDS Atom XML（便于单测，不依赖网络）。
OpdsFeed parseFeedXml(String xmlText, {String? baseUrl}) {
  final document = XmlDocument.parse(xmlText);
  final feed = document.rootElement;

  String? textOf(XmlElement parent, String name) {
    return parent.findElements(name).firstOrNull?.innerText.trim();
  }

  String resolveHref(String href) {
    if (baseUrl == null || href.isEmpty) return href;
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    return Uri.parse(baseUrl).resolve(href).toString();
  }

  final feedTitle = textOf(feed, 'title') ?? 'OPDS';

  String? nextUrl;
  String? selfUrl;
  for (final link in feed.childElements.where((e) => e.name.local == 'link')) {
    final rel = link.getAttribute('rel');
    final href = link.getAttribute('href');
    if (href == null) continue;
    if (rel == 'next') nextUrl = resolveHref(href);
    if (rel == 'self') selfUrl = resolveHref(href);
  }

  final entries = <OpdsEntry>[];
  for (final entry in feed.childElements.where((e) => e.name.local == 'entry')) {
    final title = textOf(entry, 'title') ?? '(untitled)';
    final summary = textOf(entry, 'summary') ?? textOf(entry, 'content');
    final id = textOf(entry, 'id');

    String? author;
    final authorEl = entry.findElements('author').firstOrNull;
    if (authorEl != null) {
      author = textOf(authorEl, 'name');
    }

    String? coverUrl;
    final acquisitions = <OpdsAcquisitionLink>[];
    String? subsectionUrl;

    for (final link
        in entry.childElements.where((e) => e.name.local == 'link')) {
      final rel = link.getAttribute('rel') ?? '';
      final href = link.getAttribute('href');
      final type = link.getAttribute('type') ?? '';
      final linkTitle = link.getAttribute('title');
      final lengthStr = link.getAttribute('length');
      final length = lengthStr != null ? int.tryParse(lengthStr) : null;
      if (href == null || href.isEmpty) continue;
      final resolved = resolveHref(href);

      if (rel == _opdsImage || rel == _opdsImageThumb) {
        coverUrl ??= resolved;
      } else if (rel.startsWith(_opdsAcquisition) ||
          rel == 'http://opds-spec.org/acquisition/open-access') {
        acquisitions.add(OpdsAcquisitionLink(
          href: resolved,
          type: type,
          title: linkTitle,
          length: length,
        ));
      } else if (rel == _opdsSubsection ||
          (type.contains('opds-catalog') && acquisitions.isEmpty)) {
        subsectionUrl ??= resolved;
      }
    }

    entries.add(OpdsEntry(
      title: title,
      author: author,
      summary: summary,
      id: id,
      coverUrl: coverUrl,
      acquisitions: acquisitions,
      subsectionUrl: subsectionUrl,
    ));
  }

  return OpdsFeed(
    title: feedTitle,
    entries: entries,
    nextUrl: nextUrl,
    selfUrl: selfUrl,
  );
}

// 避免依赖 collection 的 firstOrNull 扩展在部分环境缺失
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
