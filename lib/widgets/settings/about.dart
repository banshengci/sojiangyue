import 'dart:async';

import 'package:songjiang_reader/config/remote_config.dart';
import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/page/settings_page/developer/developer_options_page.dart';
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

  final alreadyEnabled = Prefs().developerOptionsEnabled;
  if (_developerUnlockTapCount < _developerUnlockTapThreshold) {
    return;
  }

  _developerUnlockTapCount = 0;
  if (!alreadyEnabled) {
    Prefs().developerOptionsEnabled = true;
    AnxToast.show('Developer options enabled');
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 5),
                  child: Center(
                    child: Text(
                      '松江阅',
                      style: TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: Text(L10n.of(context).appVersion),
                  subtitle: Text(version + (kDebugMode ? ' (debug)' : '')),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: version));
                    AnxToast.show(L10n.of(context).notesPageCopied);
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
                if (EnvVar.showBeian) ...[
                  GestureDetector(
                    onTap: () {
                      launchUrl(Uri.parse('https://beian.miit.gov.cn/'),
                          mode: LaunchMode.externalApplication);
                    },
                    child: const Text('闽ICP备2025091402号-1A'),
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
