import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/models/opds_catalog.dart';
import 'package:songjiang_reader/service/opds/opds_service.dart';

void main() {
  group('OpdsCatalog', () {
    test('json 往返', () {
      final c = OpdsCatalog(
        id: '1',
        name: 'Calibre',
        url: 'https://example.com/opds',
        username: 'u',
        password: 'p',
      );
      final restored = OpdsCatalog.fromJson(c.toJson());
      expect(restored.id, c.id);
      expect(restored.name, c.name);
      expect(restored.url, c.url);
      expect(restored.username, 'u');
      expect(restored.hasAuth, isTrue);
    });
  });

  group('parseFeedXml', () {
    const sample = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>Root Catalog</title>
  <link rel="self" href="/opds" type="application/atom+xml"/>
  <entry>
    <title>Fiction</title>
    <link rel="subsection" href="/opds/fiction" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  </entry>
  <entry>
    <title>Great Book</title>
    <author><name>Jane Doe</name></author>
    <summary>A fine novel.</summary>
    <link rel="http://opds-spec.org/image" href="/covers/1.jpg" type="image/jpeg"/>
    <link rel="http://opds-spec.org/acquisition" href="/download/1.epub" type="application/epub+zip" length="12345"/>
  </entry>
</feed>
''';

    test('解析标题、导航与 acquisition', () {
      final feed = parseFeedXml(sample, baseUrl: 'https://example.com/opds');
      expect(feed.title, 'Root Catalog');
      expect(feed.entries.length, 2);

      final nav = feed.entries.first;
      expect(nav.isNavigation, isTrue);
      expect(nav.subsectionUrl, 'https://example.com/opds/fiction');

      final book = feed.entries.last;
      expect(book.isBook, isTrue);
      expect(book.title, 'Great Book');
      expect(book.author, 'Jane Doe');
      expect(book.coverUrl, 'https://example.com/covers/1.jpg');
      expect(book.acquisitions.single.href, 'https://example.com/download/1.epub');
      expect(book.acquisitions.single.fileExtension, 'epub');
      expect(book.acquisitions.single.length, 12345);
    });

    test('相对链接按 baseUrl 解析', () {
      final feed = parseFeedXml(sample, baseUrl: 'https://cdn.example.com/opds/root');
      expect(
        feed.entries.first.subsectionUrl,
        'https://cdn.example.com/opds/fiction',
      );
    });

    test('fileExtension 从 type 推断 pdf', () {
      final link = OpdsAcquisitionLink(
        href: 'https://x/a',
        type: 'application/pdf',
      );
      expect(link.fileExtension, 'pdf');
    });
  });
}
