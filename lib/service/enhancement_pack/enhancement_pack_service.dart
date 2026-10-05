// lib/service/enhancement_pack/enhancement_pack_service.dart
//
// 书籍增强包（书卷包思想）导入导出（2.4）。
// 复用工程既有 archive(ZIP) 与 characterDao，把「人物理解增强包」打成 .sjpack.zip，
// 与插件市场共用分发基建；manifest 统一 x_songjiang_* 扩展键前缀，避免污染 canonical 字段。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 增强包清单（package_manifest.json 解析 / 生成）。
class EnhancementPackManifest {
  const EnhancementPackManifest({
    required this.schemaVersion,
    required this.packType,
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.includes,
    this.createdAt,
    this.minAppVersion,
  });

  final String schemaVersion;
  final String packType;
  final String id;
  final String name;
  final String author;
  final String description;
  final List<String> includes;
  final String? createdAt;
  final String? minAppVersion;

  factory EnhancementPackManifest.fromJson(Map<String, dynamic> j) {
    final type = (j['packType'] as String? ?? 'character_graph');
    if (type != 'character_graph') {
      throw FormatException('不支持的增强包类型: $type');
    }
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw FormatException('增强包缺少 id');
    return EnhancementPackManifest(
      schemaVersion: j['schemaVersion'] as String? ?? '1.0',
      packType: type,
      id: id,
      name: j['name'] as String? ?? id,
      author: j['author'] as String? ?? '',
      description: j['description'] as String? ?? '',
      includes: (j['includes'] as List? ?? [])
          .map((e) => e as String)
          .toList(),
      createdAt: j['createdAt'] as String?,
      minAppVersion: j['x_songjiang_minApp'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'packType': packType,
        'id': id,
        'name': name,
        'author': author,
        'description': description,
        'createdAt': createdAt,
        'includes': includes,
        'x_songjiang_minApp': minAppVersion,
      };
}

/// 增强包服务：导出本书人物图谱为 .sjpack.zip，或从 zip 导入到指定书。
class EnhancementPackService {
  EnhancementPackService(this.dao);
  final CharacterDao dao;

  /// 把一本书的人物图谱导出为增强包，返回保存路径。
  Future<String> exportCharacterGraph(int bookId, String bookTitle) async {
    final cards = await dao.getCharacters(bookId);
    final relations = await dao.getRelations(bookId);
    final world = await dao.getWorldSettings(bookId);
    final timeline = await dao.getTimeline(bookId);
    if (cards.isEmpty) {
      throw StateError('本书暂无人物数据，无法导出增强包');
    }
    final graph = {
      'characters': cards.map((c) => c.toMap()).toList(),
      'relations': relations.map((r) => r.toMap()).toList(),
      'world': world.map((w) => w.toMap()).toList(),
      'timeline': timeline.map((t) => t.toMap()).toList(),
    };
    final manifest = EnhancementPackManifest(
      schemaVersion: '1.0',
      packType: 'character_graph',
      id: 'com.songjiang.pack.${bookId}_'
          '${DateTime.now().millisecondsSinceEpoch}',
      name: '$bookTitle · 人物关系包',
      author: 'songjiang-local',
      description: '由松江阅导出的角色理解增强包（${cards.length} 人）',
      includes: ['graph.json'],
      createdAt: DateTime.now().toIso8601String(),
      minAppVersion: '1.0.0',
    );
    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
    final graphBytes = utf8.encode(jsonEncode(graph));
    archive.addFile(ArchiveFile('package_manifest.json', manifestBytes.length, manifestBytes));
    archive.addFile(ArchiveFile('graph.json', graphBytes.length, graphBytes));
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw StateError('打包失败');
    final dir = await getApplicationDocumentsDirectory();
    final packDir = Directory('${dir.path}/packs');
    if (!await packDir.exists()) await packDir.create(recursive: true);
    final file = File('${packDir.path}/${manifest.id}.sjpack.zip');
    await file.writeAsBytes(encoded, flush: true);
    SjLog.info('EnhancementPack: 已导出 ${file.path}');
    return file.path;
  }

  /// 从 .sjpack.zip 导入人物图谱到指定书（整图替换）。
  Future<int> importCharacterGraph(int bookId, Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final manifestFile = archive.findFile('package_manifest.json');
    if (manifestFile == null) {
      throw StateError('增强包缺少 package_manifest.json');
    }
    EnhancementPackManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>,
    ); // 校验类型 / id。
    final graphFile = archive.findFile('graph.json');
    if (graphFile == null) throw StateError('增强包缺少 graph.json');
    final graph =
        jsonDecode(utf8.decode(graphFile.content)) as Map<String, dynamic>;
    final now = DateTime.now();
    final cards = _list(graph['characters'])
        .map((m) => CharacterCard.fromMap(_withBook(m, bookId, now)))
        .toList();
    final relations = _list(graph['relations'])
        .map((m) => CharacterRelation.fromMap(_withBook(m, bookId, now)))
        .toList();
    final world = _list(graph['world'])
        .map((m) => WorldSetting.fromMap(_withBook(m, bookId, now)))
        .toList();
    final timeline = _list(graph['timeline'])
        .map((m) => TimelineEvent.fromMap(_withBook(m, bookId, now)))
        .toList();
    await dao.replaceBookGraph(
      bookId: bookId,
      characters: cards,
      relations: relations,
      settings: world,
      events: timeline,
    );
    SjLog.info('EnhancementPack: 已导入 ${cards.length} 人 / ${relations.length} 关系');
    return cards.length;
  }

  /// 用文件选择器读取一个 .sjpack.zip 的字节。
  static Future<Uint8List?> pickPackBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'sjpack'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return File(path).readAsBytes();
  }

  static List<Map<String, dynamic>> _list(Object? raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  static Map<String, dynamic> _withBook(
    Map<String, dynamic> m,
    int bookId,
    DateTime now,
  ) {
    final copy = {...m};
    copy['book_id'] = bookId;
    copy['source'] = 'pack_import';
    copy['created_at'] = now.toIso8601String();
    copy['updated_at'] = now.toIso8601String();
    copy.remove('id');
    return copy;
  }
}
