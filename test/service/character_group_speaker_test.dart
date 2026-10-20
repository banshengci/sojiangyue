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

  group('splitSpokenBlock（一回合多段）', () {
    const names = ['姬动', '烈焰', '弗瑞', '陈思璇'];

    test('一个回合里几个人轮着说话，拆成几张卡片', () {
      // 截图里的真实形态：落库时首行「弗瑞：」已被 strip，剩下的人还在正文里
      const raw = '（大手一挥，直接拍板）就这么定了。师弟，你明天一早就动身。\n'
          '\n'
          '姬动：我不去。\n'
          '\n'
          '陈思璇：姬动……\n'
          '\n'
          '弗瑞：由不得你。';
      final segs = splitSpokenBlock(raw, firstSpeaker: '弗瑞', onStage: names);
      expect(segs.map((s) => s.speaker).toList(), ['弗瑞', '姬动', '陈思璇', '弗瑞']);
      expect(segs[0].text, contains('就这么定了'));
      expect(segs[1].text, '我不去。');
    });

    test('整段只有别人的台词时，不再挂在首行那个人头上', () {
      // 截图里那张标着「姬动」却只有陈思璇一句的卡片
      const raw = '陈思璇：（望着姬动离去的方向）姬动……你还是答应了。';
      final segs = splitSpokenBlock(raw, firstSpeaker: '姬动', onStage: names);
      expect(segs.length, 1);
      expect(segs.first.speaker, '陈思璇');
    });

    test('独立成段的纯括注是旁白，不并进上一个人的台词', () {
      const raw = '（驿站外，姬动正在备马，忽然感应到一股冰寒气息。他握上了刀柄）\n'
          '\n'
          '姬动：出来。';
      final segs = splitSpokenBlock(raw, firstSpeaker: '弗瑞', onStage: names);
      expect(segs.first.isNarration, isTrue);
      expect(segs.first.text, startsWith('（驿站外'));
      expect(segs[1].speaker, '姬动');
      expect(segs[1].text, '出来。');
    });

    test('「（动作）台词」不算旁白——括号只开了个头，后面还有话', () {
      const raw = '（收回目光，攥紧拳头，指甲几乎嵌入掌心）姬动，你带她去祭烈焰陛下。';
      final segs = splitSpokenBlock(raw, firstSpeaker: '阿金', onStage: const ['阿金']);
      expect(segs.length, 1);
      expect(segs.first.speaker, '阿金');
      expect(segs.first.isNarration, isFalse);
    });

    test('台词中间夹一段括注，括注自己成一行', () {
      const raw = '姬动：你走吧。\n'
          '（门被轻轻带上。）\n'
          '姬动：别回头。';
      final segs = splitSpokenBlock(raw, onStage: names);
      expect(segs.map((s) => s.speaker).toList(), ['姬动', '', '姬动']);
      expect(segs[1].isNarration, isTrue);
    });

    test('不在场的人名不拆（避免把旁人的话安到在场者头上）', () {
      const raw = '王熙凤：都散了吧。';
      final segs = splitSpokenBlock(raw, onStage: names);
      expect(segs.length, 1);
      expect(segs.first.speaker, '');
      expect(segs.first.text, '王熙凤：都散了吧。');
    });

    test('空内容返回空列表（流式开始时不该凭空多一张卡片）', () {
      expect(splitSpokenBlock(''), isEmpty);
      expect(splitSpokenBlock('   \n  '), isEmpty);
    });

    test('单段内容不会被拆坏', () {
      const raw = '姬动：走。';
      final segs = splitSpokenBlock(raw, onStage: names);
      expect(segs.length, 1);
      expect(segs.first.speaker, '姬动');
      expect(segs.first.text, '走。');
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
