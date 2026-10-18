import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/plugin/plugin_package.dart';

/// 本地插件包的解析与拒绝分支。
///
/// 这条链路的风险点很集中：用户并不知道自己手里那个 zip 是什么。
/// 所以测试不只要覆盖"能装"，更要覆盖**每一种该被拒的形态**——
/// 拒绝分支写漏一个，就是一个可以绕过校验的入口。
void main() {
  String manifestJson({
    String id = 'com.example.demo',
    String name = '示例插件',
    String tools = '[{"id":"t1","displayName":"工具","description":"d",'
        '"inputSchema":{"type":"object"},"behavior":"aiPrompt","prompt":"p {{x}}"}],',
    String hooks = '[{"event":"onSelectText","tool":"t1"}],',
  }) =>
      '{"schemaVersion":"1.0","id":"$id","name":"$name","version":"1.0.0",'
      '"author":"me","permissions":["ai.query"],"hooks":$hooks"tools":$tools}'
      .replaceAll(',}', '}');

  String goodJson() => manifestJson();

  Uint8List zipOf(Map<String, String> files) {
    final archive = Archive();
    for (final e in files.entries) {
      final bytes = utf8.encode(e.value);
      archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive)!;
    return Uint8List.fromList(encoded);
  }

  group('裸 plugin.json', () {
    test('合法清单能解析出工具与钩子', () {
      final m = readPluginManifestFromBytes(
        Uint8List.fromList(utf8.encode(goodJson())),
      );
      expect(m.id, 'com.example.demo');
      expect(m.tools.length, 1);
      expect(m.hooks.length, 1);
      expect(m.permissions.single.value, 'ai.query');
    });

    test('空文件被拒', () {
      expect(
        () => readPluginManifestFromBytes(Uint8List(0)),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('不是 JSON 被拒', () {
      expect(
        () => readPluginManifestFromBytes(
          Uint8List.fromList(utf8.encode('not json')),
        ),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('缺 name 被拒', () {
      final raw = goodJson().replaceFirst('"name":"示例插件",', '');
      expect(
        () => readPluginManifestFromBytes(Uint8List.fromList(utf8.encode(raw))),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('id 含非法字符被拒', () {
      final raw = manifestJson(id: 'a/b');
      expect(
        () => readPluginManifestFromBytes(Uint8List.fromList(utf8.encode(raw))),
        throwsA(isA<PluginPackageException>()),
      );
    });
  });

  group('ZIP 包', () {
    test('清单在根目录', () {
      final bytes = zipOf({'plugin.json': goodJson(), 'readme.md': 'hi'});
      expect(readPluginManifestFromBytes(bytes).id, 'com.example.demo');
    });

    test('清单在第一层目录（符合打包习惯）', () {
      final bytes = zipOf({'my-plugin/plugin.json': goodJson()});
      expect(readPluginManifestFromBytes(bytes).id, 'com.example.demo');
    });

    test('没有 plugin.json 被拒', () {
      final bytes = zipOf({'readme.md': 'hi'});
      expect(
        () => readPluginManifestFromBytes(bytes),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('含 .. 路径穿越被拒', () {
      final bytes = zipOf({
        'plugin.json': goodJson(),
        '../evil.txt': 'x',
      });
      expect(
        () => readPluginManifestFromBytes(bytes),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('含绝对路径被拒', () {
      final bytes = zipOf({'plugin.json': goodJson(), '/etc/passwd': 'x'});
      expect(
        () => readPluginManifestFromBytes(bytes),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('非 zip 的二进制会被当成文本解析并拒绝', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => readPluginManifestFromBytes(bytes),
        throwsA(isA<PluginPackageException>()),
      );
    });
  });

  group('清单自检', () {
    test('钩子引用不存在的工具被拒', () {
      final raw = manifestJson(hooks: '[{"event":"onSelectText","tool":"nope"}],');
      expect(
        () => readPluginManifestFromBytes(Uint8List.fromList(utf8.encode(raw))),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('aiPrompt 没有 prompt 被拒', () {
      final raw = '{"id":"a.b","name":"n","version":"1","tools":'
          '[{"id":"t","displayName":"d","description":"","inputSchema":{},'
          '"behavior":"aiPrompt"}]}';
      expect(
        () => readPluginManifestFromBytes(Uint8List.fromList(utf8.encode(raw))),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('llmChain 没有 steps 被拒', () {
      final raw = '{"id":"a.b","name":"n","version":"1","tools":'
          '[{"id":"t","displayName":"d","description":"","inputSchema":{},'
          '"behavior":"llmChain"}]}';
      expect(
        () => readPluginManifestFromBytes(Uint8List.fromList(utf8.encode(raw))),
        throwsA(isA<PluginPackageException>()),
      );
    });

    test('既无工具也无钩子被拒（装上没用）', () {
      const raw = '{"id":"a.b","name":"n","version":"1","tools":[]}';
      expect(
        () => readPluginManifestFromBytes(Uint8List.fromList(utf8.encode(raw))),
        throwsA(isA<PluginPackageException>()),
      );
    });
  });

  group('unsafeArchiveEntryPath', () {
    test('普通路径安全', () {
      expect(unsafeArchiveEntryPath('plugin.json'), isNull);
      expect(unsafeArchiveEntryPath('dir/sub/a.txt'), isNull);
    });

    test('绝对路径 / 盘符 / 穿越都不安全', () {
      expect(unsafeArchiveEntryPath('/etc/passwd'), isNotNull);
      expect(unsafeArchiveEntryPath('C:\\Windows\\x'), isNotNull);
      expect(unsafeArchiveEntryPath('a/../../b'), isNotNull);
      expect(unsafeArchiveEntryPath('..'), isNotNull);
      expect(unsafeArchiveEntryPath(''), isNotNull);
    });
  });
}
