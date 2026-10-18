import 'package:flutter_test/flutter_test.dart';

import 'package:songjiang_reader/service/character/chat_autoplay.dart';
import 'package:songjiang_reader/service/character/character_chat_service.dart'
    show continueNudge;
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/service/character/character_persona.dart';

/// 旁观模式的自动推进。
///
/// 这个功能的风险只有两个：**推不动**（提示词要求主动推进，但没人触发）
/// 和**停不下**（一直烧 token）。前者靠 nudge + 指令约束，
/// 后者靠 [shouldContinueAutoPlay] 的边界，这里把它们钉住。
void main() {
  group('shouldContinueAutoPlay', () {
    test('开关关掉就不再继续', () {
      expect(
        shouldContinueAutoPlay(
            autoPlay: false, turns: 0, limit: 10, hasError: false),
        isFalse,
      );
    });

    test('到上限即停', () {
      expect(
        shouldContinueAutoPlay(
            autoPlay: true, turns: 9, limit: 10, hasError: false),
        isTrue,
      );
      expect(
        shouldContinueAutoPlay(
            autoPlay: true, turns: 10, limit: 10, hasError: false),
        isFalse,
      );
      expect(
        shouldContinueAutoPlay(
            autoPlay: true, turns: 11, limit: 10, hasError: false),
        isFalse,
      );
    });

    test('出错后必须停（否则带着坏状态一直重试）', () {
      expect(
        shouldContinueAutoPlay(
            autoPlay: true, turns: 0, limit: 10, hasError: true),
        isFalse,
      );
    });

    test('正常推进中继续', () {
      expect(
        shouldContinueAutoPlay(
            autoPlay: true, turns: 3, limit: 10, hasError: false),
        isTrue,
      );
    });
  });

  group('推进信号', () {
    test('明确要求不要停下来等读者，也不要复述', () {
      expect(continueNudge, contains('不要停下来等读者'));
      expect(continueNudge, contains('不要复述'));
    });

    test('以「继续演出」开头，便于模型识别这是舞台指令而不是用户台词', () {
      expect(continueNudge.startsWith('【继续演出】'), isTrue);
    });
  });

  group('旁观指令', () {
    test('要求主动推进，不提问等回答、不描述读者反应', () {
      final d = buildParticipationDirective(
        participation: CharacterParticipation.spectator,
      );
      expect(d, contains('主动推进'));
      expect(d, contains('不要提问等待读者回答'));
      expect(d, contains('不要描述读者的反应'));
    });

    test('扮演会写明代入对象，且不许替读者说话', () {
      final d = buildParticipationDirective(
        participation: CharacterParticipation.roleplay,
        userPersona: '林黛玉',
      );
      expect(d, contains('扮演'));
      expect(d, contains('林黛玉'));
      expect(d, contains('不要替他说话'));
    });

    test('入场会强调他不属于这个世界', () {
      final d = buildParticipationDirective(
        participation: CharacterParticipation.join,
        userPersona: '张三',
      );
      expect(d, contains('入场'));
      expect(d, contains('张三'));
      expect(d, contains('不属于'));
    });

    test('没填名字时也有合理兜底，不会出现空引号', () {
      for (final p in CharacterParticipation.values) {
        final d = buildParticipationDirective(participation: p, userPersona: '');
        expect(d, isNot(contains('「」')));
      }
    });
  });

  group('连播间隔', () {
    test('给用户留出能按到「停止」的窗口', () {
      expect(autoPlayGap.inMilliseconds, greaterThanOrEqualTo(300));
    });
  });
}
