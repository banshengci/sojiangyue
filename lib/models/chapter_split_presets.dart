import 'package:songjiang_reader/models/chapter_split_rule.dart';

const String kDefaultChapterSplitRuleId = 'default_chapter_rule';

final List<ChapterSplitRule> builtinChapterSplitRules = [
  ChapterSplitRule(
    id: kDefaultChapterSplitRuleId,
    name: 'Default (mixed languages)',
    // 说明：
    // 1. `chap(?:ter)?` —— 原写法 `(?:ter)` 是必选组，导致 "chap 3" 这类
    //    缩写永远匹配不上，与下方 samples 不符。
    // 2. 尾部新增 `[ 　]*\d+(?:[.。]\d+)*(?:[ 　]+.*)?` 分支，
    //    让 "Vol.2 A new world" 这种「关键字后无空格直接跟序号」也能命中。
    // 章题允许紧跟「第N章」而无空格（网文常见：第1章开局就离婚）。
    // 第二分支用 `[ 　]*` 而非 `[ 　]+`，避免必须有空白。
    pattern:
        r'^(?:(.+[ 　]+)|())(第[一二三四五六七八九十零〇百千万两0123456789]+[章卷]|卷[一二三四五六七八九十零〇百千万两0123456789]+|chap(?:ter)?\.?|vol(?:ume)?\.?|book|bk)(?:[ 　]*\d+(?:[.。]\d+)*(?:[ 　]+.*)?|[ 　]*(?:\S.*)?)?[ 　]*$',
    samples: [
      '第一章 起始之地',
      '第十二卷 风云再起',
      '第1章开局就离婚（加料 田曦薇）',
      'Chapter 12: The Journey',
      'chap 3. another life',
      'Book 1 - Dawn of Era',
      'Vol.2 A new world',
      'bk 4 - outside sample',
    ],
    isBuiltin: true,
    caseSensitive: false,
    multiLine: true,
  ),
  ChapterSplitRule(
    id: 'cn_only_numeric',
    name: 'Chinese (第X章)',
    // 章号后可有可无空格/标点，再跟标题（网文常无空格）
    pattern: r'^\s*第[一二三四五六七八九十零〇百千万两0123456789]+章(?:[ ：:.-]?.*)?$',
    samples: [
      '第一章 少年出山',
      '第二十章 ：终极之战',
      '第3章- 遗失的记忆',
      '第四十章 序章',
    ],
    isBuiltin: true,
    caseSensitive: false,
    multiLine: true,
  ),
  ChapterSplitRule(
    id: 'en_chapter_number',
    name: 'English (Chapter N)',
    // 除阿拉伯数字外，也接受 one ~ twenty 的英文拼写（不少英文书用 "Chapter One"）
    pattern:
        r'^\s*chapter\s+(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)(?:[ .:-].*)?$',
    samples: [
      'Chapter 1: Beginning',
      'chapter 23 - A twist',
      'CHAPTER 99. Finale',
      'chapter one',
    ],
    isBuiltin: true,
    caseSensitive: false,
    multiLine: true,
  ),
  ChapterSplitRule(
    id: 'en_volume_number',
    name: 'English (Volume/Book)',
    // `vol(?:ume)?\.?` 让 "vol. 4" 这类缩写也能命中（原写法只认 volume/book 全拼）
    pattern: r'^\s*(vol(?:ume)?\.?|book)\s+\d+(?:[ .:-].*)?$',
    samples: [
      'Volume 1: Arrival',
      'Book 2 - Secrets',
      'volume 03 introduction',
      'vol. 4',
    ],
    isBuiltin: true,
    caseSensitive: false,
    multiLine: true,
  ),
];

ChapterSplitRule getDefaultChapterSplitRule() {
  return builtinChapterSplitRules.firstWhere(
    (rule) => rule.id == kDefaultChapterSplitRuleId,
  );
}

ChapterSplitRule? findBuiltinChapterSplitRuleById(String id) {
  try {
    return builtinChapterSplitRules.firstWhere((rule) => rule.id == id);
  } catch (_) {
    return null;
  }
}
