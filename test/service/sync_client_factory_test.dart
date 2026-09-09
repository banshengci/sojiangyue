import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/enums/sync_protocol.dart';
import 'package:songjiang_reader/service/sync/sync_client_factory.dart';
import 'package:songjiang_reader/service/sync/webdav_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SyncPrefs.ensureInitialized();
    SyncClientFactory.resetCurrentClient();
  });

  group('SyncClientFactory', () {
    test('availableProtocols 目前仅含 webdav', () {
      expect(SyncClientFactory.availableProtocols, [SyncProtocol.webdav]);
    });

    test('getCurrentSyncProtocol 无配置时回退 webdav', () {
      expect(SyncClientFactory.getCurrentSyncProtocol(), SyncProtocol.webdav);
    });

    test('getCurrentSyncProtocol 读取已存协议名', () {
      SyncPrefs.syncProtocol = SyncProtocol.ftp.name;
      // ftp 仍在枚举中，工厂应能解析；只是 createClient 未实现
      expect(SyncClientFactory.getCurrentSyncProtocol(), SyncProtocol.ftp);
    });

    test('getCurrentSyncProtocol 未知名回退 webdav', () {
      SyncPrefs.syncProtocol = 'not-a-protocol';
      expect(SyncClientFactory.getCurrentSyncProtocol(), SyncProtocol.webdav);
    });

    test('createClient(webdav) 返回已配置的 WebdavClient', () {
      final client = SyncClientFactory.createClient(
        SyncProtocol.webdav,
        {'url': 'https://dav.example/remote.php', 'username': 'u', 'password': 'p'},
      );
      expect(client, isA<WebdavClient>());
      expect(client.isConfigured, isTrue);
    });

    test('createClient(webdav) 缺 url/username/password 时未配置', () {
      final client = SyncClientFactory.createClient(
        SyncProtocol.webdav,
        const {},
      );
      expect(client.isConfigured, isFalse);
    });

    test('createClient 对未实现协议抛 UnimplementedError', () {
      expect(
        () => SyncClientFactory.createClient(SyncProtocol.ftp, const {}),
        throwsA(isA<UnimplementedError>()),
      );
      expect(
        () => SyncClientFactory.createClient(SyncProtocol.s3, const {}),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('saveConfigForProtocol / getConfigForProtocol 往返', () {
      SyncClientFactory.saveConfigForProtocol(
        SyncProtocol.webdav,
        {'url': 'https://x', 'username': 'a', 'password': 'b'},
      );
      final config = SyncClientFactory.getConfigForProtocol(SyncProtocol.webdav);
      expect(config['url'], 'https://x');
      expect(config['username'], 'a');
    });

    test('initializeCurrentClient：有配置时创建客户端', () {
      SyncClientFactory.saveConfigForProtocol(
        SyncProtocol.webdav,
        {'url': 'https://dav.example', 'username': 'u', 'password': 'p'},
      );
      SyncClientFactory.initializeCurrentClient();
      expect(SyncClientFactory.currentClient, isA<WebdavClient>());
      expect(SyncClientFactory.isCurrentClientReady, isTrue);
    });

    test('initializeCurrentClient：无配置时不创建', () {
      SyncClientFactory.initializeCurrentClient();
      expect(SyncClientFactory.currentClient, isNull);
      expect(SyncClientFactory.isCurrentClientReady, isFalse);
    });

    test('switchProtocol 写入偏好并重建客户端', () {
      SyncClientFactory.saveConfigForProtocol(
        SyncProtocol.webdav,
        {'url': 'https://dav.example', 'username': 'u', 'password': 'p'},
      );
      SyncClientFactory.switchProtocol(SyncProtocol.webdav);
      expect(SyncPrefs.syncProtocol, SyncProtocol.webdav.name);
      expect(SyncClientFactory.currentClient, isNotNull);
    });

    test('resetCurrentClient 清空当前客户端', () {
      SyncClientFactory.saveConfigForProtocol(
        SyncProtocol.webdav,
        {'url': 'https://dav.example', 'username': 'u', 'password': 'p'},
      );
      SyncClientFactory.initializeCurrentClient();
      expect(SyncClientFactory.currentClient, isNotNull);
      SyncClientFactory.resetCurrentClient();
      expect(SyncClientFactory.currentClient, isNull);
    });
  });
}
