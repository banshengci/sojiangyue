import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_chat.dart';

/// 群聊的说话人识别。
///
/// 群聊会话把在场人物存成 `bookId:姓名` 的逗号串（encodeMemberRefs），
/// 而模型按 buildGroupSystemPrompt 的要求，每次只输出一个人的发言，
/// 格式是「姓名：内容」。这两件事之间必须有人拆一次，否则：
///   · 界面上每条消息的说话人都是 `1:林黛玉,1:贾宝玉` 这串内部编码
///   · 玩法读不出"这句话是谁说的"
void main() {
  group('onStageNames', () {
    test('单人会话原样返回', () {
      expect(onStageNames('林黛玉'), ['林黛玉']);
    });

    test('群聊会话剥掉 bookId 前缀', () {
      expect(
        onStageNames('1:林黛玉,2:贾宝玉'),
        ['林黛玉', '贾宝玉'],
      );
    });

    test('中英文逗号都认，空段丢弃', () {
      expect(onStageNames('1:林黛玉，2:贾宝玉,, '), ['林黛玉', '贾宝玉']);
    });

    test('空串返回空列表', () {
      expect(onStageNames(''), isEmpty);
      expect(onStageNames('  '), isEmpty);
    });
  });

  group('splitSpokenLine', () {
    const names = ['林黛玉', '贾宝玉'];

    test('中文冒号：拆出说话人并去掉前缀', () {
      final r = splitSpokenLine('林黛玉：你又来做什么。', names);
      expect(r.speaker, '林黛玉');
      expect(r.text, '你又来做什么。');
    });

    test('英文冒号同样识别', () {
      final r = splitSpokenLine('贾宝玉: 我来看看你。', names);
      expect(r.speaker, '贾宝玉');
      expect(r.text, '我来看看你。');
    });

    test('前面有空白也能认', () {
      final r = splitSpokenLine('  贾宝玉：嗯。', names);
      expect(r.speaker, '贾宝玉');
      expect(r.text, '嗯。');
    });

    test('认不出说话人时返回空 speaker —— 不能猜，猜错会张冠李戴', () {
      final r = splitSpokenLine('（窗外下雨了）', names);
      expect(r.speaker, '');
      expect(r.text, '（窗外下雨了）');
    });

    test('不在场的人名不算（避免把旁人的话安到在场者头上）', () {
      final r = splitSpokenLine('王熙凤：都散了吧。', names);
      expect(r.speaker, '');
      expect(r.text, '王熙凤：都散了吧。');
    });

    test('只有名字没有内容也不崩', () {
      final r = splitSpokenLine('林黛玉：', names);
      expect(r.speaker, '林黛玉');
      expect(r.text, '');
    });

    test('台词被引号包着也能认出说话人（正文保留引号）', () {
      // 实测里模型很爱这样写：「弗瑞：……」。以前认不出，
      // 整段就落到"第一个在场者"头上，群聊里满屏张冠李戴。
      final r = splitSpokenLine('「弗瑞：黑暗天机，三日内你的大军撤出去。」', const [
        '姬动',
        '弗瑞',
      ]);
      expect(r.speaker, '弗瑞');
      expect(r.text, '「黑暗天机，三日内你的大军撤出去。」');
    });

    test('几种常见引号都认', () {
      for (final open in ['「', '『', '“', '"']) {
        final close = switch (open) {
          '「' => '」',
          '『' => '』',
          '“' => '”',
          _ => '"',
        };
        final r = splitSpokenLine('$open姬动：你说什么？$close', const ['姬动']);
        expect(r.speaker, '姬动', reason: '开引号 $open 没认出来');
        expect(r.text, '$open你说什么？$close');
      }
    });

    test('引号里不是在场者的名字，仍然不猜', () {
      final r = splitSpokenLine('「王熙凤：都散了吧。」', names);
      expect(r.speaker, '');
      expect(r.text, '「王熙凤：都散了吧。」');
    });
  });

  group('旁白要显示的名字', () {
    test('群聊不把内部编码印出来', () {
      const raw = '1:姬动,1:烈焰,1:黑暗天机';
      // 读心这类块：一个具体的"谁"
      expect(displayCharacterName(raw), '姬动');
      // 提示词/列表这类地方：整份名单，用顿号
      expect(displayCastNames(raw), '姬动、烈焰、黑暗天机');
    });

    test('有主人物时优先用主人物名', () {
      expect(
        displayCharacterName('1:姬动,1:烈焰', primary: '烈焰'),
        '烈焰',
      );
    });

    test('单人会话原样返回', () {
      expect(displayCharacterName('林黛玉'), '林黛玉');
      expect(displayCastNames('林黛玉'), '林黛玉');
    });

    test('空串不炸', () {
      expect(displayCharacterName(''), '');
      expect(displayCastNames(''), '');
    });
  });
}
