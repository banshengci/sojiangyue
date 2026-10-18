import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/models/gameplay_mode.dart';
import 'package:songjiang_reader/models/gameplay_session.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_catalog.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_modes.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_models.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_pack_service.dart';
import 'package:songjiang_reader/service/gameplay/gameplay_runtime.dart';
import 'package:songjiang_reader/service/gameplay/official_gameplay_packs.dart';

/// 官方玩法包：能装、能存、能开一局。
///
/// 这组测试盯的是「玩法可以安装」这条链路本身——JSON 往返、
/// 压缩包往返、目录合并、运行时可解析。少任何一环，
/// 用户装完看到的都是空白或者错误。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('官方玩法包', () {
    test('六个包，id 唯一，每个只带一个玩法', () {
      expect(kOfficialGameplayPacks.length, 6);
      final ids = kOfficialGameplayPacks.map((p) => p.id).toSet();
      expect(ids.length, kOfficialGameplayPacks.length, reason: '包 id 不能重复');
      for (final pack in kOfficialGameplayPacks) {
        expect(pack.packType, GameplayPackType.gameplayMode);
        expect(pack.gameplayModes.length, 1, reason: '一包一玩法便于单独装卸');
      }
    });

    test('玩法 id 不与内置冲突', () {
      final builtin = kBuiltinGameplayModes.map((m) => m.id).toSet();
      for (final pack in kOfficialGameplayPacks) {
        for (final mode in pack.gameplayModes) {
          expect(builtin.contains(mode.id), isFalse,
              reason: '${mode.id} 与内置玩法重名，装上会被忽略');
        }
      }
    });

    test('每个玩法都带状态、分幕与结局条件', () {
      for (final pack in kOfficialGameplayPacks) {
        final mode = pack.gameplayModes.single;
        expect(mode.stats, isNotEmpty, reason: '${mode.name} 没有状态量');
        expect(mode.phases, isNotEmpty, reason: '${mode.name} 没有分幕');
        expect(mode.endingHint, isNotNull, reason: '${mode.name} 没有结局条件');
        expect(mode.sceneHints, isNotEmpty, reason: '${mode.name} 没有开局场景');
        expect(mode.directive.length, greaterThan(20),
            reason: '${mode.name} 的规则外壳太薄');
        for (final s in mode.stats) {
          expect(s.hint.trim(), isNotEmpty,
              reason: '${mode.name} 的状态 ${s.key} 缺少给模型的说明');
        }
      }
    });
  });

  group('JSON 往返', () {
    test('玩法转成 JSON 再转回来，关键字段不丢', () {
      for (final pack in kOfficialGameplayPacks) {
        final src = pack.gameplayModes.single;
        final back = GameplayMode.fromJson(src.toJson());
        expect(back.id, src.id);
        expect(back.name, src.name);
        expect(back.directive, src.directive);
        expect(back.phases, src.phases);
        expect(back.stats.length, src.stats.length);
        expect(back.stats.first.hint, src.stats.first.hint);
        expect(back.secretLabel, src.secretLabel);
        expect(back.endingHint, src.endingHint);
        expect(back.sceneHints, src.sceneHints);
      }
    });

    test('状态量的按人记录标记能保留', () {
      final mode = GameplayMode.fromJson({
        'id': 'x',
        'directive': '规则',
        'stats': [
          {'key': 'affection', 'name': '好感', 'perMember': true, 'isScore': true},
        ],
      });
      expect(mode.stats.single.perMember, isTrue);
      expect(mode.stats.single.isScore, isTrue);
    });

    test('缺 directive 的玩法判非法（空壳不该能开）', () {
      expect(
        () => GameplayMode.fromJson({'id': 'x'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => GameplayMode.fromJson({'directive': '有规则没 id'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('.sjgame.zip 往返', () {
    test('打包再导入，玩法原样还在', () async {
      final service = GameplayPackService.instance;
      for (final pack in kOfficialGameplayPacks) {
        final bytes = await service.exportPack(pack);
        final back = await service.importPack(bytes);
        expect(back.id, pack.id);
        expect(back.packType, GameplayPackType.gameplayMode);
        expect(back.gameplayModes.length, 1);
        expect(back.gameplayModes.single.id, pack.gameplayModes.single.id);
        expect(back.gameplayModes.single.directive,
            pack.gameplayModes.single.directive);
      }
    });

    test('包体积在合理范围（纯文本，不该超过 20KB）', () async {
      for (final pack in kOfficialGameplayPacks) {
        final bytes = await GameplayPackService.instance.exportPack(pack);
        expect(bytes.length, lessThan(20 * 1024), reason: '${pack.name} 包异常大');
      }
    });
  });

  group('目录合并', () {
    test('没装任何包时只有内置玩法', () async {
      final catalog = await GameplayCatalog.load();
      expect(catalog.installed, isEmpty);
      expect(catalog.all.length, kBuiltinGameplayModes.length);
      expect(catalog.hasInstalled, isFalse);
    });

    test('装了包之后玩法出现在目录里', () async {
      final pack = kOfficialGameplayPacks.first;
      await GameplayPackService.instance.saveInstalled(pack);

      final catalog = await GameplayCatalog.load();
      expect(catalog.installed.length, 1);
      expect(catalog.all.length, kBuiltinGameplayModes.length + 1);
      expect(catalog.isFromPack(pack.gameplayModes.single.id), isTrue);
    });

    test('包里的 id 与内置冲突时被忽略，不覆盖内置', () async {
      final duplicated = GameplayPackManifest(
        schemaVersion: '1.0',
        id: 'com.songjiang.play.bad',
        name: '坏包',
        version: '1.0.0',
        author: 't',
        description: '试图覆盖内置玩法',
        packType: GameplayPackType.gameplayMode,
        gameplayModesJson: [
          {
            'id': 'murder-mystery', // 内置剧本杀
            'name': '假剧本杀',
            'directive': '冒充内置',
          },
        ],
      );
      await GameplayPackService.instance.saveInstalled(duplicated);

      final catalog = await GameplayCatalog.load();
      expect(catalog.installed, isEmpty);
      expect(catalog.builtin.any((m) => m.name == '剧本杀'), isTrue);
    });

    test('同 id 的包后装覆盖先装（升级场景）', () async {
      final base = kOfficialGameplayPacks.first;
      final v2 = GameplayPackManifest(
        schemaVersion: '1.0',
        id: base.id,
        name: base.name,
        version: '1.1.0',
        author: base.author,
        description: '升级版',
        packType: GameplayPackType.gameplayMode,
        gameplayModesJson: [
          {...base.gameplayModesJson.first, 'summary': '升级后的说明'},
        ],
      );
      await GameplayPackService.instance.saveInstalled(base);
      await GameplayPackService.instance.saveInstalled(v2);

      final catalog = await GameplayCatalog.load();
      final installed = catalog.installed.single;
      expect(installed.summary, '升级后的说明');
    });
  });

  group('能开一局', () {
    test('每个新玩法都能生成注入指令，且要求输出状态块', () {
      for (final pack in kOfficialGameplayPacks) {
        final mode = pack.gameplayModes.single;
        final session = GameplaySession(
          chatSessionId: 1,
          modeId: mode.id,
          stats: {for (final s in mode.stats) s.key: s.initial},
          memberStats: const {},
          phaseIndex: 0,
          turn: 0,
          log: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        final directive = GameplayRuntime.buildDirective(
          mode: mode,
          session: session,
        );
        expect(directive, contains('本场玩法：${mode.name}'));
        expect(directive, contains('可追踪状态'));
        expect(directive, contains('当前进度'));
        expect(directive, contains('输出要求'));
      }
    });
  });

  // 导出工具：设置 SJ_EXPORT_PACKS_DIR 时才执行，CI 上自动跳过。
  // 用法：$env:SJ_EXPORT_PACKS_DIR="D:\xiangmu\玩法包"; flutter test test/service/gameplay_pack_install_test.dart
  test('导出官方玩法包到指定目录（可选）', () async {
    final dir = Platform.environment['SJ_EXPORT_PACKS_DIR'];
    if (dir == null || dir.isEmpty) return;
    final out = Directory(dir)..createSync(recursive: true);
    for (final pack in kOfficialGameplayPacks) {
      final bytes = await GameplayPackService.instance.exportPack(pack);
      final safe = pack.gameplayModes.single.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      File('${out.path}/$safe.sjgame.zip').writeAsBytesSync(bytes);
    }
  });
}
