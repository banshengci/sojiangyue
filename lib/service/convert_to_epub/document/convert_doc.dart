import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'package:songjiang_reader/service/convert_to_epub/build_epub_from_html.dart';
import 'package:songjiang_reader/service/convert_to_epub/document/chapter_draft.dart';
import 'package:songjiang_reader/utils/log/common.dart';

/// 把老版 Word `.doc`（OLE2 复合文档二进制格式）转换为 EPUB。
///
/// 背景：`.doc` 是 Word 97–2003 的私有二进制格式（OLE2 容器 + FIB + Piece Table），
/// 目前没有可靠的纯 Dart 解析库（Aspose 是需密钥的云 API，`doc_text` 是 TS 实现）。
/// 因此在「不引入原生依赖、不依赖外部工具」的约束下，这里采用 **best-effort** 提取：
///
/// 1. 用纯 Dart 实现的 OLE2 读取器定位 `WordDocument` 流（最易错、已用合成样本验证）；
/// 2. 从流中扫描可打印正文（UTF-16LE 与 CP1252 两种编码自动判别），恢复正文文本。
///
/// 代价：会丢失原始排版/标题层级（转为纯文本段落）。需要完整保真时，建议先
/// 在 Word/WPS 中把 `.doc` 另存为 `.docx` 再导入。本实现保证**不崩溃**且能提取正文，
/// 作为对无法转 .docx 场景的兜底支持。
Future<File> convertDocToEpub(File file, {Directory? tempDir}) async {
  final filename = path.basenameWithoutExtension(file.path);
  final bytes = file.readAsBytesSync();

  if (!_Ole2.isOle2(bytes)) {
    throw Exception('Convert: 不是合法的 OLE2(.doc) 文件：$filename');
  }

  final ole = _Ole2(bytes);
  Uint8List? wd;
  try {
    wd = ole.readStream('WordDocument');
  } catch (e) {
    AnxLog.warning('Convert: 找不到 WordDocument 流，$filename: $e');
  }

  final text = wd == null ? '' : _scanDocText(wd);

  if (text.trim().isEmpty) {
    throw Exception('Convert: 未能从 .doc 提取到正文：$filename');
  }

  // 按空行切分成段落，合并进一个章节（best-effort，标题层级已不可考）。
  final paragraphs = text
      .split(RegExp(r'\n\s*\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final html = paragraphs.map((p) => '<p>${_escapeHtml(p)}</p>').join('\n');
  final chapter = ChapterDraft(title: filename, level: 1, html: html);

  AnxLog.info(
      'Convert: .doc 转换完成，文件名=$filename，段落数=${paragraphs.length}（best-effort 文本提取）');
  return buildEpubFromHtml(
    title: filename,
    author: 'Unknown',
    chapters: [chapter].toHtmlChapters(filename),
    tempDir: tempDir,
  );
}

/// 从 WordDocument 流中扫描可打印正文。
///
/// Word 把正文与二进制控制字节交错存储：Unicode 文档里文本是 UTF-16LE
/// （ASCII 字符的偶数字节为 0），ANSI 文档里是 CP1252 单字节。这里自动判别：
/// - 偶数字节多为 0 → 按 UTF-16LE 解码，保留可打印码点与换行；
/// - 否则按 CP1252 单字节扫描。
String _scanDocText(Uint8List wd) {
  if (wd.isEmpty) return '';

  int zeroCount = 0;
  for (var i = 1; i < wd.length; i += 2) {
    if (wd[i] == 0) zeroCount++;
  }
  final utf16Likely = zeroCount > wd.length >> 2;

  final chars = <int>[];
  if (utf16Likely) {
    for (var i = 0; i + 1 < wd.length; i += 2) {
      final code = wd[i] | (wd[i + 1] << 8);
      if (code == 0x0D || code == 0x0A) {
        chars.add(0x0A);
      } else if (_isPrintable(code)) {
        chars.add(code);
      }
    }
  } else {
    for (final b in wd) {
      if (b == 0x0D || b == 0x0A) {
        chars.add(0x0A);
      } else if (b >= 0x20 && b < 0x7F) {
        chars.add(b);
      } else if (b >= 0x80) {
        chars.add(_cp1252(b).codeUnitAt(0));
      }
      // 其余控制字节（0x00–0x1F 除换行外）跳过
    }
  }
  return String.fromCharCodes(chars);
}

bool _isPrintable(int code) =>
    code >= 0x20 && code != 0x7F ||
    (code >= 0xA0 && code <= 0xFFFD);

String _escapeHtml(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// CP1252 中 0x80–0x9F 区与 Latin-1 不同，做最小映射；其余按码点。
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

/// 最小可用的 OLE2（复合文档）读取器，仅用于从 `.doc` 中定位并读出指定流。
///
/// 支持：标准 512 字节扇区、FAT/DIFAT 链式索引、目录枚举、
/// 常规流与 mini 流（小于 cutoff 的小流存于 mini-stream）。
/// 校验签名，解析失败时抛出便于上层回退。
class _Ole2 {
  _Ole2(this._data) {
    if (!isOle2(_data)) throw Exception('OLE2: 签名不匹配');
    final bd = ByteData.sublistView(_data);
    final sectorShift = bd.getUint16(30, Endian.little);
    _sectorSize = 1 << sectorShift;
    final miniSectorShift = bd.getUint16(32, Endian.little);
    _miniSectorSize = 1 << miniSectorShift;
    _firstDirSector = bd.getUint32(48, Endian.little);
    _miniCutoff = bd.getUint32(56, Endian.little);
    _firstMiniFatSector = bd.getUint32(60, Endian.little);
    _firstDifatSector = bd.getUint32(68, Endian.little);

    _buildFat();
    _buildMiniFat();
    _parseDirectory();
  }

  final Uint8List _data;
  late int _sectorSize;
  late int _miniSectorSize;
  late int _firstDirSector;
  late int _miniCutoff;
  late int _firstMiniFatSector;
  late int _firstDifatSector;
  late List<int> _fatFlat; // 逻辑扇区号 -> 下一扇区号
  late List<int> _miniFatFlat; // mini 扇区号 -> 下一 mini 扇区号
  late Uint8List _miniStream;
  final Map<String, _DirEntry> _dirEntries = {};

  static bool isOle2(Uint8List data) {
    if (data.length < 8) return false;
    const sig = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    for (var i = 0; i < 8; i++) {
      if (data[i] != sig[i]) return false;
    }
    return true;
  }

  int _sectorOffset(int sector) => 512 + sector * _sectorSize;

  void _buildFat() {
    // 收集 DIFAT 中列出的全部 FAT 扇区号
    final difat = <int>[];
    final bd = ByteData.sublistView(_data);
    for (var i = 0; i < 109; i++) {
      difat.add(bd.getUint32(76 + i * 4, Endian.little));
    }
    var difatSector = _firstDifatSector;
    while (difatSector != 0xFFFFFFFE && difatSector != 0xFFFFFFFF) {
      final secOff = _sectorOffset(difatSector);
      final count = (_sectorSize ~/ 4) - 1;
      for (var i = 0; i < count; i++) {
        difat.add(bd.getUint32(secOff + i * 4, Endian.little));
      }
      difatSector = bd.getUint32(secOff + count * 4, Endian.little);
    }

    _fatFlat = <int>[];
    for (final fatSector in difat) {
      if (fatSector < 0 || fatSector >= 0xFFFFFFFC) continue;
      final off = _sectorOffset(fatSector);
      final entries = _sectorSize ~/ 4;
      for (var j = 0; j < entries; j++) {
        _fatFlat.add(bd.getUint32(off + j * 4, Endian.little));
      }
    }
  }

  void _buildMiniFat() {
    _miniFatFlat = <int>[];
    if (_firstMiniFatSector < 0 || _firstMiniFatSector >= 0xFFFFFFFC) {
      return;
    }
    final bd = ByteData.sublistView(_data);
    var ms = _firstMiniFatSector;
    while (ms != 0xFFFFFFFE && ms >= 0 && ms < _fatFlat.length) {
      final off = _sectorOffset(ms);
      final entries = _sectorSize ~/ 4;
      for (var j = 0; j < entries; j++) {
        _miniFatFlat.add(bd.getUint32(off + j * 4, Endian.little));
      }
      ms = _fatFlat[ms];
    }
  }

  void _parseDirectory() {
    final dirBytes = _readRegularStream(_firstDirSector, null);
    final bd = ByteData.sublistView(dirBytes);
    final entries = dirBytes.length ~/ 128;
    for (var e = 0; e < entries; e++) {
      final base = e * 128;
      if (base + 128 > dirBytes.length) break;
      final nameLen = bd.getUint16(base + 64, Endian.little);
      if (nameLen <= 2) continue;
      final name = _utf16le(dirBytes.sublist(base, base + nameLen - 2))
          .toLowerCase();
      final type = dirBytes[base + 66];
      final startSector = bd.getUint32(base + 116, Endian.little);
      final size = bd.getUint64(base + 120, Endian.little);
      _dirEntries[name] = _DirEntry(name, type, startSector, size);
    }

    // mini-stream 内容来自根存储（type 5）的常规流
    final root = _dirEntries['root entry'];
    _miniStream =
        root == null ? Uint8List(0) : _readRegularStream(root.startSector, root.size);
  }

  Uint8List readStream(String name) {
    final entry = _dirEntries[name.toLowerCase()];
    if (entry == null) throw Exception('OLE2: 找不到流 $name');
    if (entry.size < _miniCutoff && entry.type == 2 && _miniStream.isNotEmpty) {
      return _readMiniStream(entry.startSector, entry.size);
    }
    return _readRegularStream(entry.startSector, entry.size);
  }

  Uint8List _readRegularStream(int startSector, int? size) {
    final out = <int>[];
    var sector = startSector;
    var guard = 0;
    while (sector != 0xFFFFFFFE &&
        sector != 0xFFFFFFFF &&
        sector >= 0 &&
        sector < _fatFlat.length &&
        guard++ < 100000) {
      final off = _sectorOffset(sector);
      if (off + _sectorSize > _data.length) break;
      out.addAll(_data.sublist(off, off + _sectorSize));
      sector = _fatFlat[sector];
    }
    if (size != null && out.length > size) {
      out.length = size;
    }
    return Uint8List.fromList(out);
  }

  Uint8List _readMiniStream(int startMiniSector, int size) {
    final out = <int>[];
    var m = startMiniSector;
    var guard = 0;
    while (m != 0xFFFFFFFE && m >= 0 && m < _miniFatFlat.length && guard++ < 100000) {
      final off = m * _miniSectorSize;
      if (off + _miniSectorSize > _miniStream.length) break;
      out.addAll(_miniStream.sublist(off, off + _miniSectorSize));
      m = _miniFatFlat[m];
    }
    if (out.length > size) out.length = size;
    return Uint8List.fromList(out);
  }

  static String _utf16le(List<int> b) {
    final buf = Uint16List(b.length ~/ 2);
    for (var i = 0; i < buf.length; i++) {
      buf[i] = b[i * 2] | (b[i * 2 + 1] << 8);
    }
    return String.fromCharCodes(buf);
  }
}

class _DirEntry {
  _DirEntry(this.name, this.type, this.startSector, this.size);
  final String name;
  final int type; // 2 = stream, 5 = root storage
  final int startSector;
  final int size;
}
