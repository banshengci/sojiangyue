import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:songjiang_reader/plugin/declarative_plugin_tool.dart';
import 'package:songjiang_reader/plugin/plugin_settings.dart';
import 'package:songjiang_reader/plugin/plugin_storage.dart';
import 'package:songjiang_reader/plugin/songjiang_plugin_contract.dart';

/// 插件设置、私有存储、模板变量优先级。
///
/// 这三块都是"插件能影响什么"的边界：设置决定行为、存储决定它记得什么、
/// 模板决定这些值怎么落进 prompt。边界写松了，插件就能覆盖用户的输入。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('清单解析：settings 与 enhancers', () {
    test('解析出两类设置与选项', () {
      final m = PluginManifest.fromJson({
        'id': 'a.b',
        'name': 'n',
        'version': '1',
        'settings': [
          {'key': 'tone', 'title': '语气', 'type': 'enum', 'default': '克制', 'options': ['克制', '温柔']},
          {'key': 'n', 'title': '次数', 'type': 'integer', 'default': 3},
        ],
        'enhancers': [
          {'id': 'short', 'title': '短句', 'rule': '每次最多说两句'},
        ],
        'tools': [],
      });
      expect(m.settings.length, 2);
      expect(m.settings.first.type, PluginSettingType.enum_);
      expect(m.settings.first.options, ['克制', '温柔']);
      expect(m.settings.last.defaultValue, '3');
      expect(m.enhancers.single.rule, '每次最多说两句');
    });

    test('没有 rule 的增强器被丢弃（空规则等于没开）', () {
      final m = PluginManifest.fromJson({
        'id': 'a.b',
        'name': 'n',
        'version': '1',
        'enhancers': [
          {'id': 'x', 'title': '空', 'rule': '   '},
          {'id': 'y', 'title': '有', 'rule': '说短句'},
        ],
        'tools': [],
      });
      expect(m.enhancers.length, 1);
      expect(m.enhancers.single.id, 'y');
    });
  });

  group('validateSettingValue', () {
    const boolDef = PluginSettingDef(key: 'b', title: 'b', type: PluginSettingType.boolean);
    const intDef = PluginSettingDef(key: 'i', title: 'i', type: PluginSettingType.integer);
    const enumDef = PluginSettingDef(
      key: 'e',
      title: 'e',
      type: PluginSettingType.enum_,
      options: ['甲', '乙'],
    );

    test('布尔只接受 true/false', () {
      expect(validateSettingValue(boolDef, 'true'), isNull);
      expect(validateSettingValue(boolDef, 'false'), isNull);
      expect(validateSettingValue(boolDef, 'yes'), isNotNull);
    });

    test('整数必须能解析', () {
      expect(validateSettingValue(intDef, '3'), isNull);
      expect(validateSettingValue(intDef, '3.5'), isNotNull);
      expect(validateSettingValue(intDef, '三'), isNotNull);
    });

    test('枚举必须在选项里', () {
      expect(validateSettingValue(enumDef, '甲'), isNull);
      expect(validateSettingValue(enumDef, '丙'), isNotNull);
    });
  });

  group('settings 读写', () {
    const defs = [
      PluginSettingDef(key: 'tone', title: '语气', type: PluginSettingType.enum_, defaultValue: '克制', options: ['克制', '温柔']),
    ];

    test('未设置时返回默认值', () async {
      final v = await PluginSettingsStore.resolve('p.one', defs);
      expect(v['tone'], '克制');
    });

    test('写入后能读回，且不影响别的插件', () async {
      await PluginSettingsStore.set('p.one', defs, 'tone', '温柔');
      expect((await PluginSettingsStore.resolve('p.one', defs))['tone'], '温柔');
      expect((await PluginSettingsStore.resolve('p.two', defs))['tone'], '克制');
    });

    test('拒绝写未声明的键', () async {
      final ok = await PluginSettingsStore.set('p.one', defs, 'not_declared', 'x');
      expect(ok, isFalse);
    });

    test('模板变量键名为 config.<key>', () async {
      await PluginSettingsStore.set('p.one', defs, 'tone', '温柔');
      final vars = PluginSettingsStore.toTemplateVars(
        await PluginSettingsStore.resolve('p.one', defs),
      );
      expect(vars['config.tone'], '温柔');
    });
  });

  group('私有存储', () {
    test('写入后能读回', () async {
      await PluginStorage.write('p.one', 'notes', '上次选了黛玉');
      expect(await PluginStorage.read('p.one', 'notes'), '上次选了黛玉');
    });

    test('按插件隔离：别的插件读不到', () async {
      await PluginStorage.write('p.one', 'notes', 'x');
      expect(await PluginStorage.read('p.two', 'notes'), isNull);
      expect(await PluginStorage.all('p.two'), isEmpty);
    });

    test('键名非法被拒', () async {
      expect(
        () => PluginStorage.write('p.one', 'bad key!', 'x'),
        throwsA(isA<PluginStorageException>()),
      );
    });

    test('单值超限被拒', () async {
      final big = 'x' * (PluginStorage.maxValueLength + 1);
      expect(
        () => PluginStorage.write('p.one', 'big', big),
        throwsA(isA<PluginStorageException>()),
      );
    });

    test('键数量超限被拒', () async {
      for (var i = 0; i < PluginStorage.maxKeys; i++) {
        await PluginStorage.write('p.one', 'k$i', 'v');
      }
      expect(
        () => PluginStorage.write('p.one', 'overflow', 'v'),
        throwsA(isA<PluginStorageException>()),
      );
    });

    test('模板变量键名为 storage.<key>', () async {
      await PluginStorage.write('p.one', 'notes', 'hi');
      final vars = PluginStorage.toTemplateVars(await PluginStorage.all('p.one'));
      expect(vars['storage.notes'], 'hi');
    });

    test('clear 只清自己的数据', () async {
      await PluginStorage.write('p.one', 'a', '1');
      await PluginStorage.write('p.two', 'a', '2');
      await PluginStorage.clear('p.one');
      expect(await PluginStorage.all('p.one'), isEmpty);
      expect(await PluginStorage.read('p.two', 'a'), '2');
    });
  });

  group('模板变量优先级', () {
    test('入参覆盖插件设置（用户这一轮的要求优先）', () {
      final merged = mergeTemplateVars(
        {'config.tone': '克制', 'storage.notes': '旧笔记'},
        {'tone': '直白'},
      );
      expect(merged['config.tone'], '克制');
      expect(merged['storage.notes'], '旧笔记');
      expect(merged['tone'], '直白');
    });

    test('同名键：入参赢', () {
      final merged = mergeTemplateVars({'k': 'plugin'}, {'k': 'input'});
      expect(merged['k'], 'input');
    });
  });

  group('settingAsBool', () {
    test('true/1/yes 都算真，其余算假', () {
      expect(settingAsBool('true'), isTrue);
      expect(settingAsBool('1'), isTrue);
      expect(settingAsBool('YES'), isTrue);
      expect(settingAsBool('false'), isFalse);
      expect(settingAsBool(null, fallback: true), isTrue);
    });
  });
}
