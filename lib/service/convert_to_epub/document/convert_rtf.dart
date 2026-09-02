import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/chapter_draft.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把 RTF（富文本格式）文件转换为 EPUB。
///
/// RTF 是基于转义控制字的纯文本格式。这里实现一个够用的解析器：
/// - 处理 `\b`/`\i`/`\ul` 粗体/斜体/下划线（含 `\b0` 等关闭指令）；
/// - 处理 `\uNNNN` Unicode 转义与 `\'xx` 按代码页（默认 CP1252，GBK 做字节对最佳还原）的转义；
/// - 通过 `\stylesheet` 中的样式名（Heading / Überschrift / 标题 / Titre / Título /
///   Titolo / Title / Subtitle 等，可带数字层级）识别标题并切分章节；
/// - 段落 `\par` / `\pard`、对齐 `\qc` 等。
///
/// 仅依赖项目已有的 `charset`（GBK 解码），不引入新依赖。
Future<File> convertRtfToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  final bytes = file.readAsBytesSync();
  // RTF 主体是 ASCII 控制字 + 高位字节以 \'xx 转义；latin1 保真读取以便后续按代码页还原。
  final src = latin1.decode(bytes);

  final chapters = _parseRtf(src);

  AnxLog.info('Convert: RTF 转换完成，文件名=$filename，章节数=${chapters.length}');
  return buildEpubFromHtml(
    title: filename,
    author: 'Unknown',
    chapters: chapters.toHtmlChapters(filename),
    tempDir: tempDir,
  );
}

class _RtfFmt {
  bool bold = false;
  bool italic = false;
  bool underline = false;
  void copyFrom(_RtfFmt o) {
    bold = o.bold;
    italic = o.italic;
    underline = o.underline;
  }
}

List<ChapterDraft> _parseRtf(String src) {
  final chapters = <ChapterDraft>[];
  var current = ChapterDraft(level: 1);
  var currentHasContent = false;

  int depth = 0;
  int? skipDepth; // 处于 \*\... 被忽略的目的地（如 \*\generator）时记录进入时的深度
  bool inBody = false;
  int ansicpg = 1252;

  // 样式表：样式序号 -> 名称（用于识别标题）
  final styleNames = <int, String>{};
  bool inStylesheet = false;
  int? stylesheetDepth;
  int? pendingStyleIndex;
  var styleNameBuffer = '';

  // 当前段落累积
  final fmtStack = <_RtfFmt>[];
  var fmt = _RtfFmt();
  var runText = '';
  final paraHtml = StringBuffer();
  var paraAlign = 'left';
  int? paraHeadingLevel;
  int? gbkLead;

  int i = 0;
  final n = src.length;

  String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&[a-zA-Z]+;', ' ').trim();

  int? _headingLevelFromStyle(int index) {
    final name = styleNames[index];
    if (name == null) return null;
    final m = RegExp(
            r'(?:Heading|Überschrift|标题|Titre|Título|Titolo|Title|Subtitle|'
            r'Kopfzeile|Untertitel|En-tête|Заголовок)\s*(\d)?')
        .firstMatch(name);
    if (m == null) return null;
    if (m.group(1) != null) return int.tryParse(m.group(1)!);
    // 无数字的通用标题样式：副标题降一级，其余视为 1 级
    if (RegExp(r'Subtitle|Untertitel|Sous-titre|Sottotitolo',
            caseSensitive: false)
        .hasMatch(name)) {
      return 2;
    }
    return 1;
  }

  void appendText(String s) {
    if (inStylesheet && pendingStyleIndex != null && s == ';') {
      styleNames[pendingStyleIndex!] = styleNameBuffer.trim();
      pendingStyleIndex = null;
      styleNameBuffer = '';
      return;
    }
    if (inStylesheet && pendingStyleIndex != null) {
      styleNameBuffer += s;
    } else if (inBody) {
      runText += s;
    }
    // 其余情况（头部组 / 被忽略的目的地）丢弃
  }

  void flushRun() {
    if (runText.isEmpty) return;
    var w = _escapeHtml(runText);
    if (fmt.underline) w = '<u>$w</u>';
    if (fmt.italic) w = '<em>$w</em>';
    if (fmt.bold) w = '<strong>$w</strong>';
    paraHtml.write(w);
    runText = '';
  }

  void flushParagraph() {
    flushRun();
    final html = paraHtml.toString().trim();
    paraHtml.clear();
    if (!inBody) {
      paraHeadingLevel = null;
      return;
    }
    if (paraHeadingLevel != null) {
      final text = _stripTags(html);
      if (currentHasContent || current.title.isNotEmpty) chapters.add(current);
      // RTF 的标题是通过样式识别的，正文里没有 <hN> 标签，这里补上以便正常渲染。
      final wrapped = '<h$paraHeadingLevel>$html</h$paraHeadingLevel>';
      current = ChapterDraft(title: text, level: paraHeadingLevel!, html: wrapped);
      currentHasContent = false;
    } else if (html.isNotEmpty) {
      final aligned = paraAlign == 'left'
          ? '<p>$html</p>'
          : '<p style="text-align:$paraAlign">$html</p>';
      current.html += (current.html.isEmpty ? '' : '\n') + aligned;
      currentHasContent = true;
    }
    paraHeadingLevel = null;
  }

  void appendDecodedByte(int b) {
    if (b < 0x80) {
      appendText(String.fromCharCode(b));
      return;
    }
    if (ansicpg == 936) {
      // GBK：连续两个 \'xx 组成一个汉字
      if (gbkLead != null) {
        try {
          appendText(gbk.decode([gbkLead!, b]));
        } catch (_) {
          appendText(String.fromCharCode(b));
        }
        gbkLead = null;
      } else if (b >= 0x81 && b <= 0xFE) {
        gbkLead = b;
      } else {
        appendText(String.fromCharCode(b));
      }
      return;
    }
    appendText(_cp1252(b));
  }

  void handleWord(String word, int? param) {
    switch (word) {
      case 'par':
        if (!inBody) inBody = true;
        flushRun();
        flushParagraph();
        break;
      case 'pard':
        flushRun();
        flushParagraph();
        inBody = true;
        paraAlign = 'left';
        paraHeadingLevel = null;
        break;
      case 'b':
        flushRun();
        fmt.bold = param == null || param != 0;
        break;
      case 'i':
        flushRun();
        fmt.italic = param == null || param != 0;
        break;
      case 'ul':
        flushRun();
        fmt.underline = param == null || param != 0;
        break;
      case 'ulnone':
        flushRun();
        fmt.underline = false;
        break;
      case 'ql':
        paraAlign = 'left';
        break;
      case 'qc':
        paraAlign = 'center';
        break;
      case 'qr':
        paraAlign = 'right';
        break;
      case 'qj':
        paraAlign = 'justify';
        break;
      case 's':
        if (param != null) {
          if (inStylesheet) {
            pendingStyleIndex = param;
          } else {
            paraHeadingLevel = _headingLevelFromStyle(param);
          }
        }
        break;
      case 'ansicpg':
        if (param != null) ansicpg = param;
        break;
      case 'stylesheet':
        inStylesheet = true;
        stylesheetDepth = depth;
        break;
      case 'tab':
        runText += '    ';
        break;
      case 'line':
        flushRun();
        paraHtml.write('<br/>');
        break;
      case 'bullet':
        runText += '•';
        break;
      case 'ldblquote':
      case 'rdblquote':
        runText += '"';
        break;
      case 'lquote':
      case 'rquote':
        runText += "'";
        break;
      case 'endash':
        runText += '–';
        break;
      case 'emdash':
        runText += '—';
        break;
      case 'u':
        if (param != null) {
          final code = param < 0 ? param + 65536 : param;
          runText += String.fromCharCode(code);
          // 跳过紧随其后的 ANSI 回退字节（\'xx 序列）
          while (i < n && src[i] == '\\' && i + 1 < n && src[i + 1] == "'") {
            i += 3;
          }
        }
        break;
      default:
        break;
    }
  }

  void handleSymbol(String sym) {
    switch (sym) {
      case "'":
        if (i + 1 < n) {
          final hex = src.substring(i, i + 2);
          i += 2;
          final byte = int.tryParse(hex, radix: 16);
          if (byte != null) appendDecodedByte(byte);
        }
        break;
      case '\\':
        runText += '\\';
        break;
      case '{':
        runText += '{';
        break;
      case '}':
        runText += '}';
        break;
      case '~':
        runText += ' ';
        break;
      case '_':
        runText += ' ';
        break;
      case ';':
        appendText(';');
        break;
      default:
        // 其余控制符号（如 \- 可选连字符、\; 等）忽略
        break;
    }
  }

  while (i < n) {
    final ch = src[i];
    if (ch == '{') {
      depth++;
      fmtStack.add(_RtfFmt()..copyFrom(fmt));
      i++;
      continue;
    }
    if (ch == '}') {
      if (fmtStack.isNotEmpty) fmt = fmtStack.removeLast();
      depth--;
      if (skipDepth != null && depth < skipDepth) skipDepth = null;
      if (stylesheetDepth != null && depth < stylesheetDepth!) {
        inStylesheet = false;
        stylesheetDepth = null;
      }
      if (inStylesheet && pendingStyleIndex != null) {
        styleNames[pendingStyleIndex!] = styleNameBuffer.trim();
        pendingStyleIndex = null;
        styleNameBuffer = '';
      }
      i++;
      continue;
    }
    if (ch == '\\') {
      if (i + 1 >= n) break;
      final c2 = src[i + 1];
      i += 2;
      if (c2 == '*') {
        if (skipDepth == null) skipDepth = depth;
        continue;
      }
      if (skipDepth != null) {
        // 跳过该控制字/符号的剩余部分（花括号已在上面单独处理）
        if (RegExp(r'[a-zA-Z]').hasMatch(c2)) {
          while (i < n && RegExp(r'[a-zA-Z]').hasMatch(src[i])) i++;
          if (i < n &&
              (src[i] == '-' || RegExp(r'[0-9]').hasMatch(src[i]))) {
            if (src[i] == '-') i++;
            while (i < n && RegExp(r'[0-9]').hasMatch(src[i])) i++;
          }
          if (i < n && src[i] == ' ') i++;
        }
        continue;
      }
      if (RegExp(r'[a-zA-Z]').hasMatch(c2)) {
        var j = i;
        while (j < n && RegExp(r'[a-zA-Z]').hasMatch(src[j])) j++;
        // i 已经越过反斜杠与首字母 c2，故词名 = c2 + 余下字母
        final word = c2 + src.substring(i, j);
        int? param;
        if (j < n &&
            (src[j] == '-' || RegExp(r'[0-9]').hasMatch(src[j]))) {
          var k = j;
          if (src[k] == '-') k++;
          while (k < n && RegExp(r'[0-9]').hasMatch(src[k])) k++;
          param = int.tryParse(src.substring(j, k));
          j = k;
        }
        if (j < n && src[j] == ' ') j++;
        i = j;
        handleWord(word, param);
        continue;
      } else {
        handleSymbol(c2);
        continue;
      }
    }
    // 普通文本
    appendText(ch);
    i++;
  }

  flushRun();
  flushParagraph();
  if (current.html.trim().isNotEmpty ||
      current.title.isNotEmpty ||
      chapters.isEmpty) {
    chapters.add(current);
  }
  return chapters;
}

String _escapeHtml(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// CP1252 中 0x80–0x9F 区与 Latin-1 不同，做最小映射；其余直接按码点。
String _cp1252(int b) {
  const map = {
    0x80: '€',
    0x82: '‚',
    0x83: 'ƒ',
    0x84: '„',
    0x85: '…',
    0x86: '†',
    0x87: '‡',
    0x88: 'ˆ',
    0x89: '‰',
    0x8A: 'Š',
    0x8B: '‹',
    0x8C: 'Œ',
    0x8E: 'Ž',
    0x91: '‘',
    0x92: '’',
    0x93: '“',
    0x94: '”',
    0x95: '•',
    0x96: '–',
    0x97: '—',
    0x98: '˜',
    0x99: '™',
    0x9A: 'š',
    0x9B: '›',
    0x9C: 'œ',
    0x9E: 'ž',
    0x9F: 'Ÿ',
  };
  return map[b] ?? String.fromCharCode(b);
}
