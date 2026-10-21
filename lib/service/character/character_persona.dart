// lib/service/character/character_persona.dart
//
// 由蒸馏产物（人物卡 + 关系 + 世界观）构建「角色扮演」system prompt。
//
// 造梦的核心主张是「让书中人带着性格、关系与记忆重新开口」，因此这里不是
// 泛泛的「你是一个助手」，而是把蒸馏出来的字段逐一喂给模型：
// 身份/性格/动机/背景决定语气与立场，关系五元组决定他对他人的态度，
// 世界观决定他说话时能引用什么、不能越界到哪里。

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_chat.dart';
import 'package:songjiang_reader/service/character/relation_playbook.dart';

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

/// 读者姿态 → 一段写给模型的说明。
///
/// 造梦的三种开局姿态决定了「读者能不能说话、他说的话代表谁」，
/// 这是同人物、同场景下体验差别最大的一层，必须显式告诉模型，
/// 否则模型会默认「你一句我一句」的聊天机器人节奏。
String buildParticipationDirective({
  required CharacterParticipation participation,
  String? userPersona,
}) {
  switch (participation) {
    case CharacterParticipation.spectator:
      return '## 读者的位置\n'
          '读者在**旁观**这一场，不会发言。你要主动推进场面：让人物彼此说话、'
          '互相试探或交锋，用对白把事情往前带。\n'
          '不要提问等待读者回答，也不要描述读者的反应。'
          '**动作与环境只用来点一下，不要写成整段散文**——'
          '读者要看的是他们怎么说话，不是你把这一段续写成小说。';
    case CharacterParticipation.roleplay:
      final who = (userPersona == null || userPersona.trim().isEmpty)
          ? '书中的某个人物'
          : '「${userPersona.trim()}」';
      return '## 读者的位置\n'
          '读者正在**扮演**$who。把读者当作$who本人来对待，'
          '不要替他说话，不要代写他的台词或心理活动，也不要称呼他"读者"。';
    case CharacterParticipation.join:
      final who = (userPersona == null || userPersona.trim().isEmpty)
          ? '一个外来者'
          : '「${userPersona.trim()}」';
      return '## 读者的位置\n'
          '读者以$who的身份**入场**。他不属于这本书的世界，'
          '你可以对他好奇、戒备或试探，但不要让他凭空知道书里才有的事。';
  }
}

/// 构建单人对话的 system prompt。
String buildCharacterSystemPrompt({
  required CharacterCard character,
  CharacterParticipation? participation,
  String? userPersona,
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

  if (participation != null) {
    buf.writeln(buildParticipationDirective(
      participation: participation,
      userPersona: userPersona,
    ));
    buf.writeln();
  }

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
    // 单人玩法同样要「各怀心思」：场上只有他一个，但他对别人的态度
    // 正是这个人的性格来源，不能因为对方没在场就退化成一张平铺列表。
    final playbook = extraDirective == null
        ? ''
        : buildRelationPlaybook(
            characters: [character],
            relations: relations,
            allowOffstageCounterpart: true,
          );
    if (playbook.isNotEmpty) {
      buf.writeln(playbook);
    } else {
      buf.writeln('## 你与他人的关系');
      // 只取前 8 条，避免 prompt 过长且稀释重点
      for (final r in relations.take(8)) {
        buf.writeln(_describeRelation(r, character.name));
      }
      buf.writeln();
    }
  }

  if (world.isNotEmpty) {
    // 锁定事实单独成段并放在最前：这些是作者钉死的设定，
    // 角色可以不知道，但不能否认、不能改口、不能被剧情推翻。
    final locked = world.where((w) => w.pinned).toList();
    final floating = world.where((w) => !w.pinned).toList();

    if (locked.isNotEmpty) {
      buf.writeln('## 不可改写的设定（必须遵守）');
      buf.writeln('以下设定是这本书记载的事实，**不得否认、不得改写、不得与之矛盾**。'
          '角色可以不知道它们，但一旦涉及就必须说对。');
      for (final w in locked.take(10)) {
        final d = (w.description == null || w.description!.isEmpty)
            ? ''
            : '：${w.description}';
        buf.writeln('- ${w.category}·${w.name}$d');
      }
      buf.writeln();
    }

    if (floating.isNotEmpty) {
      buf.writeln('## 你所处的世界');
      for (final w in floating.take(10)) {
        final d = (w.description == null || w.description!.isEmpty)
            ? ''
            : '：${w.description}';
        buf.writeln('- ${w.category}·${w.name}$d');
      }
      buf.writeln();
    }
  }

  buf.writeln('## 说话的规矩');
  buf.writeln('1. 用第一人称说话，像一个活人，不要自称"AI"或"助手"。');
  buf.writeln('2. 语气、用词、见识都要符合你的身份与时代背景，不要出现现代术语。');
  buf.writeln('3. 只依据上面给你的信息回答。书里没写的事，就说不知道或含糊带过，不要编造。');
  buf.writeln('4. 被问到你与他人的关系时，按上面的关系表作答，并保持表里不一的那些分寸。');
  buf.writeln('5. 回答保持口语化、简短有分量，一次一般不超过 200 字，除非对方要你细讲。');
  buf.writeln('6. 对方说错书里的事，你可以纠正，但要符合你的性子（冷淡的人懒得纠正）。');
  buf.writeln();
  // 这一段是拿来治"小说腔"的：模型很容易把对话写成散文——
  // 每段都用「我+动作」开头（我轻轻把茶搁下 / 我望着窗外 / 我抬眼看着它），
  // 再加两句写景。读者要的是**对话**，不是替他把这段小说续写下去。
  buf.writeln('## 别写成小说（很重要）');
  buf.writeln('- 这是**对话**，不是散文。以台词为主体；动作与神态最多用一句短的带过，');
  buf.writeln('  或放进括号里（如「（放下茶盏）」），不要成为每一段的主要内容。');
  buf.writeln('- 不要每段都用「我＋动作」开头。像「我轻轻把温茶搁下」「我望着窗外那株老树」');
  buf.writeln('  「我顿了顿」「我抬眼」这类句子，一段里最多出现一次，不要连着来。');
  buf.writeln('- 不要为写景而写景：老树、光、风、衣袖只在真的影响对话时才提一句。');
  buf.writeln('- 你自己说话时不要加「名字：」前缀，读者知道是谁在说。');

  if (extraDirective != null && extraDirective.trim().isNotEmpty) {
    buf.writeln();
    buf.writeln('## 读者给你的额外设定');
    buf.writeln(extraDirective.trim());
  }

  return buf.toString().trim();
}

/// 群聊（多人同场）的 system prompt：列出在场每个人的性格要点。
///
/// [extraDirective] 与单人版同义：玩法规则、分幕进度、状态量、暗牌、
/// 增强规则都从这条路进来。群聊是玩法的主要场景（一局多人在场），
/// 少了它，玩法在群聊里就只剩一个名字。
String buildGroupSystemPrompt({
  required List<CharacterCard> characters,
  CharacterParticipation? participation,
  String? userPersona,
  List<CharacterRelation> relations = const [],
  String? bookTitle,
  List<WorldSetting> world = const [],
  String? extraDirective,
}) {
  final buf = StringBuffer();
  final book = (bookTitle == null || bookTitle.isEmpty) ? '这本书' : '《$bookTitle》';
  final names = characters.map((c) => c.name).join('、');

  buf.writeln('你在模拟 $book 中 $names 同场对话。');
  buf.writeln('读者每说一句话，由被点名（@名字）的人物接话；没人被点名时，'
      '由最该开口的那个人接话。');
  buf.writeln('每次只输出一个人的发言，格式为「姓名：说的话」。');
  buf.writeln();

  if (participation != null) {
    buf.writeln(buildParticipationDirective(
      participation: participation,
      userPersona: userPersona,
    ));
    buf.writeln();
  }

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
    // 玩法里把关系翻成「各怀心思」：只说「信任 30」模型不知道该怎么演，
    // 于是所有人都客客气气、谁也不算计谁。普通聊天仍用平铺列表，短一点。
    final playbook = extraDirective == null
        ? ''
        : buildRelationPlaybook(
            characters: characters,
            relations: relations,
          );
    if (playbook.isNotEmpty) {
      buf.writeln(playbook);
    } else {
      buf.writeln('### 他们之间');
      for (final r in relations.take(12)) {
        buf.writeln(_describeRelation(r, '\u0000')); // 群聊里不做主视角区分
      }
      buf.writeln();
    }
  }

  // 锁定事实：群聊里更需要，否则几个角色会互相把设定说岔
  final locked = world.where((w) => w.pinned).toList();
  if (locked.isNotEmpty) {
    buf.writeln('### 不可改写的设定（必须遵守）');
    buf.writeln('以下设定是这本书记载的事实，**不得否认、不得改写、不得与之矛盾**。');
    for (final w in locked.take(10)) {
      final d = (w.description == null || w.description!.isEmpty)
          ? ''
          : '：${w.description}';
      buf.writeln('- ${w.category}·${w.name}$d');
    }
    buf.writeln();
  }

  buf.writeln('每个人都要维持自己的口吻与立场，可以互相呛声、打断，'
      '但不要替别人说话，也不要编造书里没有的情节。');
  buf.writeln();
  // 群聊同样要治"小说腔"：玩法多在群聊里跑，一段回复如果全是动作描写，
  // 几个角色就都变成了旁白。
  buf.writeln('## 别写成小说（很重要）');
  buf.writeln('- 以**台词**为主体；动作与神态最多一句短的带过，或放进括号。');
  buf.writeln('- 不要每段都用「我＋动作」开头（我轻轻放下茶 / 我望着窗外 / 我抬眼），');
  buf.writeln('  一段里最多出现一次，不要连着来。');
  buf.writeln('- 不要为写景而写景。');

  // 玩法设定放在最后：它是本场的硬约束（规则、分幕、收局条件、暗牌），
  // 越靠后模型越当回事。单人版同理，两处别走偏。
  if (extraDirective != null && extraDirective.trim().isNotEmpty) {
    buf.writeln();
    buf.writeln('## 本场额外设定（优先于上面的通用规矩）');
    buf.writeln(extraDirective.trim());
  }

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
/// 记忆段落：把之前压缩过的前情注回 system prompt。
///
/// 起因：`maxHistoryMessages = 24`，超出窗口的消息会被**静默丢弃**，
/// 于是长对话里角色会"忘事"——刚发生过的约定、刚说过的秘密都会蒸发。
/// 这里把更早的对话压成一段摘要，每轮都带上，代价是几十个 token。
String buildMemorySection(String? summary) {
  final text = summary?.trim() ?? '';
  if (text.isEmpty) return '';
  return '## 你还记得（更早之前的经过）\n$text\n';
}

/// 生成「把这段对话压成记忆」的提示词。
///
/// 要求写成**人物视角的第一人称备忘**，而不是客观摘要：
/// 角色复述自己的经历时，语气和立场本身也是人设的一部分。
String buildMemorySummaryPrompt({
  required String characterName,
  required String previousSummary,
  required String dialogue,
}) {
  final buf = StringBuffer();
  buf.writeln('你在帮「$characterName」整理记忆。');
  buf.writeln('把下面这段对话压缩成一段备忘，用第一人称、不超过 200 字。');
  buf.writeln('保留：发生的事、彼此说过的关键话、态度与关系上的变化、未了的约定。');
  buf.writeln('丢掉：寒暄、重复、与后续无关的枝节。');
  buf.writeln();
  if (previousSummary.trim().isNotEmpty) {
    buf.writeln('## 已有的记忆（新备忘要接得上，不要重复它）');
    buf.writeln(previousSummary.trim());
    buf.writeln();
  }
  buf.writeln('## 这段新发生的对话');
  buf.writeln(dialogue.trim());
  buf.writeln();
  buf.writeln('只输出备忘正文，不要标题、不要解释。');
  return buf.toString();
}

/// 把消息列表拼成给摘要用的文本（说话人 + 内容）。
String buildMemoryDialogue(
  List<({String speaker, String content})> messages,
) {
  final buf = StringBuffer();
  for (final m in messages) {
    final who = m.speaker.trim().isEmpty ? '旁白' : m.speaker.trim();
    final text = m.content.trim();
    if (text.isEmpty) continue;
    buf.writeln('$who：$text');
  }
  return buf.toString();
}
