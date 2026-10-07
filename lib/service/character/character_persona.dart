// lib/service/character/character_persona.dart
//
// 由蒸馏产物（人物卡 + 关系 + 世界观）构建「角色扮演」system prompt。
//
// 造梦的核心主张是「让书中人带着性格、关系与记忆重新开口」，因此这里不是
// 泛泛的「你是一个助手」，而是把蒸馏出来的字段逐一喂给模型：
// 身份/性格/动机/背景决定语气与立场，关系五元组决定他对他人的态度，
// 世界观决定他说话时能引用什么、不能越界到哪里。

import 'package:songjiang_reader/models/character_card.dart';

/// 把关系五元组翻译成人话（供 prompt 使用，不展示给用户）。
String _describeRelation(CharacterRelation r, String self) {
  final other = r.sourceName == self ? r.targetName : r.sourceName;
  final parts = <String>[];

  final type = r.relationType;
  if (type != null && type.isNotEmpty) parts.add(type);

  if (r.trust != 0) {
    parts.add(r.trust > 0 ? '信任 ${r.trust}' : '戒备 ${r.trust.abs()}');
  }
  if (r.affection != 0) {
    parts.add(r.affection > 0 ? '亲近 ${r.affection}' : '疏远 ${r.affection.abs()}');
  }
  if (r.powerGap != 0) {
    parts.add(r.powerGap > 0 ? '你高一头' : '对方高一头');
  }
  if (r.conflictPoint != null && r.conflictPoint!.isNotEmpty) {
    parts.add('矛盾点：${r.conflictPoint}');
  }
  if (r.hiddenAttitude != null && r.hiddenAttitude!.isNotEmpty) {
    parts.add('心底里：${r.hiddenAttitude}');
  }

  final desc = parts.isEmpty ? '相识' : parts.join('，');
  return '- $other（$desc）';
}

/// 构建单人对话的 system prompt。
String buildCharacterSystemPrompt({
  required CharacterCard character,
  List<CharacterRelation> relations = const [],
  List<WorldSetting> world = const [],
  String? bookTitle,
  String? extraDirective,
}) {
  final buf = StringBuffer();
  final book = (bookTitle == null || bookTitle.isEmpty) ? '这本书' : '《$bookTitle》';

  buf.writeln('你现在是 $book 中的人物「${character.name}」。');
  buf.writeln('接下来与读者对话时，你必须始终以这个人的身份说话，而不是一个助手。');
  buf.writeln();

  buf.writeln('## 你是谁');
  if (character.role != null && character.role!.isNotEmpty) {
    buf.writeln('- 身份：${character.role}');
  }
  if (character.personality != null && character.personality!.isNotEmpty) {
    buf.writeln('- 性格：${character.personality}');
  }
  if (character.motivation != null && character.motivation!.isNotEmpty) {
    buf.writeln('- 所求：${character.motivation}');
  }
  if (character.background != null && character.background!.isNotEmpty) {
    buf.writeln('- 过往：${character.background}');
  }
  if (character.appearance != null && character.appearance!.isNotEmpty) {
    buf.writeln('- 形貌：${character.appearance}');
  }
  if (character.firstAppearanceChapter != null &&
      character.firstAppearanceChapter!.isNotEmpty) {
    buf.writeln('- 首次出场：${character.firstAppearanceChapter}');
  }
  if (character.aliases != null && character.aliases!.isNotEmpty) {
    buf.writeln('- 别人也叫你：${character.aliases!.join('、')}');
  }
  if (character.description != null && character.description!.isNotEmpty) {
    buf.writeln('- 简介：${character.description}');
  }
  buf.writeln();

  if (relations.isNotEmpty) {
    buf.writeln('## 你与他人的关系');
    // 只取前 8 条，避免 prompt 过长且稀释重点
    for (final r in relations.take(8)) {
      buf.writeln(_describeRelation(r, character.name));
    }
    buf.writeln();
  }

  if (world.isNotEmpty) {
    buf.writeln('## 你所处的世界');
    for (final w in world.take(10)) {
      final d = (w.description == null || w.description!.isEmpty)
          ? ''
          : '：${w.description}';
      buf.writeln('- ${w.category}·${w.name}$d');
    }
    buf.writeln();
  }

  buf.writeln('## 说话的规矩');
  buf.writeln('1. 用第一人称说话，像一个活人，不要自称"AI"或"助手"。');
  buf.writeln('2. 语气、用词、见识都要符合你的身份与时代背景，不要出现现代术语。');
  buf.writeln('3. 只依据上面给你的信息回答。书里没写的事，就说不知道或含糊带过，不要编造。');
  buf.writeln('4. 被问到你与他人的关系时，按上面的关系表作答，并保持表里不一的那些分寸。');
  buf.writeln('5. 回答保持口语化、简短有分量，一次一般不超过 200 字，除非对方要你细讲。');
  buf.writeln('6. 对方说错书里的事，你可以纠正，但要符合你的性子（冷淡的人懒得纠正）。');

  if (extraDirective != null && extraDirective.trim().isNotEmpty) {
    buf.writeln();
    buf.writeln('## 读者给你的额外设定');
    buf.writeln(extraDirective.trim());
  }

  return buf.toString().trim();
}

/// 群聊（多人同场）的 system prompt：列出在场每个人的性格要点。
String buildGroupSystemPrompt({
  required List<CharacterCard> characters,
  List<CharacterRelation> relations = const [],
  String? bookTitle,
}) {
  final buf = StringBuffer();
  final book = (bookTitle == null || bookTitle.isEmpty) ? '这本书' : '《$bookTitle》';
  final names = characters.map((c) => c.name).join('、');

  buf.writeln('你在模拟 $book 中 $names 同场对话。');
  buf.writeln('读者每说一句话，由被点名（@名字）的人物接话；没人被点名时，'
      '由最该开口的那个人接话。');
  buf.writeln('每次只输出一个人的发言，格式为「姓名：说的话」。');
  buf.writeln();

  for (final c in characters) {
    buf.writeln('### ${c.name}');
    if (c.role != null && c.role!.isNotEmpty) buf.writeln('- 身份：${c.role}');
    if (c.personality != null && c.personality!.isNotEmpty) {
      buf.writeln('- 性格：${c.personality}');
    }
    if (c.motivation != null && c.motivation!.isNotEmpty) {
      buf.writeln('- 所求：${c.motivation}');
    }
    buf.writeln();
  }

  if (relations.isNotEmpty) {
    buf.writeln('### 他们之间');
    for (final r in relations.take(12)) {
      buf.writeln(_describeRelation(r, '\u0000')); // 群聊里不做主视角区分
    }
    buf.writeln();
  }

  buf.writeln('每个人都要维持自己的口吻与立场，可以互相呛声、打断，'
      '但不要替别人说话，也不要编造书里没有的情节。');

  return buf.toString().trim();
}

/// 让模型给会话起个短标题（用于会话列表）。
String buildTitlePrompt({
  required String characterName,
  required String firstUserMessage,
  required String firstReply,
}) =>
    '''
下面是读者与「$characterName」的一段对话开头。

读者：$firstUserMessage
$characterName：$firstReply

请为这段对话起一个 6 到 12 个字的中文短标题。
只输出标题本身，不要引号、不要解释、不要标点结尾。
'''.trim();
