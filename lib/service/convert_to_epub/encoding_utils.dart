import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';

import 'package:songjiang_reader/utils/log/common.dart';

/// 探测并读取文本文件，兼容 UTF-8 / GBK / Latin1 / UTF-16 / UTF-32 等常见编码。
///
/// 从 [convert_from_txt.dart] 抽出，避免文档转换器（HTML/Markdown）反向依赖
/// 仅 TXT 转换才需要的 Flutter 配置链，从而可在纯 Dart 环境下单测。
String readFileWithEncoding(File file) {
  bool checkGarbled(String content) {
    final garbledPattern = RegExp(
        r'Õ|Ê|�|Ç|³|¾|Ð|Ó|Î|Á|É|�|Ã|Ä|Å|Æ|Ë|Ì|Í|Ï|Ò|Ó|Ô|Õ|Ö|Ù|Ú|Û|Ü|Ý|à|á|â|ã|ä|å|æ|è|é|ê|ë|ì|í|î|ï|ð|ñ|ò|ó|ô|õ|ö|ù|ú|û|ü|ý|ÿ|\x00-\x1F\x7F|｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ|€|�');
    final sampleContent =
        content.length > 500 ? content.substring(0, 500) : content;

    final matches = garbledPattern.allMatches(sampleContent);

    final garbledCount = matches.length;

    return garbledCount / sampleContent.length > 20 / 500;
  }

  final decoder = {
    'utf8': utf8.decode,
    'gbk': gbk.decode,
    'latin1': latin1.decode,
    'utf16': utf16.decode,
    'utf32': utf32.decode,
  };

  for (final entry in decoder.entries) {
    try {
      SjLog.info('Convert: Reading file with encoding: ${entry.key}');
      final content = entry.value(file.readAsBytesSync());
      if (!checkGarbled(content)) {
        return content;
      }
      SjLog.info('Convert: Detected garbled text ${entry.key}');
    } catch (e) {
      SjLog.warning(
          'Convert: Failed to read file with encoding: ${entry.key}');
    }
  }

  throw Exception('Convert: Failed to read file with any encoding');
}
