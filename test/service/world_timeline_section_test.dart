import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/character/world_timeline.dart';

/// 世界时间线注入对话。
///
/// 时间线本身早就存在（表、模型、DAO、展示页、蒸馏抽取都有），
/// 缺的只是"送进对话"这一步。这里锁住渲染的形状，
/// 免得注入一段角色读不懂的东西——或者在没有事件时污染 prompt。
void main() {
  TimelineEvent ev({
    String title = '黛玉进贾府',
    String? chapter,
    String? timeNote,
  }) =>
      TimelineEvent(
        bookId: 1,
        title: title,
        chapter: chapter,
        timeNote: timeNote,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  test('没有事件时返回空串（不污染 prompt）', () {
    expect(buildTimelineSection(const []), '');
  });

  test('有序号、章节、事件名', () {
    final s = buildTimelineSection([
      ev(title: '黛玉进贾府', chapter: '第三回'),
      ev(title: '宝玉摔玉', chapter: '第三回'),
    ]);
    expect(s, contains('世界时间线'));
    expect(s, contains('1. 【第三回】黛玉进贾府'));
    expect(s, contains('2. 【第三回】宝玉摔玉'));
  });

  test('有时间标注时带上', () {
    final s = buildTimelineSection([ev(timeNote: '同年冬')]);
    expect(s, contains('同年冬'));
  });

  test('章节/时间缺失时不出现空括号', () {
    final s = buildTimelineSection([ev(title: '某事')]);
    expect(s, contains('1. 某事'));
    expect(s, isNot(contains('【】')));
    expect(s, isNot(contains('（）')));
  });

  test('要求角色不要逐条复述（避免把时间线变成台词）', () {
    final s = buildTimelineSection([ev()]);
    expect(s, contains('不要逐条复述'));
  });
}
