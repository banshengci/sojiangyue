// lib/service/character/relation_playbook.dart
//
// 把关系图翻译成「各怀心思」的行动指南。
//
// 原来关系在提示词里只是一句平铺的「信任 30，亲近 -20」，
// 模型读完不知道该拿它干什么，于是所有人都客客气气、谁也不算计谁——
// 关系图白喂了，几个角色听起来像同一个人换了名字。
//
// 这里把它变成可执行的东西：明面上怎么演、心里怎么想、会做什么、不会做什么。

import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/models/character_relation_merge.dart';

/// 一条关系对「我」意味着什么。
///
/// 界面上的「关系」面板也用它——提示词和 UI 必须说同一套话，
/// 否则玩家看到的「亲近」和模型演出来的「疏远」对不上。
class RelationStance {
  const RelationStance(this.surface, this.inner, this.willDo, this.wontDo);

  /// 明面上怎么待他
  final String surface;

  /// 心里其实怎么想
  final String inner;

  /// 会做的事
  final String willDo;

  /// 不会做的事
  final String wontDo;
}

/// 把一条关系翻成「明面 / 心里 / 会做 / 不会做」。
///
/// [outgoing] 为假表示这条关系写的是**对方**对我的态度：
/// 数值可以当近似值用，但心里话不能算在我头上（调用方自行决定要不要展示）。
RelationStance describeRelationStance(
  CharacterRelation r, {
  required bool outgoing,
}) {
  // 关系是有方向的：A→B 记的是 A 的态度。
  // 只有反向关系时，把数值当近似值用（人多数会礼尚往来），
  // 但表里不一与心结属于写下这条关系的那个人，绝不能搬给对方。
  final gap = outgoing ? r.powerGap : -r.powerGap;
  final trust = r.trust;
  final affection = r.affection;

  final String surface;
  if (affection <= -40) {
    surface = '不掩饰的敌意，话说得很难听';
  } else if (affection < -10) {
    surface = '疏远，只维持必要的礼数';
  } else if (affection >= 50) {
    surface = '亲近，说话随便，会互相损';
  } else if (affection >= 10) {
    surface = '和气，有来有往';
  } else {
    surface = '客气但隔着一层';
  }

  final String inner;
  if (trust >= 60) {
    inner = '把后背交给对方也不怕';
  } else if (trust >= 20) {
    inner = '大体信得过，但留着一手';
  } else if (trust > -20) {
    inner = '看不透，边走边看';
  } else if (trust > -60) {
    inner = '怀疑对方另有目的';
  } else {
    inner = '认定对方是敌人，只等时机';
  }

  final String willDo;
  final String wontDo;
  if (trust >= 60) {
    willDo = '会替对方把话圆上，有事会先通气';
    wontDo = '不会当面查对方';
  } else if (trust >= 20) {
    willDo = '会配合，会把不那么要紧的事交出去';
    wontDo = '不会把真正的底牌亮出来';
  } else if (trust > -20) {
    willDo = '会谈事，会试探，会顺着话往下问';
    wontDo = '不会先交底';
  } else {
    willDo = '会应下，会拖着，会借别人的手';
    wontDo = '不会真的照做';
  }

  final parts = <String>[surface];
  if (gap > 40) {
    parts.add('对方压得住你，你得低头');
  } else if (gap < -40) {
    parts.add('你压得住对方，不必客气');
  }

  return RelationStance(parts.join('；'), inner, willDo, wontDo);
}

/// 生成「各怀心思」段。
///
/// [characters] 在场人物（1~N），[relations] 最好是**只含在场人物之间**的关系；
/// 传进来的关系里指向场外的人会被跳过——场上没人接得住这条线。
///
/// [allowOffstageCounterpart] 用于单人对话：场上只有一个人，
/// 但"他对别人的态度"仍然是这个人的性格来源，不能因为对方没在场就丢掉。
String buildRelationPlaybook({
  required List<CharacterCard> characters,
  required List<CharacterRelation> relations,
  bool allowOffstageCounterpart = false,
}) {
  if (relations.isEmpty) return '';

  final onStage = <String>{
    for (final c in characters) canonicalPersonName(c.name),
  };
  if (onStage.isEmpty) return '';

  final buf = StringBuffer();
  buf.writeln('### 各怀心思（只在心里，不要说出来）');
  buf.writeln();

  var wroteAny = false;
  for (final c in characters) {
    final self = canonicalPersonName(c.name);

    // 每个对手只演一条：优先用「我→对方」那条（那才是我的态度）。
    // 双向关系同时存在时，反向那条写的是**对方的**心里话，
    // 混进来会让甲用乙的立场说话——前面就踩过这个坑。
    final byOther = <String, CharacterRelation>{};
    final outgoing = <String>{};
    for (final r in relations) {
      final s = canonicalPersonName(r.sourceName);
      final t = canonicalPersonName(r.targetName);
      if (s != self && t != self) continue;
      final other = s == self ? t : s;
      if (other == self) continue;
      if (!allowOffstageCounterpart && !onStage.contains(other)) continue;
      if (s == self) {
        byOther[other] = r;
        outgoing.add(other);
      } else if (!byOther.containsKey(other)) {
        byOther[other] = r;
      }
    }
    if (byOther.isEmpty) continue;

    wroteAny = true;
    buf.writeln('**${c.name}**');
    if (c.motivation != null && c.motivation!.trim().isNotEmpty) {
      buf.writeln('- 所求：${c.motivation!.trim()}　←　这是自己的算盘，不会主动说破');
    }
    for (final entry in byOther.entries.take(4)) {
      final other = entry.key;
      final r = entry.value;
      final isOutgoing = outgoing.contains(other);
      final st = describeRelationStance(r, outgoing: isOutgoing);
      final type = (r.relationType == null || r.relationType!.isEmpty)
          ? ''
          : '（${r.relationType}）';
      buf.writeln('- 对 **$other**$type');
      buf.writeln('  明面：${st.surface}');
      buf.writeln('  心里：${st.inner}');
      if (isOutgoing) {
        // 这两项属于写下这条关系的人，反向时不能借用
        if (r.hiddenAttitude != null && r.hiddenAttitude!.trim().isNotEmpty) {
          buf.writeln('  表里不一：${r.hiddenAttitude!.trim()}');
        }
        if (r.conflictPoint != null && r.conflictPoint!.trim().isNotEmpty) {
          buf.writeln('  心结：${r.conflictPoint!.trim()}');
        }
      }
      buf.writeln('  会：${st.willDo}　不会：${st.wontDo}');
    }
    buf.writeln();
  }

  if (!wroteAny) return '';

  buf.writeln('**怎么用这些关系演**');
  buf.writeln('1. 关系是**动机**，不是台词。不要把「信任多少」说出来，让它决定你怎么接话。');
  buf.writeln('2. 敌意常包在客气里，亲近常表现为不客气——越熟越敢损，越恨越客气。');
  buf.writeln('3. 同盟是暂时的：目标一致就并肩，目标一分就散。'
      '别为了场面和气放弃自己的目的。');
  buf.writeln('4. 信任是试探着给的：先递半句真话，看对方怎么接，再决定下一句。');
  buf.writeln('5. 表里不一的人，台词与内心相反；真心只在动作、停顿、改口里漏出来。');
  buf.writeln('6. 每个人都可以隐瞒、试探、借力，必要时利用别人——只要符合他的所求。');
  buf.writeln('7. 不要替别人决定立场，也不要让所有人都同意；有分歧才像真的。');
  buf.writeln('8. 若本局状态里已经有人物之间的好感/信任，**以本局的数值为准**，'
      '蒸馏出的关系只是起点。');
  buf.writeln();
  return buf.toString();
}
