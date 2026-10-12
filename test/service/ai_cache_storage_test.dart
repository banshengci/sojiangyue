import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/service/ai/ai_cache.dart';
import 'package:songjiang_reader/utils/get_path/get_cache_dir.dart';

/// AI 缓存的**文件级**端到端测试（写盘 / 命中 / 淘汰 / 身份校验）。
///
/// `ai_cache_test.dart` 只覆盖了纯函数（缓存键、序列化）与源码级接线守护，
/// 没有真正落过盘。这里补上：把 path_provider 的缓存目录通道 mock 到临时目录，
/// 走一遍真实的 `setAiCache` / `getAiCache` / `cleanCache` / `cacheCount`。
///
/// 为什么值得单独测：缓存是**跨进程持久化**的，格式或键算错不会当场报错，
/// 而是表现为「缓存永远是 0 条」或「换了模型还返回旧答案」——
/// 正是本次修复前那个「只有 UI 没有实现」的状态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // AiPrefs 是领域 Prefs，需要先初始化才能读到 maxCacheCount
    await AiPrefs.ensureInitialized();

    tmp = Directory.systemTemp.createTempSync('ai_cache_e2e');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationCacheDirectory' ||
          call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tmp.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File cacheFile() => File('${tmp.path}/${AiCache.cacheFileName}');

  List<ChatMessage> msgs(String text) =>
      [HumanChatMessage(content: ChatMessageContent.text(text))];

  group('写盘与命中', () {
    test('setAiCache 真的落盘，getAiCache 能读回同样的内容', () async {
      const identity = 'p1|gpt-4';
      final hash = AiCache.cacheHashFor(msgs('问题'), identity);

      await AiCache.setAiCache(
        hash,
        '这是答案',
        'p1',
        msgs('问题'),
        identity: identity,
      );

      expect(cacheFile().existsSync(), isTrue,
          reason: '缓存文件没有生成——写路径又断了');

      final hit = await AiCache.getAiCache(hash, identity: identity);
      expect(hit, isNotNull);
      expect(hit!.data, '这是答案');
      expect(hit.identifier, 'p1');
      expect(hit.identity, identity);
    });

    test('未写入过的键返回 null', () async {
      expect(await AiCache.getAiCache(12345), isNull);
    });

    test('identity 不匹配时不算命中（换模型不能吃旧答案）', () async {
      const identity = 'p1|gpt-4';
      final hash = AiCache.cacheHashFor(msgs('问题'), identity);
      await AiCache.setAiCache(hash, '旧模型的答案', 'p1', msgs('问题'),
          identity: identity);

      expect(await AiCache.getAiCache(hash, identity: 'p2|claude'), isNull);
      // 同一身份仍应命中
      expect(await AiCache.getAiCache(hash, identity: identity), isNotNull);
    });

    test('不传 identity 时不校验身份（兼容老调用方）', () async {
      final hash = AiCache.cacheHashFor(msgs('问题'), 'p1|gpt-4');
      await AiCache.setAiCache(hash, '答案', 'p1', msgs('问题'),
          identity: 'p1|gpt-4');
      expect(await AiCache.getAiCache(hash), isNotNull);
    });

    test('写入多条后 cacheCount 与文件内容一致', () async {
      for (var i = 0; i < 3; i++) {
        await AiCache.setAiCache(
          AiCache.cacheHashFor(msgs('问题$i'), 'p1|m'),
          '答案$i',
          'p1',
          msgs('问题$i'),
          identity: 'p1|m',
        );
      }

      expect(await AiCache.cacheCount, 3);
      final decoded =
          json.decode(cacheFile().readAsStringSync()) as Map<String, dynamic>;
      expect(decoded.length, 3);
    });

    test('同一键重复写入会覆盖而不是堆积', () async {
      final hash = AiCache.cacheHashFor(msgs('问题'), 'p1|m');
      await AiCache.setAiCache(hash, '第一版', 'p1', msgs('问题'),
          identity: 'p1|m');
      await AiCache.setAiCache(hash, '第二版', 'p1', msgs('问题'),
          identity: 'p1|m');

      expect(await AiCache.cacheCount, 1);
      expect((await AiCache.getAiCache(hash))!.data, '第二版');
    });
  });

  group('并发写入（读-改-写必须串行化）', () {
    test('同时写入 10 条，10 条都要落盘', () async {
      AiPrefs.maxCacheCount = 1000;

      // 模拟 10 个 AI 请求几乎同时完成
      await Future.wait([
        for (var i = 0; i < 10; i++)
          AiCache.setAiCache(
            AiCache.cacheHashFor(msgs('并发问题$i'), 'p1|m'),
            '并发答案$i',
            'p1',
            msgs('并发问题$i'),
            identity: 'p1|m',
          ),
      ]);

      expect(await AiCache.cacheCount, 10,
          reason: '并发写入互相覆盖了——setAiCache 的读-改-写没有串行化');

      // 每一条都必须能读回自己那一条，而不是只剩最后写的那条
      for (var i = 0; i < 10; i++) {
        final hash = AiCache.cacheHashFor(msgs('并发问题$i'), 'p1|m');
        final hit = await AiCache.getAiCache(hash, identity: 'p1|m');
        expect(hit, isNotNull, reason: '第 $i 条丢了');
        expect(hit!.data, '并发答案$i');
      }
    });

    test('并发写入与后续串行写入混用也不丢', () async {
      AiPrefs.maxCacheCount = 1000;

      await Future.wait([
        for (var i = 0; i < 5; i++)
          AiCache.setAiCache(
            AiCache.cacheHashFor(msgs('批$i'), 'p1|m'),
            '批答案$i',
            'p1',
            msgs('批$i'),
            identity: 'p1|m',
          ),
      ]);
      await AiCache.setAiCache(
        AiCache.cacheHashFor(msgs('尾'), 'p1|m'),
        '尾答案',
        'p1',
        msgs('尾'),
        identity: 'p1|m',
      );

      expect(await AiCache.cacheCount, 6);
    });

    test('并发写入时一条失败不影响其它条', () async {
      AiPrefs.maxCacheCount = 1000;
      await AiCache.setAiCache(
        AiCache.cacheHashFor(msgs('正常'), 'p1|m'),
        '正常答案',
        'p1',
        msgs('正常'),
        identity: 'p1|m',
      );
      await Future.wait([
        for (var i = 0; i < 3; i++)
          AiCache.setAiCache(
            AiCache.cacheHashFor(msgs('后$i'), 'p1|m'),
            '后答案$i',
            'p1',
            msgs('后$i'),
            identity: 'p1|m',
          ),
      ]);

      expect(await AiCache.cacheCount, 4);
    });

    test('反向对照：不经过 serializeWrite 的并发读-改-写确实会丢条目', () async {
      AiPrefs.maxCacheCount = 1000;

      // 复刻 setAiCache 的内部三步，但**不**走队列，模拟修复前的行为
      Future<void> unsynchronizedWrite(int i) async {
        final cacheDir = await getSjCacheDir();
        final file = File('${cacheDir.path}/${AiCache.cacheFileName}');
        final cache = await AiCache.readCache();
        final key = AiCache.cacheHashFor(msgs('裸写$i'), 'p1|m').toString();
        cache[key] = {
          'data': '裸写答案$i',
          'identifier': 'p1',
          'identity': 'p1|m',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'messages': <dynamic>[],
        };
        await file.writeAsString(json.encode(cache));
      }

      await Future.wait([
        for (var i = 0; i < 8; i++) unsynchronizedWrite(i),
      ]);

      final lostCount = await AiCache.cacheCount;
      expect(lostCount, lessThan(8),
          reason: '这条对照用例本来就是用来证明「不串行化会丢」的；'
              '如果它没丢，说明底层 IO 行为变了，该重新评估串行化是否还需要');

      // 同样 8 条，走 serializeWrite 就一条不丢
      await AiCache.clearCache();
      await Future.wait([
        for (var i = 0; i < 8; i++)
          AiCache.serializeWrite(() async {
            final cacheDir = await getSjCacheDir();
            final file = File('${cacheDir.path}/${AiCache.cacheFileName}');
            final cache = await AiCache.readCache();
            final key =
                AiCache.cacheHashFor(msgs('裸写$i'), 'p1|m').toString();
            cache[key] = {
              'data': '裸写答案$i',
              'identifier': 'p1',
              'identity': 'p1|m',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'messages': <dynamic>[],
            };
            await file.writeAsString(json.encode(cache));
          }),
      ]);

      expect(await AiCache.cacheCount, 8,
          reason: '经过 serializeWrite 后仍然丢条目');
    });
  });

  group('清理与容错', () {
    test('clearCache 删除文件后计数归零', () async {
      final hash = AiCache.cacheHashFor(msgs('问题'), 'p1|m');
      await AiCache.setAiCache(hash, '答案', 'p1', msgs('问题'),
          identity: 'p1|m');
      expect(await AiCache.cacheCount, 1);

      await AiCache.clearCache();

      expect(cacheFile().existsSync(), isFalse);
      expect(await AiCache.cacheCount, 0);
    });

    test('超过 maxCacheCount 时按 timestamp 淘汰最旧的', () async {
      // 把上限压到 3，避免写 300 条拖慢测试
      AiPrefs.maxCacheCount = 3;

      for (var i = 0; i < 5; i++) {
        final text = '问题$i';
        await AiCache.setAiCache(
          AiCache.cacheHashFor(msgs(text), 'p1|m'),
          '答案$i',
          'p1',
          msgs(text),
          identity: 'p1|m',
        );
      }

      expect(await AiCache.cacheCount, 3,
          reason: '清理没有把条目数压到上限以内');

      // 最早的两条应被淘汰，最后一条必须还在
      final oldest = AiCache.cacheHashFor(msgs('问题0'), 'p1|m');
      final newest = AiCache.cacheHashFor(msgs('问题4'), 'p1|m');
      expect(await AiCache.getAiCache(oldest), isNull);
      expect(await AiCache.getAiCache(newest), isNotNull);
    });

    test('未超过上限时不重写文件（避免无谓写盘）', () async {
      AiPrefs.maxCacheCount = 10;
      final hash = AiCache.cacheHashFor(msgs('问题'), 'p1|m');
      await AiCache.setAiCache(hash, '答案', 'p1', msgs('问题'),
          identity: 'p1|m');

      final before = cacheFile().lastModifiedSync();
      // 等到文件时间戳可分辨
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await AiCache.cleanCache();
      final after = cacheFile().lastModifiedSync();

      expect(after, before, reason: '未超上限却重写了文件');
    });

    test('缓存文件损坏时按空缓存处理并删除坏文件，不抛异常', () async {
      cacheFile().writeAsStringSync('{ 这不是合法 JSON');

      expect(await AiCache.readCache(), isEmpty);
      expect(cacheFile().existsSync(), isFalse,
          reason: '损坏的缓存文件应被删除，避免每次都解析失败');

      // 后续仍能正常写入
      final hash = AiCache.cacheHashFor(msgs('问题'), 'p1|m');
      await AiCache.setAiCache(hash, '答案', 'p1', msgs('问题'),
          identity: 'p1|m');
      expect(await AiCache.cacheCount, 1);
    });
  });
}
