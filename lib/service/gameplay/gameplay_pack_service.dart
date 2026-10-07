// lib/service/gameplay/gameplay_pack_service.dart
//
// 玩法包服务（3.3）：导入导出 .sjgame.zip、已安装包持久化、激活为插件、名场面卡分享。
//
// 复用：
// - 2.4 增强包的 archive(ZIP) 打/解包思路；manifest 同样走 x_songjiang_* 扩展键。
// - 2.3 插件系统：activatePack 把脚本工具编译为 PluginManifest 注入 PluginRegistry。
// - 松江阅既有 file_picker / path_provider / shared_preferences / share_plus。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_models.dart';
import 'package:songjiang_reader/utils/log/common.dart';

const String _installedKey = 'gameplay.installedPacks';
const String _activatedKey = 'gameplay.activatedPacks';

/// 玩法包服务（单例）。
class GameplayPackService {
  GameplayPackService._();

  static final GameplayPackService instance = GameplayPackService._();

  /// 把玩法包打成 .sjgame.zip（内部单一 package_manifest.json，信息零损耗）。
  Future<Uint8List> exportPack(GameplayPackManifest manifest) async {
    final archive = Archive();
    final manifestJson = jsonEncode(manifest.toJson());
    archive.addFile(
      ArchiveFile(
        'package_manifest.json',
        utf8.encode(manifestJson).length,
        utf8.encode(manifestJson),
      ),
    );
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// 导入玩法包（.sjgame.zip 或兼容 .zip），解析并校验 manifest。
  Future<GameplayPackManifest> importPack(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.files
        .where((f) => f.name == 'package_manifest.json')
        .firstOrNull;
    if (manifestFile == null) {
      throw FormatException('玩法包缺少 package_manifest.json');
    }
    final text = utf8.decode(manifestFile.content as List<int>);
    final map = jsonDecode(text) as Map<String, dynamic>;
    return GameplayPackManifest.fromJson(map);
  }

  /// 文件选择器：选 .sjgame / .zip 玩法包，返回字节；取消返回 null。
  static Future<Uint8List?> pickPackBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sjgame', 'zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.bytes;
  }

  /// 已安装玩法包清单（持久化于应用支持目录）。
  Future<List<GameplayPackManifest>> listInstalled() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_installedKey) ?? [];
      return list
          .map((e) => GameplayPackManifest.fromJson(
                jsonDecode(e) as Map<String, dynamic>,
              ))
          .toList();
    } catch (e) {
      SjLog.warning('Gameplay: 读取已安装玩法包失败: $e');
      return const [];
    }
  }

  /// 保存（安装）一个玩法包（同 id 覆盖）。
  Future<void> saveInstalled(GameplayPackManifest manifest) async {
    final all = await listInstalled();
    all.removeWhere((m) => m.id == manifest.id);
    all.add(manifest);
    await _persist(all);
  }

  /// 移除已安装玩法包（同时卸载其注入的插件工具）。
  Future<void> removeInstalled(String id) async {
    final all = await listInstalled();
    all.removeWhere((m) => m.id == id);
    await _persist(all);
    await _unmarkActivated(id);
    try {
      PluginRegistry.instance.unload(id);
    } catch (_) {
      // 该包可能未激活为插件，忽略。
    }
  }

  /// 已激活（注入插件系统）的玩法包 id 集合（持久化，重启后仍记得）。
  Future<Set<String>> activatedIds() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return (sp.getStringList(_activatedKey) ?? const <String>[]).toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<void> _markActivated(String id) async {
    final sp = await SharedPreferences.getInstance();
    final set = (sp.getStringList(_activatedKey) ?? const <String>[]).toSet();
    set.add(id);
    await sp.setStringList(_activatedKey, set.toList());
  }

  Future<void> _unmarkActivated(String id) async {
    final sp = await SharedPreferences.getInstance();
    final set = (sp.getStringList(_activatedKey) ?? const <String>[]).toSet();
    set.remove(id);
    await sp.setStringList(_activatedKey, set.toList());
  }

  Future<void> _persist(List<GameplayPackManifest> all) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(
      _installedKey,
      all.map((m) => jsonEncode(m.toJson())).toList(),
    );
  }

  /// 激活玩法包为插件：把 scriptTools 编译注入 PluginRegistry（与 2.3 打通）。
  /// 仅 reading_script 包有脚本工具；其余类型激活为「已启用内容包」，不影响 AI 内核。
  /// 返回注入的工具数量（0 表示无脚本工具）。
  int activatePack(GameplayPackManifest manifest) {
    if (manifest.scriptTools.isEmpty) return 0;
    PluginRegistry.instance.loadManifest(manifest.toPluginManifest());
    unawaited(_markActivated(manifest.id));
    return manifest.scriptTools.length;
  }

  /// 进入玩法中心时调用：把此前已激活的脚本包重新注入插件系统（重启后恢复能力）。
  Future<void> restoreActivated(
      List<GameplayPackManifest> installed) async {
    final activated = await activatedIds();
    for (final m in installed) {
      if (activated.contains(m.id) && m.scriptTools.isNotEmpty) {
        try {
          PluginRegistry.instance.loadManifest(m.toPluginManifest());
        } catch (_) {
          // 忽略个别失败，不阻断其余恢复。
        }
      }
    }
  }

  /// 名场面卡分享文案（复用松江阅既有笔记卡片导出 + 卡片分享思路）。
  static String buildSceneCardShareText(SceneCard card) {
    final buf = StringBuffer();
    buf.writeln('「${card.quote}」');
    if (card.chapter != null && card.chapter!.isNotEmpty) {
      buf.writeln('—— 《${card.bookTitle}》${card.chapter}');
    } else {
      buf.writeln('—— 《${card.bookTitle}》');
    }
    if (card.context != null && card.context!.isNotEmpty) {
      buf.writeln('\n${card.context}');
    }
    if (card.tags.isNotEmpty) {
      buf.writeln('\n#${card.tags.join(' #')}');
    }
    buf.writeln('\n—— 来自松江阅 · 名场面卡');
    return buf.toString();
  }

  /// 系统分享名场面卡（share_plus）。
  static Future<void> shareSceneCard(SceneCard card) async {
    await Share.share(buildSceneCardShareText(card));
  }
}
