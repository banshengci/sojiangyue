/// 网文 TXT 正文清洗（导入时一键清理，不改用户原文件）。
///
/// 目标：去掉站点广告/页眉页脚/跳转提示，保留章节与正文，
/// 让后续章节切分与 EPUB 分段更干净。
library;

/// 可能是广告/导航的行（命中任意一条即丢弃）。
final List<RegExp> _adLinePatterns = [
  // URL / 域名整行
  RegExp(r'^\s*(https?://|www\.)\S+\s*$'),
  RegExp(r'^\s*\S+\.(com|net|org|cn|cc|xyz|top|vip|la|me|info|cc)\s*(/\S*)?\s*$', caseSensitive: false),
  // 笔趣阁 / 起点等站点推广
  RegExp(r'(笔趣阁|最快更新|无弹窗|免费阅读|记住本站|收藏本站|加入书签|加入书架)', caseSensitive: false),
  RegExp(r'(手机用户请|请访问|请收藏|请牢记|本书首发|本书由|转载请注明|本站域名)', caseSensitive: false),
  RegExp(r'(下载APP|打开APP|扫码|二维码|广告|推广|合作|联系客服|QQ群|微信群)', caseSensitive: false),
  RegExp(r'(最新网址|最新地址|永久地址|备用地址|防采集|防失联)', caseSensitive: false),
  // 分页导航
  RegExp(r'^\s*(上一章|下一章|返回目录|目录页?|加入书签|推荐本书|投推荐票|月票|催更)\s*$'),
  RegExp(r'^\s*(<上一章|下一章>|【上一章】【下一章】)\s*$'),
  // 明显的“本章完/未完待续”单独页可保留，但“点击继续阅读”类丢弃
  RegExp(r'(点击下一章|继续阅读|阅读更多|展开全文|剩余章节)', caseSensitive: false),
  // 纯数字页码/时间戳样式的噪声行（过短且无中文）
  RegExp(r'^\s*\d{1,4}\s*$'),
  // 仅符号分隔线
  RegExp(r'^\s*[-=_~*·…]{3,}\s*$'),
  // 零宽/控制字符（在 normalize 里处理，这里兜底匹配行）
  RegExp(r'^\s*[\u200B\u200C\u200D\uFEFF\u00A0]+\s*$'),
];

/// 去掉行首行尾空白（含全角空格），并压缩连续空白。
String _trimWebLine(String line) {
  var t = line.replaceAll('﻿', '').replaceAll('​', '');
  t = t.replaceAll(' ', ' ');
  t = t.trim();
  while (t.startsWith('　')) {
    t = t.substring(1);
  }
  while (t.endsWith('　')) {
    t = t.substring(0, t.length - 1);
  }
  return t.trim();
}

bool _isNoiseLine(String line) {
  if (line.isEmpty) return true;
  for (final re in _adLinePatterns) {
    if (re.hasMatch(line)) return true;
  }
  return false;
}

/// 清洗整篇网文 TXT 正文。
///
/// - 过滤广告/导航/页码噪声行
/// - 折叠连续空行为空一行
/// - 保留章节标题行（含「第N章」等）
/// - 去掉文首到第一个章节前的大段站点说明（若存在大量噪声行）
String cleanWebNovelText(String input) {
  final normalized = input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('﻿', '')
      .replaceAll('​', '')
      .replaceAll('‌', '')
      .replaceAll('‍', '');

  final rawLines = normalized.split('\n');
  final cleaned = <String>[];
  var blankRun = 0;

  for (final raw in rawLines) {
    final line = _trimWebLine(raw);
    if (line.isEmpty) {
      blankRun++;
      if (blankRun <= 1) {
        cleaned.add('');
      }
      continue;
    }
    blankRun = 0;
    if (_isNoiseLine(line)) {
      continue;
    }
    cleaned.add(line);
  }

  // 去掉首尾空行
  while (cleaned.isNotEmpty && cleaned.first.isEmpty) {
    cleaned.removeAt(0);
  }
  while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
    cleaned.removeLast();
  }

  return cleaned.join('\n');
}

/// 供测试/调试：统计清洗删除的行数。
int countRemovedLines(String before, String after) {
  final b = before
      .split('\n')
      .map(_trimWebLine)
      .where((l) => l.isNotEmpty)
      .length;
  final a = after
      .split('\n')
      .map(_trimWebLine)
      .where((l) => l.isNotEmpty)
      .length;
  return b - a;
}
