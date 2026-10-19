// lib/service/gameplay/gameplay_setup.dart
//
// 把「开局设定」拆成人能看的三块：公开信息 / 规则 / 暗牌。
//
// 为什么要有这一步：开局那段文本原先整段塞进 `GameplaySession.secret`，
// 只注入给模型。结果「规则怪谈」的四条规则玩家根本看不到，
// 「海龟汤」连汤面都不给——玩法就退化成"听 AI 讲一个我参与不了的故事"。
// 规则怪谈的全部乐趣在于「拿着规则去试探」，规则不在玩家手里，机制就是空的。
//
// 约定模型按标记输出（见 GameplayRuntime.buildSetupPrompt），这里负责解析；
// 认不出来时一律归入暗牌——宁可少显示，也不能把真相漏给玩家。

/// 开局设定的结构化视图。
class GameplaySetup {
  const GameplaySetup({
    this.publicBrief = '',
    this.rules = const [],
    this.secret = '',
  });

  /// 玩家一开始就知道的信息（海龟汤的汤面、命案的现场概况、怪谈的场景）。
  final String publicBrief;

  /// 玩家必须遵守的硬规则（规则怪谈的四条、海龟汤的提问规矩）。
  final List<String> rules;

  /// 只有模型知道的真相（汤底、凶手与手法、致命规则是哪条）。
  final String secret;

  static const String publicTag = '【公开】';
  static const String rulesTag = '【规则】';
  static const String secretTag = '【暗牌】';

  // 旧格式（早期提示词用的是海龟汤的标记）
  static const String _soupFaceTag = '【汤面】';
  static const String _soupBottomTag = '【汤底】';

  /// 是否有可以给玩家看的东西。
  bool get hasVisible =>
      publicBrief.trim().isNotEmpty || rules.isNotEmpty;

  factory GameplaySetup.parse(String? raw) {
    final text = (raw ?? '').replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return const GameplaySetup();

    if (text.contains(publicTag) ||
        text.contains(rulesTag) ||
        text.contains(secretTag)) {
      return GameplaySetup(
        publicBrief: _section(text, publicTag, [rulesTag, secretTag]),
        rules: _parseRules(_section(text, rulesTag, [publicTag, secretTag])),
        secret: _section(text, secretTag, [publicTag, rulesTag]),
      );
    }

    // 旧数据：海龟汤只有【汤面】【汤底】两个标记
    if (text.contains(_soupFaceTag) || text.contains(_soupBottomTag)) {
      return GameplaySetup(
        publicBrief: _section(text, _soupFaceTag, [_soupBottomTag]),
        secret: _section(text, _soupBottomTag, [_soupFaceTag]),
      );
    }

    // 认不出来：整段当暗牌
    return GameplaySetup(secret: text);
  }

  /// 取 [tag] 到下一个标记之间的内容。
  static String _section(String text, String tag, List<String> others) {
    final start = text.indexOf(tag);
    if (start < 0) return '';
    final from = start + tag.length;
    var end = text.length;
    for (final other in others) {
      final i = text.indexOf(other, from);
      if (i >= 0 && i < end) end = i;
    }
    return text.substring(from, end).trim();
  }

  /// 规则块 → 一条条规则（去掉「1.」「-」这类前缀）。
  static List<String> _parseRules(String block) {
    final trimmed = block.trim();
    if (trimmed.isEmpty || trimmed == '无' || trimmed == '（无）') return const [];
    return trimmed
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l != '无' && l != '（无）')
        .map((l) => l
            .replaceFirst(
              RegExp(r'^(\d+\s*[.、)）]|[-*·]|[（(]\d+[）)])\s*'),
              '',
            )
            .trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }
}

/// 海龟汤允许的三个答案。
const List<String> kYesNoAnswers = ['与此无关', '是', '否'];

/// 把回复规范化成「是 / 否 / 与此无关」；不是这三个之一就返回 null。
///
/// 模型常写「是的，因为……」——那正是海龟汤不许做的事。
/// 这里只做识别，要不要截断由调用方决定（见 [enforceYesNo]）。
String? parseYesNo(String raw) {
  var t = raw.trim();
  // 去掉开头的引号、括号、空白（模型爱给答案加壳）
  t = t.replaceFirst(RegExp(r'''^[\s「『“"'（(]+'''), '');
  if (t.isEmpty) return null;
  if (t.startsWith('与此无关') || t.startsWith('无关')) return '与此无关';
  if (t.startsWith('不是') ||
      t.startsWith('不对') ||
      t.startsWith('没有') ||
      t.startsWith('否')) {
    return '否';
  }
  if (t.startsWith('是') || t.startsWith('对') || t.startsWith('没错')) {
    return '是';
  }
  return null;
}
