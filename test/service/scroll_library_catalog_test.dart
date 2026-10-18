import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/service/enhancement_pack/scroll_library.dart';

/// 书卷库目录解析。
///
/// 目录是**第三方维护的 JSON**，所以解析必须容错：
/// 外层可能是裸数组、`items`、`packs`、`scrolls`，字段可能是驼峰或蛇形。
/// 但有一条不能容错：**缺 sha256 的条目必须丢弃**——
/// 目录里混进一条没有校验和的记录，就等于给了一个绕过验签的入口。
void main() {
  String entry({
    String id = 'honglou',
    String name = '红楼人物谱',
    String url = 'https://example.com/honglou.sjpack.zip',
    String sha = 'abc123',
  }) =>
      '{"id":"$id","name":"$name","downloadUrl":"$url","sha256":"$sha",'
      '"description":"整理好的人物与关系","author":"someone","bookTitle":"红楼梦"}';

  group('外层结构容错', () {
    test('裸数组', () {
      final list = parseScrollCatalog('[${entry()}]');
      expect(list.length, 1);
      expect(list.first.name, '红楼人物谱');
    });

    test('{items: [...]}', () {
      expect(parseScrollCatalog('{"items":[${entry()}]}').length, 1);
    });

    test('{packs: [...]} 与 {scrolls: [...]}', () {
      expect(parseScrollCatalog('{"packs":[${entry()}]}').length, 1);
      expect(parseScrollCatalog('{"scrolls":[${entry()}]}').length, 1);
    });

    test('非法 JSON / 空串返回空表而不是抛异常', () {
      expect(parseScrollCatalog(''), isEmpty);
      expect(parseScrollCatalog('not json'), isEmpty);
      expect(parseScrollCatalog('{"items": "oops"}'), isEmpty);
    });
  });

  group('字段容错', () {
    test('蛇形字段名也认', () {
      const raw = '[{"pack_id":"x","title":"某书卷","download_url":"https://a/b.zip",'
          '"checksum":"DEADBE"}]';
      final list = parseScrollCatalog(raw);
      expect(list.length, 1);
      expect(list.first.id, 'x');
      expect(list.first.name, '某书卷');
      expect(list.first.sha256, 'deadbe', reason: '校验和统一转小写');
    });

    test('可选字段缺失时不崩', () {
      const raw = '[{"id":"a","name":"n","downloadUrl":"https://x/y.zip","sha256":"s"}]';
      final list = parseScrollCatalog(raw);
      expect(list.first.bookTitle, isNull);
      expect(list.first.description, '');
      expect(list.first.author, '');
      expect(list.first.bytes, isNull);
    });
  });

  group('安全底线', () {
    test('缺 sha256 的条目被丢弃（不能绕过验签）', () {
      const raw = '[{"id":"a","name":"n","downloadUrl":"https://x/y.zip"}]';
      expect(parseScrollCatalog(raw), isEmpty);
    });

    test('缺下载地址的条目被丢弃', () {
      const raw = '[{"id":"a","name":"n","sha256":"s"}]';
      expect(parseScrollCatalog(raw), isEmpty);
    });

    test('坏条目不影响好条目', () {
      const bad = '{"id":"bad","name":"缺校验和","downloadUrl":"https://x/y.zip"}';
      final list = parseScrollCatalog('[$bad,${entry()}]');
      expect(list.length, 1);
      expect(list.first.id, 'honglou');
    });
  });
}
