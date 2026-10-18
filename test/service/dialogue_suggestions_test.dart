import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/service/character/dialogue_suggestions.dart';

/// 「帮我写下一句」的提示词与解析。
///
/// 这类功能的失败方式很隐蔽：提示词写得含糊，模型就会给三句"泛泛的接话"，
/// 用户看不出错，只觉得"它没在听"。所以这里把"必须承接上一句"和
/// "三条要有区别"这两条硬要求钉在测试里。
void main() {
  group('提示词', () {
    test('旁观：要求写推动场景的话，并点出不要商量口吻', () {
      final p = buildSuggestionPrompt(
        characterName: '林黛玉',
        latestReply: '这花落在我手里，倒像是笑话我。',
      );
      expect(p, contains('旁观'));
      expect(p, contains('推动场景'));
      expect(p, contains('"要不要/不如/可以"'));
    });

    test('扮演：以所扮演人物的口吻说话，并带上名字', () {
      final p = buildSuggestionPrompt(
        characterName: '贾宝玉',
        latestReply: '你又恼了。',
        participationCode: 'roleplay',
        userPersona: '薛宝钗',
      );
      expect(p, contains('扮演'));
      expect(p, contains('薛宝钗'));
      expect(p, contains('会说出口的话'));
    });

    test('入场：外来者视角', () {
      final p = buildSuggestionPrompt(
        characterName: '贾宝玉',
        latestReply: '你是谁？',
        participationCode: 'join',
        userPersona: '张三',
      );
      expect(p, contains('外来者'));
      expect(p, contains('张三'));
    });

    test('带上上一轮原话，并要求承接具体内容', () {
      final p = buildSuggestionPrompt(
        characterName: '林黛玉',
        latestReply: '这花落在我手里，倒像是笑话我。',
      );
      expect(p, contains('这花落在我手里'));
      expect(p, contains('具体提到'));
    });

    test('要求三条方向有实质区别（追问/情绪/行动）', () {
      final p = buildSuggestionPrompt(
        characterName: '某人',
        latestReply: '嗯。',
        count: 3,
      );
      expect(p, contains('追问'));
      expect(p, contains('情绪'));
      expect(p, contains('行动'));
      expect(p, contains('写 3 条候选'));
    });

    test('要求输出 JSON 且含 anchor 字段', () {
      final p = buildSuggestionPrompt(characterName: '某人', latestReply: '嗯。');
      expect(p, contains('JSON 数组'));
      expect(p, contains('anchor'));
    });
  });

  group('解析', () {
    test('标准数组', () {
      final list = parseSuggestions(
        '[{"label":"追问","text":"你说的当年是什么时候？","anchor":"当年的事"}]',
      );
      expect(list.single.label, '追问');
      expect(list.single.text, '你说的当年是什么时候？');
      expect(list.single.anchor, '当年的事');
    });

    test('带代码围栏也能解析', () {
      final list = parseSuggestions(
        '```json\n[{"label":"a","text":"第一句"}]\n```',
      );
      expect(list.single.text, '第一句');
    });

    test('外层包成 {"suggestions":[...]} 也能解析', () {
      final list = parseSuggestions(
        '{"suggestions":[{"label":"a","text":"包着也能读"}]}',
      );
      expect(list.single.text, '包着也能读');
    });

    test('没有 text 的条目被丢弃', () {
      final list = parseSuggestions(
        '[{"label":"空"},{"label":"b","text":"有用"}]',
      );
      expect(list.length, 1);
      expect(list.single.text, '有用');
    });

    test('超出上限按上限截断', () {
      final raw = '[${List.generate(6, (i) => '{"label":"$i","text":"第$i句"}').join(',')}]';
      expect(parseSuggestions(raw, max: 4).length, 4);
    });

    test('无法解析时返回空列表，不抛异常', () {
      expect(parseSuggestions('模型今天不想干活'), isEmpty);
      expect(parseSuggestions(''), isEmpty);
      expect(parseSuggestions('{"foo":1}'), isEmpty);
    });
  });
}
