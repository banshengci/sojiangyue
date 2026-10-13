import 'dart:convert';
import 'dart:io';

import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/utils/async_mutex.dart';
import 'package:songjiang_reader/utils/get_path/get_cache_dir.dart';
import 'package:langchain_core/chat_models.dart';

class AiCacheEntry {
  AiCacheEntry({
    required this.data,
    required this.identifier,
    required this.timestamp,
    required this.messages,
    this.identity = '',
  });

  final String data;
  final String identifier;
  final int timestamp;
  final List<ChatMessage> messages;

  /// 产出这条缓存的「身份」：provider id + 模型名。
  ///
  /// 缓存键由消息算出，同一个问题在不同模型下答案不同；
  /// 若用户切换了模型/供应商，只比对消息就会把旧模型的答案当成命中。
  /// 因此把身份一并存下，读取时不一致就直接视为未命中。
  /// 兼容历史数据：缺失时视为空串（老缓存不会被当作命中）。
  final String identity;

  String decoratedText() {
    final context = navigatorKey.currentContext!;
    return '$data\n\n> ${L10n.of(context).aiCachedBy(identifier)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'identifier': identifier,
      'timestamp': timestamp,
      'identity': identity,
      'messages': messages.map((m) => m.toMap()).toList(growable: false),
    };
  }

  factory AiCacheEntry.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map<String, dynamic>) {
          messages.add(ChatMessage.fromMap(item));
        } else if (item is Map) {
          messages.add(ChatMessage.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ));
        }
      }
    }

    return AiCacheEntry(
      data: json['data']?.toString() ?? '',
      identifier: json['identifier']?.toString() ?? '',
      identity: json['identity']?.toString() ?? '',
      timestamp: json['timestamp'] is int
          ? json['timestamp'] as int
          : DateTime.now().millisecondsSinceEpoch,
      messages: messages,
    );
  }
}

class AiCache {
  static const String cacheFileName = 'ai_cache.json';

  static Future<Map<String, dynamic>> readCache() async {
    final cacheDir = await getSjCacheDir();
    final file = File('${cacheDir.path}/$cacheFileName');

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      } catch (e) {
        file.delete();
        return {};
      }
    }
    return {};
  }

  /// 写入串行化用的互斥器。
  ///
  /// [setAiCache] 是「读整个文件 → 改一条 → 写回整个文件」，没有锁的话
  /// 两个请求同时完成时会互相覆盖。实测：同时写 5 条只有 1 条落盘，
  /// 写 20 条也只有 1 条——缓存会退化成「只留最后一条」，命中率几乎为 0。
  ///
  /// 只串行化**写**；读不走队列（读本身不改文件，读不到只是未命中，
  /// 顶多退回一次网络请求，不值得为它付出排队延迟）。
  static final AsyncMutex _writeMutex = AsyncMutex();

  /// 把 [task] 排到写队列尾部，返回它自己的结果。
  ///
  /// 保留这个薄封装是为了可测：测试会显式对比「经过串行化」与「不经过串行化」
  /// 两种情况的落盘条数，从而证明互斥器确实在防覆盖，
  /// 而不是只能相信 [setAiCache] 恰好写对了。
  static Future<T> serializeWrite<T>(Future<T> Function() task) =>
      _writeMutex.run(task);

  /// 读-改-写整体排队，避免并发写入互相覆盖。
  static Future<void> setAiCache(
    int hash,
    String data,
    String identifier,
    List<ChatMessage> conversation, {
    String identity = '',
  }) async {
    await serializeWrite(() async {
      final cacheDir = await getSjCacheDir();
      final file = File('${cacheDir.path}/$cacheFileName');
      final cache = await readCache();

      final entry = AiCacheEntry(
        data: data,
        identifier: identifier,
        identity: identity,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        messages: conversation,
      );

      cache[hash.toString()] = entry.toJson();

      await file.writeAsString(json.encode(cache));
      // 把刚读到的 cache 直接传进去，避免 cleanCache 再读一遍整个文件
      await cleanCache(cache);
    });
  }

  /// 读缓存。
  ///
  /// [identity] 非空时会与条目里存的身份比对，不一致按未命中返回 null
  /// （用户切换模型/供应商后，旧答案不能当作命中）。
  static Future<AiCacheEntry?> getAiCache(int hash, {String identity = ''}) async {
    final cache = await readCache();
    final entry = cache[hash.toString()];
    AiCacheEntry? parsed;
    if (entry is Map<String, dynamic>) {
      parsed = AiCacheEntry.fromJson(entry);
    } else if (entry is Map) {
      parsed = AiCacheEntry.fromJson(
        entry.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (parsed == null) return null;
    if (identity.isNotEmpty && parsed.identity != identity) {
      return null;
    }
    return parsed;
  }

  /// 由「提问内容 + 产出方身份」算出一个稳定的缓存键。
  ///
  /// 用 messages 的序列化结果做键（同一段对话 → 同一个键），
  /// 再混入 identity；不用 `Object.hashCode`，因为它跨进程/跨次运行不稳定，
  /// 会把缓存写成永远命中不了。
  static int cacheHashFor(List<ChatMessage> messages, String identity) {
    final payload = json.encode({
      'identity': identity,
      'messages': messages.map((m) => m.toMap()).toList(growable: false),
    });
    // 只用于本地缓存文件名/键，非安全用途，取一段稳定的字符串哈希即可
    var hash = 0x811C9DC5; // FNV-1a 32 位偏移基数
    for (final unit in payload.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// 按 [AiPrefs.maxCacheCount] 裁剪缓存（按 timestamp 淘汰最旧的）。
  ///
  /// [loaded] 允许调用方传入已读出的缓存内容，省掉一次整文件读取
  /// （写入路径刚读过，没必要再读一遍）。
  static Future<void> cleanCache([Map<String, dynamic>? loaded]) async {
    final maxCount = AiPrefs.maxCacheCount;
    final cache = loaded ?? await readCache();
    // 数量没超标就不用动磁盘——原实现无论是否裁剪都会重写整个文件
    if (cache.length <= maxCount) return;

    final keys = cache.keys.toList();
    keys.sort((a, b) {
      final aMap = cache[a];
      final bMap = cache[b];
      final aTimestamp =
          aMap is Map && aMap['timestamp'] is int ? aMap['timestamp'] as int : 0;
      final bTimestamp =
          bMap is Map && bMap['timestamp'] is int ? bMap['timestamp'] as int : 0;
      return aTimestamp - bTimestamp;
    });
    final keysToRemove = keys.sublist(0, cache.length - maxCount).toSet();
    // 用 Set 做成员判断：原来直接把 List 传给 contains，
    // 是 O(被删数量 × 总数量) 的线性查找。
    cache.removeWhere((key, _) => keysToRemove.contains(key));

    final cacheDir = await getSjCacheDir();
    final file = File('${cacheDir.path}/$cacheFileName');
    await file.writeAsString(json.encode(cache), mode: FileMode.writeOnly);
  }

  static Future<int> get cacheCount async {
    final cache = await readCache();
    return cache.length;
  }

  static Future<void> clearCache() async {
    final cacheDir = await getSjCacheDir();
    final file = File('${cacheDir.path}/$cacheFileName');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
