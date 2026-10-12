import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:songjiang_reader/service/ai/ai_cache.dart';

/// AI 缓存的回归测试。
///
/// 背景：`AiCache.setAiCache/getAiCache` 曾经是**死代码**——UI 上
/// 「AI 缓存 / 缓存大小 / 清空缓存」都在（`settings_page/ai.dart`），
/// 但没有任何地方读写缓存，于是缓存数恒为 0、清空按钮空转。
/// 另有一个 `AiCacheEntry.decoratedText()` 同样零调用者。
///
/// 本文件锁住两类问题：
///   1. **接线不能断**：直接检查 `lib/service/ai/index.dart` 里确实调用了
///      缓存的读与写。这类「功能在但没接上」的缺陷靠行为测试抓不到
///      （没有调用方就没有可测的行为），只能从源码层面守。
///   2. 缓存键与身份校验的正确性：键必须稳定（否则永远命不中）、
///      必须能区分不同提问、换模型后不能误命中。
void main() {
  group('缓存键（cacheHashFor）', () {
    // langchain_core 里两个类的 content 类型不同：
    // HumanChatMessage.content 是 ChatMessageContent，AIChatMessage.content 是 String
    ChatMessage human(String text) =>
        HumanChatMessage(content: ChatMessageContent.text(text));
    ChatMessage ai(String text) => AIChatMessage(content: text);

    test('同样的提问与身份 → 同样的键（否则缓存永远命不中）', () {
      final a = AiCache.cacheHashFor([human('你好')], 'p1|gpt-4');
      final b = AiCache.cacheHashFor([human('你好')], 'p1|gpt-4');
      expect(a, b);
    });

    test('不同提问 → 不同键', () {
      final a = AiCache.cacheHashFor([human('你好')], 'p1|gpt-4');
      final b = AiCache.cacheHashFor([human('再见')], 'p1|gpt-4');
      expect(a, isNot(b));
    });

    test('同一提问但换了模型/供应商 → 不同键', () {
      final a = AiCache.cacheHashFor([human('你好')], 'p1|gpt-4');
      final b = AiCache.cacheHashFor([human('你好')], 'p2|claude-3');
      final c = AiCache.cacheHashFor([human('你好')], 'p1|gpt-4o');
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('返回的是稳定的非负整数（可安全作为 JSON 键）', () {
      final h = AiCache.cacheHashFor([human('稳定性')], 'p|m');
      expect(h, isA<int>());
      expect(h, greaterThanOrEqualTo(0));
    });

    test('多轮对话与单轮可区分', () {
      final single = AiCache.cacheHashFor([human('你好')], 'p|m');
      final multi = AiCache.cacheHashFor([human('你好'), ai('在的')], 'p|m');
      expect(single, isNot(multi));
    });
  });

  group('条目序列化（identity 往返）', () {
    test('toJson/fromJson 保留 identity，否则换模型后会误命中', () {
      final entry = AiCacheEntry(
        data: '答案',
        identifier: 'p1',
        identity: 'p1|gpt-4',
        timestamp: 1234567890,
        messages: [
          HumanChatMessage(content: ChatMessageContent.text('问题')),
        ],
      );

      final restored = AiCacheEntry.fromJson(
        json.decode(json.encode(entry.toJson())) as Map<String, dynamic>,
      );

      expect(restored.data, '答案');
      expect(restored.identifier, 'p1');
      expect(restored.identity, 'p1|gpt-4');
      expect(restored.timestamp, 1234567890);
      expect(restored.messages.length, 1);
    });

    test('历史条目缺 identity 字段时不抛异常，且按未命中处理', () {
      // 模拟旧版本写下的缓存（没有 identity 字段）
      final legacy = {
        'data': '旧答案',
        'identifier': 'p1',
        'timestamp': 1,
        'messages': <dynamic>[],
      };

      final restored = AiCacheEntry.fromJson(legacy);
      expect(restored.identity, '');
      // 有身份的调用方拿不到这条：'' != 'p1|gpt-4'
      expect(restored.identity == 'p1|gpt-4', isFalse);
    });
  });

  group('接线不能断（源码级守护）', () {
    test('aiGenerateStream 主链路确实读写了缓存', () {
      final source = File('lib/service/ai/index.dart').readAsStringSync();

      expect(source, contains('AiCache.getAiCache'),
          reason: '缓存读路径没接上：命中不了任何缓存');
      expect(source, contains('AiCache.setAiCache'),
          reason: '缓存写路径没接上：缓存永远是空的（这正是修复前的状态）');
      expect(source, contains('AiCache.cacheHashFor'),
          reason: '没有键就算不了缓存');
      expect(source, contains('_cachedExecuteStream'),
          reason: '缓存包装函数没被使用');
      // 三个 provider 分支都要走缓存
      expect(
        RegExp(r'_cachedExecuteStream\(').allMatches(source).length,
        greaterThanOrEqualTo(3),
        reason: '新的 provider 分支漏了缓存（新增分支时要一起接上）',
      );
    });

    test('设置页展示的缓存计数与清空仍指向 AiCache', () {
      final provider = File('lib/providers/ai_cache_count.dart').readAsStringSync();
      expect(provider, contains('AiCache.cacheCount'));
      expect(provider, contains('AiCache.clearCache'));
    });
  });
}
