// lib/service/character/director_action.dart
//
// 「导演」：不是简单地"继续"，而是告诉这场戏**下一步该往哪走**。
//
// 为什么需要：只有「继续演出」时，模型只能往前推，用户想让两个人先吵起来、
// 或者先停一下写写内心，没有表达途径。这里给五种意图 + 一句可选目标，
// 拼成一段舞台指令，作为本轮请求的"用户发言"（不落库、不进历史）。
//
// 机制借鉴自同类作品的「导演四项/五项」，提示词全部自行撰写。

/// 导演意图。
enum DirectorAction {
  /// 推进情节。
  advance(
    '推进',
    '让情节向前一步',
    '让情节自然向前推进一步：有人做出决定、有事情发生，不要停在原地打转。',
  ),

  /// 放慢节奏，聚焦情绪。
  slowEmotion(
    '情绪放缓',
    '聚焦内心与关系温度',
    '把节奏放慢：写内心的犹豫、停顿与没说出口的话，写两人之间的温度变化；'
        '不要推进外部事件，也不要制造新的麻烦。',
  ),

  /// 制造冲突。
  conflict(
    '制造冲突',
    '抛出分歧或对立',
    '让矛盾显形：两个人的立场出现真实分歧，或者有人提出对方无法接受的条件。'
        '冲突要有来由，不要为了吵而吵。',
  ),

  /// 切换视角。
  viewpoint(
    '切换视角',
    '换一个人主视叙述',
    '换一个人来主视：用另一个在场人物的眼睛看这一幕，'
        '让读者听到他/她心里想的和嘴上说的不一样。',
  ),

  /// 打破第四面墙。
  fourthWall(
    '破第四面墙',
    '角色察觉到自己在故事里',
    '让角色短暂地意识到自己在故事中：可以质疑作者、评论设定、'
        '或者直接对读者说话。只破一次，破完要回到戏里。',
  );

  const DirectorAction(this.label, this.hint, this.instruction);

  /// 展示名。
  final String label;

  /// 一句话说明（界面上给用户看）。
  final String hint;

  /// 注入给模型的舞台指令。
  final String instruction;
}

/// 组装本轮的舞台指令。
///
/// [goal] 是用户这次想达成的目标（可空）。非空时附在最后，
/// 并且明确要求"不要直接说出目标"，否则模型会把它写成任务说明。
String buildDirectorDirective(
  DirectorAction action, {
  String? goal,
}) {
  final g = (goal ?? '').trim();
  final buf = StringBuffer();
  buf.write('【导演指令 · ${action.label}】');
  buf.write(action.instruction);
  if (g.isNotEmpty) {
    buf.write('\n这一次的目标是：$g。');
    buf.write('把目标落成具体的行动与台词，不要把它当成任务说明念出来。');
  }
  return buf.toString();
}
