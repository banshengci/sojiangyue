import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/service/md5_service.dart';

/// `MD5Service.calculateFileMd5` 的回归测试。
///
/// 原实现是 `file.readAsBytes()` → `md5.convert(bytes)`：
///   1. 整个文件读进内存（CBZ/CBR 漫画包常见上百 MB，会顶爆内存）；
///      crypto 包对大文件明确要求用 chunked 而不是 `convert`；
///   2. 全程在主 isolate 上同步执行，界面（包括导入时那个
///      「正在计算 MD5」进度框）完全卡死。
///
/// 现实现改为「1 MiB 分块 + 后台 isolate」。本测试锁住三件事：
///   1. 结果正确性：与整读 `md5.convert` 逐字节一致（覆盖空文件、
///      恰好 1 MiB、略超/略低于块的边界——分块实现最容易在这些点出错）；
///   2. 不阻塞：算哈希期间主 isolate 的事件循环仍在走；
///   3. 文件不存在时返回 null。
void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('md5_service_test');
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 造一个有确定内容的文件，返回路径
  String makeFile(String name, Uint8List bytes) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  Uint8List pseudoRandom(int length, int seed) {
    final rnd = Random(seed);
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = rnd.nextInt(256);
    }
    return out;
  }

  group('结果正确性（与整读 md5.convert 一致）', () {
    // 分块实现最容易在块边界出错，这里刻意覆盖边界值
    final cases = <String, Uint8List>{
      'empty.bin': Uint8List(0),
      'tiny.bin': Uint8List.fromList([1, 2, 3]),
      'exact_1mib.bin': pseudoRandom(1 << 20, 1),
      'just_over_1mib.bin': pseudoRandom((1 << 20) + 1, 2),
      'just_under_2mib.bin': pseudoRandom((2 << 20) - 1, 3),
      'exact_3mib.bin': pseudoRandom(3 << 20, 4),
      'one_byte.bin': Uint8List.fromList([0xFF]),
    };

    cases.forEach((name, bytes) {
      test('$name（${bytes.length} 字节）与整读结果一致', () async {
        final path = makeFile(name, bytes);
        final expected = md5.convert(bytes).toString();

        final actual = await MD5Service.calculateFileMd5(path);

        expect(actual, expected);
      });
    });

    test('已知内容的 MD5 与标准值一致（防止实现整体走偏）', () async {
      // md5("abc") = 900150983cd24fb0d6963f7d28e17f72
      final path = makeFile('abc.bin', Uint8List.fromList('abc'.codeUnits));
      expect(await MD5Service.calculateFileMd5(path),
          '900150983cd24fb0d6963f7d28e17f72');
      // 空文件的标准值
      final emptyPath = makeFile('std_empty.bin', Uint8List(0));
      expect(await MD5Service.calculateFileMd5(emptyPath),
          'd41d8cd98f00b204e9800998ecf8427e');
    });
  });

  group('健壮性', () {
    test('文件不存在时返回 null 而不是抛异常', () async {
      expect(await MD5Service.calculateFileMd5('${tmp.path}/不存在.bin'), isNull);
    });
  });

  group('不阻塞主 isolate', () {
    test('计算较大文件的 MD5 期间，事件循环仍在运转', () async {
      // 4 MiB：足够让同步实现在多数机器上卡住一段时间，
      // 又不至于让测试太慢
      final path = makeFile('tick_probe.bin', pseudoRandom(4 << 20, 9));

      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );

      try {
        final digest = await MD5Service.calculateFileMd5(path);
        expect(digest, isNotNull);
      } finally {
        timer.cancel();
      }

      // 旧实现（主 isolate 同步整读）在同样的文件上实测期间 tick 为 0。
      // 这里不断言具体次数（机器性能差异大），只要求事件循环确实走起来了。
      expect(ticks, greaterThan(0),
          reason: '期间事件循环一次都没走，说明 MD5 又回到主 isolate 上同步执行了');
    });
  });
}
