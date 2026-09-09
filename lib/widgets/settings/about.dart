import 'dart:async';

import 'package:songjiang_reader/config/remote_config.dart';
import 'package:songjiang_reader/config/developer_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:songjiang_reader/utils/env_var.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/settings/link_icon.dart';
import 'package:songjiang_reader/utils/check_update.dart';
import 'package:songjiang_reader/widgets/settings/show_donate_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:url_launcher/url_launcher.dart';

class About extends StatefulWidget {
  const About({
    super.key,
    this.leadingColor = false,
  });
  final bool leadingColor;

  @override
  State<About> createState() => _AboutState();
}

class _AboutState extends State<About> {
  String version = '';

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {}

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(L10n.of(context).appAbout),
      leading: Icon(Icons.info_outline,
          color: widget.leadingColor
              ? Theme.of(context).colorScheme.primary
              : null),
      onTap: () => openAboutDialog(),
    );
  }
}

const int _developerUnlockTapThreshold = 7;
int _developerUnlockTapCount = 0;
Timer? _developerUnlockResetTimer;

void _handleDeveloperUnlockTap(BuildContext context) {
  _developerUnlockTapCount++;
  _developerUnlockResetTimer?.cancel();
  _developerUnlockResetTimer =
      Timer(const Duration(seconds: 2), () => _developerUnlockTapCount = 0);

  final alreadyEnabled = DeveloperPrefs.developerOptionsEnabled;
  if (_developerUnlockTapCount < _developerUnlockTapThreshold) {
    return;
  }

  _developerUnlockTapCount = 0;
  if (!alreadyEnabled) {
    DeveloperPrefs.developerOptionsEnabled = true;
    SjToast.show('Developer options enabled');
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
  Future.microtask(_openDeveloperOptionsPage);
}

void _openDeveloperOptionsPage() {
  final BuildContext? navContext = navigatorKey.currentContext;
  if (navContext == null) return;
  Navigator.of(navContext).push(
    CupertinoPageRoute(
      fullscreenDialog: false,
      builder: (context) => const DeveloperOptionsPage(),
    ),
  );
}

/// 关于对话框的品牌头部：松绿渐变 + Logo + 中英文名 + 版本 + 标语 + 水印
Widget _buildAboutHeader(BuildContext context, String version) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      gradient: isDark
          ? SongJiangColors.bambooGradientDark
          : SongJiangColors.bambooGradient,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: (isDark ? Colors.black : SongJiangColors.bambooDeep)
              .withAlpha(isDark ? 80 : 45),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          // 水印「阅」
          Positioned(
            right: -14,
            bottom: -32,
            child: Text(
              '阅',
              style: TextStyle(
                fontSize: 110,
                fontWeight: FontWeight.w700,
                color: Colors.white.withAlpha(isDark ? 16 : 26),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withAlpha(26)
                        : Colors.white.withAlpha(220),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withAlpha(isDark ? 40 : 0),
                      width: 1,
                    ),
                  ),
                  child: Image.asset(
                    SongJiangBrand.logoAsset,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  SongJiangBrand.name,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  SongJiangBrand.nameEn,
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 1.4,
                    color: Colors.white.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v$version${kDebugMode ? ' · debug' : ''}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withAlpha(225),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  SongJiangBrand.tagline,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(205),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> openAboutDialog() async {
  final pubspecContent = await rootBundle.loadString('pubspec.yaml');
  final pubspec = Pubspec.parse(pubspecContent);
  final version = pubspec.version.toString();

  showDialog(
    context: navigatorKey.currentContext!,
    builder: (BuildContext context) {
      return AlertDialog(
          content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
          minWidth: 300,
        ),
        child: SingleChildScrollView(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAboutHeader(context, version),
                const SizedBox(height: 4),
                const Divider(),
                ListTile(
                  title: Text(L10n.of(context).appVersion),
                  subtitle: Text(version + (kDebugMode ? ' (debug)' : '')),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: version));
                    SjToast.show(L10n.of(context).notesPageCopied);
                    _handleDeveloperUnlockTap(context);
                  },
                ),
                if (EnvVar.enableCheckUpdate && RemoteConfig.enableUpdateCheck)
                  ListTile(
                      title: Text(L10n.of(context).aboutCheckForUpdates),
                      onTap: () => checkUpdate(true)),
                if (EnvVar.enableDonation)
                  ListTile(
                    title: Text(L10n.of(context).appDonate),
                    onTap: () {
                      showDonateDialog(context);
                    },
                  ),
                ListTile(
                  title: Text(L10n.of(context).appLicense),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: '松江阅',
                      applicationVersion: version,
                    );
                  },
                ),
                if (RemoteConfig.enableContributorsUrl)
                  ListTile(
                    title: Text(L10n.of(context).appAuthor),
                    onTap: () {
                      launchUrl(
                        Uri.parse(RemoteConfig.contributorsUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                if (RemoteConfig.enablePrivacyLink)
                  ListTile(
                    title: Text(L10n.of(context).aboutPrivacyPolicy),
                    onTap: () async {
                      launchUrl(
                        Uri.parse(RemoteConfig.privacyUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                if (RemoteConfig.enableTermsLink)
                  ListTile(
                    title: Text(L10n.of(context).aboutTermsOfUse),
                    onTap: () async {
                      launchUrl(
                        Uri.parse(RemoteConfig.termsUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                if (RemoteConfig.enableDocsLink)
                  ListTile(
                    title: Text(L10n.of(context).aboutHelp),
                    onTap: () async {
                      launchUrl(
                        Uri.parse(RemoteConfig.docsUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                const Divider(),
                // 备案号由 BEIAN_TEXT 注入；上游那份是别人的主体信息，不能沿用
                if (EnvVar.showBeian && RemoteConfig.enableBeian) ...[
                  GestureDetector(
                    onTap: () {
                      launchUrl(Uri.parse('https://beian.miit.gov.cn/'),
                          mode: LaunchMode.externalApplication);
                    },
                    child: Text(RemoteConfig.beianText),
                  ),
                  const Divider(),
                ],
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (RemoteConfig.projectHome.isNotEmpty)
                        linkIcon(
                            icon: Icon(
                              IonIcons.earth,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            url: RemoteConfig.projectHome,
                            mode: LaunchMode.externalApplication),
                      if (RemoteConfig.projectHome.isNotEmpty)
                        linkIcon(
                            icon: Icon(
                              IonIcons.logo_github,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            url: RemoteConfig.projectHome,
                            mode: LaunchMode.externalApplication),
                      if (RemoteConfig.enableTelegramLink)
                        linkIcon(
                            icon: Icon(
                              Icons.telegram,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            url: RemoteConfig.telegramUrl,
                            mode: LaunchMode.externalApplication),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
    },
  );
}
