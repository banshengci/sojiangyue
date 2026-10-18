import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/page/character/session_setup_sheet.dart';

/// 开局面板的准入规则。
///
/// 造梦的开局要同时定三件事（你的位置 / 你是谁 / 谁在场），
/// 这里锁住「什么时候允许点开始」——放过去就会出现
/// 「扮演了但没说是谁」「一个人都没选却开局」这种空局。
void main() {
  final cards = <CharacterCard>[
    CharacterCard(
      bookId: 1,
      name: '林黛玉',
      role: '贾府表小姐',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
    CharacterCard(
      bookId: 1,
      name: '贾宝玉',
      role: '荣府公子',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];

  SessionSetup? result;

  Widget host() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showSessionSetupSheet(
                    context,
                    bookId: 1,
                    cards: cards,
                    title: '剧本杀 · 开局',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  setUp(() => result = null);

  testWidgets('默认旁观；没选人物时不能开始', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('剧本杀 · 开局'), findsOneWidget);
    // 三个姿态都在
    for (final p in CharacterParticipation.values) {
      expect(find.text(p.label), findsOneWidget);
    }
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull, reason: '没选在场人物时应禁用');
    expect(find.text('选好人物后才能开始'), findsOneWidget);
  });

  testWidgets('选 1 位人物后旁观可开局，身份为空', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, '林黛玉'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.participation, CharacterParticipation.spectator);
    expect(result!.userPersona, isNull);
    expect(result!.characters.map((c) => c.name), ['林黛玉']);
  });

  testWidgets('多选两位 → 交给上层判定为群聊', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, '林黛玉'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '贾宝玉'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result!.characters.length, 2);
  });

  testWidgets('切到「扮演」会带出身份选择，且默认落在第一个人物', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('扮演'));
    await tester.pumpAndSettle();

    expect(find.text('你扮演谁'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, '林黛玉'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result!.participation, CharacterParticipation.roleplay);
    expect(result!.userPersona, '林黛玉');
  });

  testWidgets('切到「入场」时，没填名字不能开始', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('入场'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '林黛玉'));
    await tester.pumpAndSettle();

    expect(find.text('你叫什么'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull, reason: '入了场却没名字，不该放行');

    await tester.enterText(find.byType(TextField), '阿舟');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result!.participation, CharacterParticipation.join);
    expect(result!.userPersona, '阿舟');
  });

  testWidgets('场景可跳过：默认「不选场景」', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('场景（可跳过）'), findsOneWidget);
    expect(find.text('不选场景'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
  });

  testWidgets('新建场景：名字或情境为空时保存按钮禁用', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();

    expect(find.text('新建场景'), findsOneWidget);
    // 两个输入框都空 → 保存禁用
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );
    expect(save.onPressed, isNull);

    // 只填名字仍不够
    await tester.enterText(find.widgetWithText(TextField, '场景名'), '雨夜书房');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed,
      isNull,
    );

    // 补上情境后可用
    await tester.enterText(find.widgetWithText(TextField, '情境'), '窗外下雨，灯芯快烧尽了');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed,
      isNotNull,
    );
  });}
