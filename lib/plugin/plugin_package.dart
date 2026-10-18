// lib/plugin/plugin_package.dart
//
// 本地插件包：从文件安装 .plugin.zip / plugin.json。
//
// 补齐的是插件开发文档里记录的那条缺口——「写了插件却发不出去」：
// 此前只有插件市场与随包预置两条路，没有本地安装入口。
//
// 同时补上包体约束（造梦有、我们此前没有）：
// 大小上限、文件数上限、解压总量上限、拒绝路径穿越与绝对路径。
// 本地包虽由用户自己选择，仍然要校验——用户并不知道自己拿到的是什么。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:songjiang_reader/plugin/plugin_registry.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 插件包不合法时抛出，消息直接给用户看。
class PluginPackageException implements Exception {
  PluginPackageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 包体约束（对齐造梦的公开限制，作为本项目的基线）。
class PluginPackageLimits {
  /// ZIP 本体上限。
  static const int maxArchiveBytes = 10 * 1024 * 1024;

  /// 归档内条目数上限。
  static const int maxEntries = 500;

  /// 解压后总量上限。
  static const int maxTotalUncompressed = 100 * 1024 * 1024;

  /// 清单文件名。
  static const String manifestFileName = 'plugin.json';
}

/// 检查归档条目路径是否安全。返回 null 表示安全，否则返回原因。
///
/// 拒绝的形态：绝对路径（`/x`、`C:\x`）、`..` 穿越、以及 Windows 盘符。
String? unsafeArchiveEntryPath(String name) {
  final n = name.replaceAll('\\', '/').trim();
  if (n.isEmpty) return '空路径';
  if (n.startsWith('/')) return '绝对路径';
  if (RegExp(r'^[A-Za-z]:').hasMatch(n)) return '带盘符的路径';
  for (final seg in n.split('/')) {
    if (seg == '..') return '包含 .. 路径穿越';
  }
  return null;
}

/// 在归档里找清单文件：允许放在 ZIP 根，或第一层目录下。
ArchiveFile? _findManifest(Archive archive) {
  final direct = archive.findFile(PluginPackageLimits.manifestFileName);
  if (direct != null) return direct;
  for (final f in archive.files) {
    final n = f.name.replaceAll('\\', '/');
    if (n.endsWith('/${PluginPackageLimits.manifestFileName}')) {
      // 只接受第一层目录，防止在深层目录里藏清单
      if ('/'.allMatches(n).length == 1) return f;
    }
  }
  return null;
}

/// 从字节解析插件清单。
///
/// 支持两种输入：
///  * `.plugin.zip`：ZIP 内含 `plugin.json`（根或第一层目录）
///  * 裸 `plugin.json` 文本
///
/// 任何不合规都抛 [PluginPackageException]，消息可直接展示。
PluginManifest readPluginManifestFromBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw PluginPackageException('文件是空的');
  }

  // 先按 JSON 试：裸 plugin.json 是合法场景
  final looksLikeZip = bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B; // "PK"

  if (!looksLikeZip) {
    if (bytes.length > PluginPackageLimits.maxArchiveBytes) {
      throw PluginPackageException('清单文件过大');
    }
    final text = _decodeText(bytes);
    return _parseManifestText(text);
  }

  if (bytes.length > PluginPackageLimits.maxArchiveBytes) {
    throw PluginPackageException(
      '压缩包超过 ${PluginPackageLimits.maxArchiveBytes ~/ (1024 * 1024)} MB 上限',
    );
  }

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw PluginPackageException('压缩包无法解开：$e');
  }

  if (archive.files.length > PluginPackageLimits.maxEntries) {
    throw PluginPackageException(
      '压缩包内文件过多（${archive.files.length} > ${PluginPackageLimits.maxEntries}）',
    );
  }

  var total = 0;
  for (final f in archive.files) {
    final unsafe = unsafeArchiveEntryPath(f.name);
    if (unsafe != null) {
      throw PluginPackageException('压缩包内含不安全路径（$unsafe）：${f.name}');
    }
    total += f.size;
    if (total > PluginPackageLimits.maxTotalUncompressed) {
      throw PluginPackageException(
        '解压后体积超过 ${PluginPackageLimits.maxTotalUncompressed ~/ (1024 * 1024)} MB 上限',
      );
    }
  }

  final manifestFile = _findManifest(archive);
  if (manifestFile == null) {
    throw PluginPackageException('压缩包里没有 ${PluginPackageLimits.manifestFileName}');
  }
  return _parseManifestText(_decodeText(manifestFile.content as List<int>));
}

String _decodeText(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    throw PluginPackageException('清单不是 UTF-8 文本');
  }
}

PluginManifest _parseManifestText(String text) {
  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw PluginPackageException('清单必须是 JSON 对象');
    }
    json = decoded.cast<String, dynamic>();
  } on PluginPackageException {
    rethrow;
  } catch (e) {
    throw PluginPackageException('清单不是合法 JSON：$e');
  }

  try {
    final manifest = PluginManifest.fromJson(json);
    _validateManifest(manifest);
    return manifest;
  } on PluginPackageException {
    rethrow;
  } catch (e) {
    // fromJson 对缺字段会抛类型错误，这里翻成人话
    throw PluginPackageException('清单字段不完整：$e');
  }
}

/// 清单自检：必填项、id 可用性、贡献与配方是否对得上。
void _validateManifest(PluginManifest manifest) {
  if (manifest.id.trim().isEmpty) {
    throw PluginPackageException('清单缺少 id');
  }
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(manifest.id)) {
    throw PluginPackageException('id 只能包含字母、数字、下划线、点和连字符');
  }
  if (manifest.name.trim().isEmpty) {
    throw PluginPackageException('清单缺少 name');
  }
  if (manifest.tools.isEmpty && manifest.hooks.isEmpty) {
    throw PluginPackageException('插件既没有工具也没有钩子，装上也不会有任何作用');
  }
  final ids = manifest.tools.map((t) => t.id).toSet();
  for (final hook in manifest.hooks) {
    if (!ids.contains(hook.toolId)) {
      throw PluginPackageException(
        '钩子引用了不存在的工具：${hook.toolId}',
      );
    }
  }
  for (final tool in manifest.tools) {
    if (tool.id.trim().isEmpty) {
      throw PluginPackageException('有工具缺少 id');
    }
    if (tool.behavior == PluginToolBehavior.aiPrompt &&
        (tool.prompt == null || tool.prompt!.trim().isEmpty)) {
      throw PluginPackageException('工具 ${tool.id} 是 aiPrompt，但没有 prompt');
    }
    if (tool.behavior == PluginToolBehavior.llmChain && tool.steps.isEmpty) {
      throw PluginPackageException('工具 ${tool.id} 是 llmChain，但没有 steps');
    }
  }
}

/// 安装：落盘 + 注册 + 默认禁用。
///
/// 落盘是为了重启后还在——注册表启动时会扫 `<appSupport>/plugins/*.plugin.json`，
/// 但 `loadManifest` 本身只改内存。
Future<void> installPluginPackage(PluginManifest manifest) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'plugins'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final safeId = manifest.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  final file = File(p.join(dir.path, '$safeId.plugin.json'));
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(_manifestToJson(manifest)),
  );

  PluginRegistry.instance.loadManifest(manifest);
  // 第三方插件默认关闭：装完要让用户自己决定是否启用
  PluginRegistry.instance.setEnabled(manifest.id, false);
  SjLog.info('Plugin: 已从文件安装 ${manifest.id}');
}

/// 把对象重新序列化回清单 JSON（用于持久化）。
Map<String, dynamic> _manifestToJson(PluginManifest m) => {
      'schemaVersion': m.schemaVersion,
      'id': m.id,
      'name': m.name,
      'version': m.version,
      'description': m.description,
      'author': m.author,
      if (m.minAppVersion != null) 'minAppVersion': m.minAppVersion,
      'permissions': m.permissions.map((p) => p.value).toList(),
      'hooks': [
        for (final h in m.hooks)
          {
            'event': h.event.name,
            'tool': h.toolId,
            if (h.ui != null) 'ui': h.ui,
          },
      ],
      'tools': [
        for (final t in m.tools)
          {
            'id': t.id,
            'displayName': t.displayName,
            'description': t.description,
            'inputSchema': t.inputSchema,
            'behavior': t.behavior.name,
            if (t.prompt != null) 'prompt': t.prompt,
            if (t.model != null) 'model': t.model,
            if (t.steps.isNotEmpty)
              'steps': [
                for (final s in t.steps) {'prompt': s.prompt, 'as': s.as},
              ],
          },
      ],
    };

/// 选文件并读出字节（`.plugin.zip` 或 `plugin.json`）。
Future<Uint8List?> pickPluginPackageBytes() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['zip', 'json'],
    withData: true,
  );
  final file = result?.files.firstOrNull;
  if (file == null) return null;
  if (file.bytes != null) return file.bytes;
  if (file.path == null) return null;
  try {
    return await File(file.path!).readAsBytes();
  } catch (e) {
    SjLog.warning('Plugin: 读取插件文件失败: $e');
    return null;
  }
}
/// 安装前确认：把插件要什么原原本本摆给用户看。
///
/// 不做"装完再说"——权限是用户唯一能判断这个插件该不该信的依据。
Future<bool> confirmPluginInstall(
  BuildContext context,
  PluginManifest manifest,
) async {
  final permissions = manifest.permissions.isEmpty
      ? '（未声明任何权限）'
      : manifest.permissions.map((p) => p.value).join('\n');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('安装「${manifest.name}」'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本：${manifest.version}'
                '${manifest.author.isEmpty ? '' : '　作者：${manifest.author}'}'),
            if (manifest.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(manifest.description),
            ],
            const SizedBox(height: 12),
            Text('需要的能力（${manifest.permissions.length} 项）'),
            const SizedBox(height: 4),
            Text(permissions, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Text('工具：${manifest.tools.length} 个'
                '${manifest.hooks.isEmpty ? '' : '，事件钩子：${manifest.hooks.length} 个'}'),
            const SizedBox(height: 8),
            const Text(
              '安装后默认保持关闭，需要你手动启用才会生效。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('安装'),
        ),
      ],
    ),
  );
  return ok ?? false;
}