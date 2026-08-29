import 'package:songjiang_reader/config/remote_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// RemoteConfig 的所有端点都由 `--dart-define` 在**编译期**注入，
/// 单元测试里无法动态改变。因此这里不断言具体 URL，只断言
/// 各 getter 之间的**一致性与派生规则**——这些逻辑与注入值无关。
void main() {
  group('RemoteConfig 派生逻辑', () {
    test('enableUpdateCheck 与 updateApiUrl 保持一致', () {
      expect(RemoteConfig.enableUpdateCheck, RemoteConfig.updateApiUrl != null);
    });

    test('updateApiUrl 非空时必须是合法绝对 URL', () {
      final api = RemoteConfig.updateApiUrl;
      if (api == null) return;
      final uri = Uri.tryParse(api);
      expect(uri, isNotNull);
      expect(uri!.hasScheme, isTrue);
      expect(uri.host, isNotEmpty);
    });

    test('fontBaseUrl 若已配置则必须以 / 结尾（保证拼接文件路径正确）', () {
      final base = RemoteConfig.fontBaseUrl;
      if (base.isEmpty) return;
      expect(base.endsWith('/'), isTrue);
    });

    test('fontManifestUrl 由 fontBaseUrl 派生', () {
      final base = RemoteConfig.fontBaseUrl;
      if (base.isEmpty) return;
      expect(RemoteConfig.fontManifestUrl, '$base${"fonts-manifest.json"}');
    });

    test('未配置 PROJECT_REPO 时不应出现 GitHub 链接', () {
      if (RemoteConfig.projectRepo.isEmpty) {
        expect(RemoteConfig.projectHome, isEmpty);
        expect(RemoteConfig.contributorsUrl, isEmpty);
      } else {
        expect(RemoteConfig.projectHome, contains(RemoteConfig.projectRepo));
        expect(RemoteConfig.contributorsUrl, isNotEmpty);
      }
    });

    test('webdavHelpUrl 依赖 docsUrl，且拼接为 docs + sync/webdav', () {
      if (RemoteConfig.docsUrl.isEmpty) {
        expect(RemoteConfig.webdavHelpUrl, isEmpty);
      } else {
        expect(RemoteConfig.webdavHelpUrl, endsWith('sync/webdav'));
      }
      expect(RemoteConfig.enableDocsLink, RemoteConfig.docsUrl.isNotEmpty);
    });

    test('各 enable 开关与对应 URL 一致', () {
      expect(RemoteConfig.enablePrivacyLink, RemoteConfig.privacyUrl.isNotEmpty);
      expect(RemoteConfig.enableTermsLink, RemoteConfig.termsUrl.isNotEmpty);
      expect(RemoteConfig.enableTelegramLink, RemoteConfig.telegramUrl.isNotEmpty);
      expect(RemoteConfig.enableDonateLink, RemoteConfig.donateUrl.isNotEmpty);
      expect(RemoteConfig.enableFontMarket, RemoteConfig.fontBaseUrl.isNotEmpty);
    });
  });
}
