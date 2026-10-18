import 'dart:convert';

// lib/service/character/dialogue_suggestions.dart
//
// 「帮我写下一句」：让模型代拟几条可以直接发出去的台词。
//
// 与「导演」的分工：
//   导演 = 决定**戏往哪走**（推进 / 放缓 / 冲突 / 换视角）
//   建议 = 决定**你这句话怎么说**，并给出三个不同方向的具体文本
//
// 关键设计是 anchor：每条建议都必须锚定上一轮角色说过的原话（连续摘录 4–20 字）。
// 没有锚点的建议会滑向"泛泛的接话"，用户一眼就知道模型没在听。

/// 一条代写建议。
class ChatSuggestion {
  const ChatSuggestion({
    required this.label,
    required this.text,
    this.anchor = '',
  });

  /// 方向标签（4–10 字）。
  final String label;

  /// 可以直接发出去的话。
  final String text;

  /// 承接自角色原话的摘录（用于校验关联性，不展示或仅作提示）。
  final String anchor;
}

/// 组装提示词。
///
/// [participation] 决定"你是谁"：旁观者只能推动场景，扮演/入场要以角色身份说话。
String buildSuggestionPrompt({
  required String characterName,
  required String latestReply,
  String? userPersona,
  String participationCode = 'spectator',
  int count = 3,
}) {
  final who = switch (participationCode) {
    'roleplay' => '你正在扮演「${(userPersona ?? '').trim().isEmpty ? '书中某个人物' : userPersona!.trim()}」，'
        '要写的是这个人物会说出口的话。',
    'join' => '你以「${(userPersona ?? '').trim().isEmpty ? '外来者' : userPersona!.trim()}」的身份在场，'
        '要写的是这个外来者会说的话。',
    _ => '你在旁观这一场，要写的是**推动场景**的一句话：让局面往前走，'
        '像"下一下已经发生了"，而不是"要不要/不如/可以"这种商量口吻。',
  };

  final buf = StringBuffer();
  buf.writeln('你在为读者代笔，写他下一句可以发出去的话。$who');
  buf.writeln();
  buf.writeln('刚刚「$characterName」说的是：');
  buf.writeln('「${latestReply.trim()}」');
  buf.writeln();
  buf.writeln('写 $count 条候选，要求：');
  buf.writeln('1. 每一条都必须承接上面这句话里**具体提到**的内容，不能泛泛接话；');
  buf.writeln('2. 三条方向要有实质区别：一条追问信息，一条偏向情绪或关系，一条偏向行动或场景；');
  buf.writeln('3. 每条一到三句，是能直接发出去的成品，不要写"你可以回复……"这种说明；');
  buf.writeln('4. 不要重复已经发生过的事，也不要替角色决定他还没做的动作。');
  buf.writeln();
  buf.writeln('只输出 JSON 数组，不要解释、不要代码围栏：');
  buf.writeln(
    '[{"label":"4到10个字的方向","text":"可以直接发出去的一到三句话",'
    '"anchor":"从上面对白里连续摘录4到20字"}]',
  );
  return buf.toString();
}

/// 解析模型返回的建议数组。
///
/// 容错：允许带代码围栏、允许外层包成 {"suggestions":[...]}；
/// 没有 text 的条目直接丢弃——空建议比没有建议更烦人。
List<ChatSuggestion> parseSuggestions(String raw, {int max = 4}) {
  var text = raw.trim();
  if (text.isEmpty) return const [];
  text = text
      .replaceAll(RegExp(r'```(?:json)?', multiLine: true), '')
      .replaceAll('```', '')
      .trim();

  Object? decoded;
  final start = text.indexOf('[');
  final end = text.lastIndexOf(']');
  if (start >= 0 && end > start) {
    try {
      decoded = _tryDecode(text.substring(start, end + 1));
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded == null) {
    final objStart = text.indexOf('{');
    final objEnd = text.lastIndexOf('}');
    if (objStart >= 0 && objEnd > objStart) {
      try {
        final map = _tryDecode(text.substring(objStart, objEnd + 1));
        if (map is Map) decoded = map['suggestions'];
      } catch (_) {
        decoded = null;
      }
    }
  }
  if (decoded is! List) return const [];

  final out = <ChatSuggestion>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    final body = (e['text'] ?? '').toString().trim();
    if (body.isEmpty) continue;
    out.add(
      ChatSuggestion(
        label: (e['label'] ?? '').toString().trim(),
        text: body,
        anchor: (e['anchor'] ?? '').toString().trim(),
      ),
    );
    if (out.length >= max) break;
  }
  return out;
}

Object? _tryDecode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}
