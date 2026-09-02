/// 把 HTML 片段规范化为可安全写入 EPUB 的 XHTML 片段。
///
/// 导入 HTML/Markdown 等格式时，源文档里常出现 HTML 语法（未闭合的 `<img>`、
/// `&nbsp;` 这类命名实体、裸 `&`）。EPUB 章节以 `application/xhtml+xml` 解析，
/// 这些写法会直接导致解析失败、章节空白。这里统一做三件事：
///   1. void 元素强制自闭合（`<img src="a">` → `<img src="a"/>`）；
///   2. 命名实体转成数字字符引用（`&nbsp;` → `&#160;`）；
///   3. 裸 `&` 转义为 `&amp;`。
library;

/// 必须使用自闭合写法的 void 元素。
const List<String> _voidElements = [
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
];

final RegExp _voidTagPattern = RegExp(
    '<(${_voidElements.join('|')})\\b([^>]*)>',
    caseSensitive: false,
    dotAll: true);

/// 命名实体，XML 预定义的五个除外。
final RegExp _namedEntityPattern = RegExp(r'&([a-zA-Z][a-zA-Z0-9]*);');

/// XML 预定义的五个实体：XHTML 原生支持，保持原样可读性更好。
const Set<String> _xmlPredefinedEntities = {'amp', 'lt', 'gt', 'quot', 'apos'};

/// 裸 `&`（既不是命名实体也不是数字字符引用）。
final RegExp _bareAmpersandPattern =
    RegExp(r'&(?![a-zA-Z][a-zA-Z0-9]*;|#[0-9]+;|#x[0-9a-fA-F]+;)');

/// 常用 HTML 命名实体 → 码点。
const Map<String, int> _namedEntities = {
  // XML 预定义的五个：保持等价语义（转为数字引用后仍是合法的 XHTML）
  'amp': 38,
  'lt': 60,
  'gt': 62,
  'quot': 34,
  'apos': 39,
  'nbsp': 160,
  'iexcl': 161,
  'cent': 162,
  'pound': 163,
  'curren': 164,
  'yen': 165,
  'brvbar': 166,
  'sect': 167,
  'uml': 168,
  'copy': 169,
  'ordf': 170,
  'laquo': 171,
  'not': 172,
  'shy': 173,
  'reg': 174,
  'macr': 175,
  'deg': 176,
  'plusmn': 177,
  'sup2': 178,
  'sup3': 179,
  'acute': 180,
  'micro': 181,
  'para': 182,
  'middot': 183,
  'cedil': 184,
  'sup1': 185,
  'ordm': 186,
  'raquo': 187,
  'frac14': 188,
  'frac12': 189,
  'frac34': 190,
  'iquest': 191,
  'Agrave': 192,
  'Aacute': 193,
  'Acirc': 194,
  'Atilde': 195,
  'Auml': 196,
  'Aring': 197,
  'AElig': 198,
  'Ccedil': 199,
  'Egrave': 200,
  'Eacute': 201,
  'Ecirc': 202,
  'Euml': 203,
  'Igrave': 204,
  'Iacute': 205,
  'Icirc': 206,
  'Iuml': 207,
  'ETH': 208,
  'Ntilde': 209,
  'Ograve': 210,
  'Oacute': 211,
  'Ocirc': 212,
  'Otilde': 213,
  'Ouml': 214,
  'times': 215,
  'Oslash': 216,
  'Ugrave': 217,
  'Uacute': 218,
  'Ucirc': 219,
  'Uuml': 220,
  'Yacute': 221,
  'THORN': 222,
  'szlig': 223,
  'agrave': 224,
  'aacute': 225,
  'acirc': 226,
  'atilde': 227,
  'auml': 228,
  'aring': 229,
  'aelig': 230,
  'ccedil': 231,
  'egrave': 232,
  'eacute': 233,
  'ecirc': 234,
  'euml': 235,
  'igrave': 236,
  'iacute': 237,
  'icirc': 238,
  'iuml': 239,
  'eth': 240,
  'ntilde': 241,
  'ograve': 242,
  'oacute': 243,
  'ocirc': 244,
  'otilde': 245,
  'ouml': 246,
  'divide': 247,
  'oslash': 248,
  'ugrave': 249,
  'uacute': 250,
  'ucirc': 251,
  'uuml': 252,
  'yacute': 253,
  'thorn': 254,
  'yuml': 255,
  'hellip': 8230,
  'prime': 8242,
  'Prime': 8243,
  'oline': 8254,
  'frasl': 8260,
  'weierp': 8472,
  'image': 8465,
  'real': 8476,
  'trade': 8482,
  'alefsym': 8501,
  'larr': 8592,
  'uarr': 8593,
  'rarr': 8594,
  'darr': 8595,
  'harr': 8596,
  'lArr': 8656,
  'uArr': 8657,
  'rArr': 8658,
  'dArr': 8659,
  'hArr': 8660,
  'forall': 8704,
  'part': 8706,
  'exist': 8707,
  'empty': 8709,
  'nabla': 8711,
  'isin': 8712,
  'notin': 8713,
  'ni': 8715,
  'prod': 8719,
  'sum': 8721,
  'minus': 8722,
  'lowast': 8727,
  'radic': 8730,
  'prop': 8733,
  'infin': 8734,
  'ang': 8736,
  'and': 8743,
  'or': 8744,
  'cap': 8745,
  'cup': 8746,
  'int': 8747,
  'there4': 8756,
  'sim': 8764,
  'cong': 8773,
  'asymp': 8776,
  'ne': 8800,
  'equiv': 8801,
  'le': 8804,
  'ge': 8805,
  'sub': 8834,
  'sup': 8835,
  'nsub': 8836,
  'sube': 8838,
  'supe': 8839,
  'oplus': 8853,
  'otimes': 8855,
  'perp': 8869,
  'sdot': 8901,
  'lceil': 8968,
  'rceil': 8969,
  'lfloor': 8970,
  'rfloor': 8971,
  'lang': 9001,
  'rang': 9002,
  'loz': 9674,
  'spades': 9824,
  'clubs': 9827,
  'hearts': 9829,
  'diams': 9830,
  // HTML5 常用
  'lsquo': 8216,
  'rsquo': 8217,
  'sbquo': 8218,
  'ldquo': 8220,
  'rdquo': 8221,
  'bdquo': 8222,
  'dagger': 8224,
  'Dagger': 8225,
  'permil': 8240,
  'lsaquo': 8249,
  'rsaquo': 8250,
  'euro': 8364,
  'ndash': 8211,
  'mdash': 8212,
  'bull': 8226,
  'emsp': 8195,
  'ensp': 8194,
  'thinsp': 8201,
  'zwnj': 8204,
  'zwj': 8205,
  'lrm': 8206,
  'rlm': 8207,
};

/// 把 HTML 片段规范化为合法 XHTML 片段。
String normalizeXhtmlFragment(String html) {
  if (html.isEmpty) return html;
  var s = html;

  // 1. void 元素自闭合
  s = s.replaceAllMapped(_voidTagPattern, (m) {
    final attrs = m.group(2) ?? '';
    if (attrs.trimRight().endsWith('/')) return m.group(0)!;
    return '<${m.group(1)}$attrs/>';
  });

  // 2. 命名实体 → 数字字符引用（XML 预定义的五个保持原样）
  s = s.replaceAllMapped(_namedEntityPattern, (m) {
    final name = m.group(1)!;
    if (_xmlPredefinedEntities.contains(name)) return m.group(0)!;
    final code = _namedEntities[name];
    if (code == null) {
      // 未知实体：转成字面文本，避免 XHTML 解析失败
      return '&amp;$name;';
    }
    return '&#$code;';
  });

  // 3. 裸 & 转义
  s = s.replaceAll(_bareAmpersandPattern, '&amp;');

  return s;
}
