import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_market_client.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_models.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_service.dart';

/// 玩法包契约测试（3.3 + 3.2）：manifest 解析边界 + 与 2.3 插件契约打通。
void main() {
  group('GameplayPackManifest', () {
    test('reading_script 包：scriptTools 编译为 PluginManifest 工具', () {
      final json = {
        'schemaVersion': '1.0',
        'packType': 'reading_script',
        'id': 'com.songjiang.hlm_quiz',
        'name': '红楼诗词闯关',
        'version': '1.0.0',
        'author': 'demo',
        'description': '红楼梦人物关系 Quiz',
        'bookScope': '红楼梦',
        'scriptTools': [
          {
            'id': 'quiz',
            'displayName': '人物关系 Quiz',
            'behavior': 'llm_chain',
            'steps': [
              {'as': 'q', 'prompt': '出一道关于{{text}}的关系题'},
              {'as': 'a', 'prompt': '给出答案：{{q}}'},
            ],
          }
        ],
      };
      final m = GameplayPackManifest.fromJson(json);
      expect(m.packType, GameplayPackType.readingScript);
      expect(m.scriptTools.length, 1);
      expect(m.scriptTools.first.behavior, PluginToolBehavior.llmChain);
      // 与 2.3 插件系统打通：编译为 PluginManifest 可注入 PluginRegistry。
      final pm = m.toPluginManifest();
      expect(pm.id, 'com.songjiang.hlm_quiz');
      expect(pm.tools.first.steps.length, 2);
    });

    test('scene_card 包：名场面卡往返一致', () {
      final json = {
        'packType': 'scene_card',
        'id': 'com.songjiang.sanguo_scene',
        'name': '三国名场面',
        'version': '1.0.0',
        'sceneCards': [
          {
            'id': 's1',
            'bookTitle': '三国演义',
            'quote': '既生瑜，何生亮',
            'chapter': '第五十七回',
            'context': '周瑜临终之叹',
            'tags': ['名场面', '周瑜'],
            'theme': 'cinnabar',
          }
        ],
      };
      final m = GameplayPackManifest.fromJson(json);
      expect(m.sceneCards.length, 1);
      expect(m.sceneCards.first.quote, '既生瑜，何生亮');
      expect(m.sceneCards.first.tags, ['名场面', '周瑜']);
      final out = m.toJson();
      final round = GameplayPackManifest.fromJson(out);
      expect(round.sceneCards.first.chapter, '第五十七回');
    });

    test('reading_challenge 包：metric/target/period 解析', () {
      final json = {
        'packType': 'reading_challenge',
        'id': 'com.songjiang.daily',
        'name': '每日阅读',
        'version': '1.0.0',
        'challenges': [
          {
            'id': 'c1',
            'title': '每日 30 分钟',
            'metric': 'daily_minutes',
            'target': 30,
            'periodDays': 7,
            'rewardAchievement': 'steady_reader',
          }
        ],
      };
      final m = GameplayPackManifest.fromJson(json);
      expect(m.challenges.first.metric, 'daily_minutes');
      expect(m.challenges.first.target, 30);
      expect(m.challenges.first.rewardAchievement, 'steady_reader');
    });

    test('非法 packType 抛 FormatException', () {
      final json = {
        'packType': 'black_box',
        'id': 'x',
        'name': 'x',
        'version': '1.0.0',
      };
      expect(() => GameplayPackManifest.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('缺失 version 抛 FormatException', () {
      final json = {
        'packType': 'scene_card',
        'id': 'x',
        'name': 'x',
      };
      expect(() => GameplayPackManifest.fromJson(json),
          throwsA(isA<FormatException>()));
    });

    test('scriptTools 为空时激活返回 0 个工具', () {
      final m = GameplayPackManifest.fromJson({
        'packType': 'scene_card',
        'id': 'x.empty',
        'name': 'x',
        'version': '1.0.0',
      });
      expect(m.scriptTools.length, 0);
      final pm = m.toPluginManifest();
      expect(pm.tools.length, 0);
    });
  });

  group('SceneCard 分享文案', () {
    test('buildSceneCardShareText 包含名句与出处', () {
      final card = SceneCard.fromMap({
        'id': 's1',
        'bookTitle': '红楼梦',
        'quote': '满纸荒唐言',
        'chapter': '第一回',
        'tags': ['题诗'],
      });
      final text = GameplayPackService.buildSceneCardShareText(card);
      expect(text, contains('满纸荒唐言'));
      expect(text, contains('《红楼梦》第一回'));
    });
  });

  group('GameplayPackService 序列化往返（ZIP 进出不丢字段）', () {
    GameplayPackManifest _sample() => GameplayPackManifest.fromJson({
          'packType': 'reading_script',
          'id': 'com.songjiang.roundtrip',
          'name': '往返测试包',
          'version': '2.3.1',
          'author': 'tester',
          'description': '含脚本/名场面/挑战的综合包',
          'bookScope': '测试书',
          'sceneCards': [
            {
              'id': 's1',
              'bookTitle': '测试书',
              'quote': '名句一则',
              'chapter': '第三章',
              'tags': ['t1'],
              'theme': 'ink',
            }
          ],
          'challenges': [
            {
              'id': 'c1',
              'title': '每日 20 分钟',
              'metric': 'daily_minutes',
              'target': 20,
              'periodDays': 7,
            }
          ],
          'scriptTools': [
            {
              'id': 'quiz',
              'displayName': '出题',
              'behavior': 'llm_chain',
              'steps': [
                {'as': 'q', 'prompt': '出题：{{text}}'},
                {'as': 'a', 'prompt': '答案：{{q}}'},
              ],
            }
          ],
        });

    test('exportPack → importPack 字段一致', () async {
      final m = _sample();
      final bytes = await GameplayPackService.instance.exportPack(m);
      expect(bytes.length, greaterThan(0));
      final back = await GameplayPackService.instance.importPack(bytes);
      expect(back.id, m.id);
      expect(back.name, m.name);
      expect(back.version, m.version);
      expect(back.bookScope, '测试书');
      expect(back.packType, GameplayPackType.readingScript);
      expect(back.sceneCards.length, 1);
      expect(back.sceneCards.first.quote, '名句一则');
      expect(back.challenges.length, 1);
      expect(back.challenges.first.target, 20);
      expect(back.scriptTools.length, 1);
      expect(back.scriptTools.first.behavior, PluginToolBehavior.llmChain);
      expect(back.scriptTools.first.steps.length, 2);
    });
  });

  group('GameplayPackMarketClient SHA256', () {
    test('computeSha256 与标准空字节向量一致', () {
      final empty = GameplayPackMarketClient.computeSha256(Uint8List(0));
      expect(empty,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('computeSha256 对同一内容稳定', () {
      final a = GameplayPackMarketClient.computeSha256(
          Uint8List.fromList(utf8.encode('松江阅')));
      final b = GameplayPackMarketClient.computeSha256(
          Uint8List.fromList(utf8.encode('松江阅')));
      expect(a, b);
      expect(a.length, 64); // 小写十六进制，32 字节
    });
  });
}
