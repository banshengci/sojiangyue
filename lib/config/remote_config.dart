/// 自有 / 远程服务的统一配置中心。
///
/// 所有 URL 通过 `--dart-define` 在构建时注入；未注入则相应功能默认禁用。
///
/// 示例（发布构建）:
/// ```
/// flutter build windows --release \
///   --dart-define=PROJECT_REPO=yourname/songjiang_reader \
///   --dart-define=FONT_BASE_URL=https://fonts.example.com \
///   --dart-define=PRIVACY_URL=https://example.com/privacy \
///   --dart-define=TERMS_URL=https://example.com/terms
/// ```
///
/// 完整支持的变量见 [RemoteConfig]。
library;

/// 远程 / 自有服务配置。所有 URL 通过 --dart-define 在编译时注入。
class RemoteConfig {
  const RemoteConfig._();

  // === 构建时可注入值（未注入则为空字符串） ===

  /// GitHub 仓库 "owner/repo"，用于更新检查和"项目主页/Contributors"链接。
  /// 设置后自动启用 GitHub Releases 作为默认更新源。
  static const String _projectRepo =
      String.fromEnvironment('PROJECT_REPO', defaultValue: '');

  /// 自有更新检查 API URL。留空且 [projectRepo] 也为空时，更新检查功能禁用。
  /// 响应需为 JSON: `{ "version": "v1.2.3", "body": "# Changelog..." }`。
  static const String _updateApiUrl =
      String.fromEnvironment('UPDATE_API_URL', defaultValue: '');

  /// "前往下载"按钮的目标 URL。留空时回退到 [projectRepo] 的 Releases 页面。
  static const String _updateDownloadUrl =
      String.fromEnvironment('UPDATE_DOWNLOAD_URL', defaultValue: '');

  /// 自有字体市场根 URL（最后需带 `/`）。留空则禁用字体下载页。
  /// 需托管 `fonts-manifest.json` 与字体文件。
  static const String _fontBaseUrl =
      String.fromEnvironment('FONT_BASE_URL', defaultValue: '');

  /// 自有隐私政策 URL。
  static const String _privacyUrl =
      String.fromEnvironment('PRIVACY_URL', defaultValue: '');

  /// 自有服务条款 URL。
  static const String _termsUrl =
      String.fromEnvironment('TERMS_URL', defaultValue: '');

  /// 自有文档站 URL（设置后 WebDAV 帮助链接会自动指向 `${docsUrl}/sync/webdav`）。
  static const String _docsUrl =
      String.fromEnvironment('DOCS_URL', defaultValue: '');

  /// 自有 Telegram 社群链接。
  static const String _telegramUrl =
      String.fromEnvironment('TELEGRAM_URL', defaultValue: '');

  /// 自有捐赠页 URL。
  static const String _donateUrl =
      String.fromEnvironment('DONATE_URL', defaultValue: '');

  // === 派生 getter：更新检查 ===

  /// 有效的更新检查 API URL。优先自定义，其次 GitHub Releases，未配置返回 `null`。
  static String? get updateApiUrl {
    if (_updateApiUrl.isNotEmpty) return _updateApiUrl;
    if (_projectRepo.isNotEmpty) {
      return 'https://api.github.com/repos/$_projectRepo/releases/latest';
    }
    return null;
  }

  /// 有效的更新下载页 URL。
  static String get updateDownloadUrl {
    if (_updateDownloadUrl.isNotEmpty) return _updateDownloadUrl;
    if (_projectRepo.isNotEmpty) {
      return 'https://github.com/$_projectRepo/releases/latest';
    }
    return '';
  }

  // === 派生 getter：字体市场 ===

  /// 字体市场根 URL（保证以 `/` 结尾）。
  static String get fontBaseUrl {
    if (_fontBaseUrl.isEmpty) return '';
    return _fontBaseUrl.endsWith('/') ? _fontBaseUrl : '$_fontBaseUrl/';
  }

  static String get fontManifestUrl => '${fontBaseUrl}fonts-manifest.json';

  // === 文档 / 链接 ===

  static String get privacyUrl => _privacyUrl;
  static String get termsUrl => _termsUrl;
  static String get docsUrl => _docsUrl;
  static String get telegramUrl => _telegramUrl;
  static String get donateUrl => _donateUrl;
  static String get projectRepo => _projectRepo;

  /// Contributors 链接（设置 [projectRepo] 后可用）。
  static String get contributorsUrl => _projectRepo.isNotEmpty
      ? 'https://github.com/$_projectRepo/graphs/contributors'
      : '';

  /// 项目主页（设置 [projectRepo] 后可用）。
  static String get projectHome => _projectRepo.isNotEmpty
      ? 'https://github.com/$_projectRepo'
      : '';

  /// WebDAV 同步帮助链接（设置 [docsUrl] 后可用）。
  static String get webdavHelpUrl {
    if (_docsUrl.isEmpty) return '';
    final base = _docsUrl.endsWith('/') ? _docsUrl : '$_docsUrl/';
    return '${base}sync/webdav';
  }

  // === 启用判定 ===

  static bool get enableUpdateCheck => updateApiUrl != null;
  static bool get enableFontMarket => _fontBaseUrl.isNotEmpty;
  static bool get enableTelegramLink => _telegramUrl.isNotEmpty;
  static bool get enableDonateLink => _donateUrl.isNotEmpty;
  static bool get enablePrivacyLink => _privacyUrl.isNotEmpty;
  static bool get enableTermsLink => _termsUrl.isNotEmpty;
  static bool get enableDocsLink => _docsUrl.isNotEmpty;
  static bool get enableContributorsUrl => _projectRepo.isNotEmpty;
}