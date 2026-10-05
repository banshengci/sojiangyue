import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

/// 插件声明契约测试（3.2）：确保 plugin.json 解析与契约边界稳定。
void main() {
  group('PluginManifest 解析', () {
    test('解析 translator 清单：权限 / 钩子 / 行为正确', () {
      final json = {
        'schemaVersion': '1.0',
        'id': 'com.songjiang.translator',
        'name': '随选即译',
        'version': '1.0.0',
        'permissions': ['read.book.text', 'ai.query'],
        'hooks': [
          {'event': 'onSelectText', 'tool': 'translate'}
        ],
        'tools': [
          {
            'id': 'translate',
            'displayName': '文本翻译',
            'behavior': 'ai_prompt',
            'prompt': '翻译：{{text}}',
          }
        ],
      };
      final m = PluginManifest.parse(jsonEncode(json));
      expect(m.id, 'com.songjiang.translator');
      expect(m.permissions, contains(PluginPermission.readBookText));
      expect(m.permissions, contains(PluginPermission.aiQuery));
      expect(m.hooks.first.event, PluginEventType.onSelectText);
      expect(m.tools.first.behavior, PluginToolBehavior.aiPrompt);
    });

    test('解析 poem_explain 清单：llmChain 多步链 steps', () {
      final json = {
        'schemaVersion': '1.0',
        'id': 'com.songjiang.poem_explain',
        'name': '诗词赏析',
        'version': '1.0.0',
        'permissions': ['read.book.text', 'ai.query'],
        'hooks': [
          {'event': 'onSelectText', 'tool': 'explain'}
        ],
        'tools': [
          {
            'id': 'explain',
            'displayName': '诗句多步赏析',
            'behavior': 'llm_chain',
            'steps': [
              {'as': 'paraphrase', 'prompt': '串讲：{{text}}'},
              {'as': 'analysis', 'prompt': '赏析：{{paraphrase}}'},
            ],
          }
        ],
      };
      final m = PluginManifest.parse(jsonEncode(json));
      expect(m.tools.first.behavior, PluginToolBehavior.llmChain);
      expect(m.tools.first.steps.length, 2);
      expect(m.tools.first.steps.first.as, 'paraphrase');
    });

    test('非法权限字符串被安全忽略（不抛异常）', () {
      final json = {
        'schemaVersion': '1.0',
        'id': 'x.bad',
        'name': 'x',
        'version': '1.0.0',
        'permissions': ['read.book.text', 'network.foo', 123],
        'tools': [],
      };
      final m = PluginManifest.parse(jsonEncode(json));
      expect(m.permissions, [PluginPermission.readBookText]);
    });

    test('缺失 version 抛异常（契约必需字段）', () {
      final json = {
        'schemaVersion': '1.0',
        'id': 'x.noversion',
        'name': 'x',
        'permissions': [],
        'tools': [],
      };
      expect(() => PluginManifest.parse(jsonEncode(json)), throwsA(isA<TypeError>()));
    });
  });
}
