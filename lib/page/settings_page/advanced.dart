import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/developer_prefs.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/md5_statistics.dart';
import 'package:songjiang_reader/page/settings_page/subpage/chapter_split_rules_page.dart';
import 'package:songjiang_reader/page/settings_page/subpage/log_page.dart';
import 'package:songjiang_reader/page/changelog_screen.dart';
import 'package:songjiang_reader/page/onboarding_screen.dart';
import 'package:songjiang_reader/service/md5_service.dart';
import 'package:songjiang_reader/service/network/http_proxy_overrides.dart';
import 'package:songjiang_reader/utils/app_version.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/settings/settings_section.dart';
import 'package:songjiang_reader/widgets/settings/settings_tile.dart';
import 'package:songjiang_reader/widgets/settings/settings_title.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/providers/http_proxy.dart';

class AdvancedSetting extends ConsumerStatefulWidget {
  const AdvancedSetting({super.key});

  @override
  ConsumerState<AdvancedSetting> createState() => _AdvancedSettingState();
}

class _AdvancedSettingState extends ConsumerState<AdvancedSetting> {
  MD5Statistics? _md5Stats;
  bool _isCalculating = false;
  double _progress = 0.0;
  String _currentFile = '';

  @override
  void initState() {
    super.initState();
    _loadMd5Statistics();
  }

  Future<void> _loadMd5Statistics() async {
    final stats = await MD5Service.getMd5Statistics();
    setState(() {
      _md5Stats = stats;
    });
  }

  @override
  Widget build(BuildContext context) {
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).eBookProcess),
          tiles: [
            SettingsTile.navigation(
              leading: const Icon(Icons.auto_stories_outlined),
              title: Text(L10n.of(context).chapterSplitting),
              onPressed: (_) {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => const ChapterSplitRulesPage(),
                  ),
                );
              },
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsAdvancedLog),
          tiles: [
            SettingsTile.switchTile(
              title: Text(L10n.of(context).settingsAdvancedClearLogWhenStart),
              leading: const Icon(Icons.delete_forever_outlined),
              initialValue: DeveloperPrefs.clearLogWhenStart,
              onToggle: (value) {
                DeveloperPrefs.clearLogWhenStart = value;
                setState(() {});
              },
            ),
            SettingsTile.navigation(
                leading: const Icon(Icons.bug_report),
                title: Text(L10n.of(context).settingsAdvancedLog),
                onPressed: onLogPressed),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).md5Management),
          tiles: [
            if (_md5Stats != null)
              SettingsTile(
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.fingerprint),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(L10n.of(context).md5Statistics),
                        const SizedBox(height: 4),
                        Text(
                          L10n.of(context).md5TotalBooks(_md5Stats!.totalBooks),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          L10n.of(context)
                              .md5BooksWithMd5(_md5Stats!.booksWithMd5),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          L10n.of(context)
                              .md5BooksWithoutMd5(_md5Stats!.booksWithoutMd5),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          L10n.of(context)
                              .md5LocalFiles(_md5Stats!.localFilesCount),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          L10n.of(context).md5LocalFilesWithoutMd5(
                              _md5Stats!.localFilesWithoutMd5),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_isCalculating)
              SettingsTile(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L10n.of(context).md5Calculating),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 4),
                    Text(
                      '${(_progress * 100).toStringAsFixed(1)}% - $_currentFile',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                leading: const Icon(Icons.calculate),
              )
            else
              SettingsTile.navigation(
                title: Text(L10n.of(context).md5CalculateMissing),
                leading: const Icon(Icons.calculate),
                onPressed: _calculateMd5,
                // enabled: _md5Stats?.booksWithoutMd5 != 0,
              ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsAdvancedJavascript),
          tiles: [
            SettingsTile.switchTile(
              title: Text(
                  L10n.of(context).settingsAdvancedEnableJavascriptForEpub),
              leading: const Icon(Icons.code),
              initialValue: ReadingUiPrefs.enableJsForEpub,
              onToggle: (value) {
                ReadingUiPrefs.enableJsForEpub = value;
                setState(() {});
              },
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsAdvancedNetwork),
          tiles: [
            SettingsTile.switchTile(
              title: Text(L10n.of(context).settingsAdvancedHttpProxyEnabled),
              leading: const Icon(Icons.wifi_tethering),
              initialValue:
                  ref.watch(httpProxyNotifierProvider).valueOrNull?.enabled ??
                      false,
              onToggle: (value) {
                ref.read(httpProxyNotifierProvider.notifier).setEnabled(value);
              },
            ),
            SettingsTile.navigation(
              title: Text(L10n.of(context).settingsAdvancedHttpProxyConfig),
              leading: const Icon(Icons.http),
              value: Text(() {
                final proxy = ref.watch(httpProxyNotifierProvider).valueOrNull;
                if (proxy == null || proxy.host.isEmpty) {
                  return L10n.of(context).settingsAdvancedHttpProxyNotConfigured;
                }
                return proxy.enabled
                    ? '${proxy.host}:${proxy.port} (Test: ${proxy.testUrl})'
                    : '${proxy.host}:${proxy.port}';
              }()),
              onPressed: _showHttpProxyDialog,
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).hints),
          tiles: [
            SettingsTile.navigation(
              title: Text(L10n.of(context).showAllHintsAgain),
              leading: const Icon(Icons.lightbulb_outline),
              onPressed: (_) {
                ReadingUiPrefs.resetHints();
                SjToast.show(L10n.of(context).allHintsWillBeShownAgain);
              },
            ),
            SettingsTile.navigation(
              title: Text(L10n.of(context).viewChangelog),
              leading: const Icon(Icons.update),
              onPressed: _showChangelog,
            ),
            SettingsTile.navigation(
              title: Text(L10n.of(context).viewOnboarding),
              leading: const Icon(Icons.menu_book_outlined),
              onPressed: _showOnboarding,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _calculateMd5(BuildContext context) async {
    if (_isCalculating) return;

    if (_md5Stats?.localFilesWithoutMd5 == 0) {
      SjToast.show(L10n.of(context).md5NoCalculationNeeded);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).md5CalculateConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.of(context).md5CalculateConfirmContent),
            const SizedBox(height: 8),
            if (_md5Stats!.localFilesWithoutMd5 < _md5Stats!.booksWithoutMd5)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        L10n.of(context).md5MissingFilesTip,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(L10n.of(context).commonCancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(L10n.of(context).commonConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isCalculating = true;
      _progress = 0.0;
      _currentFile = '';
    });

    try {
      final booksToCalculate = await bookDao.getBooksWithoutMd5();

      final result = await MD5Service.batchCalculateMd5(
        booksToCalculate,
        onProgress: (current, total, currentFile) {
          setState(() {
            _progress = current / total;
            _currentFile = currentFile;
          });
        },
      );

      await _loadMd5Statistics();

      setState(() {
        _isCalculating = false;
        _progress = 0.0;
        _currentFile = '';
      });

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(L10n.of(context).md5CalculationComplete),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L10n.of(context)
                    .md5CalculationResultCalculated(result.calculated)),
                Text(L10n.of(context)
                    .md5CalculationResultSkipped(result.skipped)),
                Text(
                    L10n.of(context).md5CalculationResultFailed(result.failed)),
                if (result.missingFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    L10n.of(context).md5MissingFiles,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...result.missingFiles.take(5).map((file) => Text('• $file')),
                  if (result.missingFiles.length > 5)
                    Text(L10n.of(context)
                        .md5AndMore(result.missingFiles.length - 5)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L10n.of(context).commonOk),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isCalculating = false;
        _progress = 0.0;
        _currentFile = '';
      });

      if (context.mounted) {
        SjToast.show(L10n.of(context).md5CalculationError(e.toString()));
      }
    }
  }

  Future<void> _showHttpProxyDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return const _HttpProxyDialog();
      },
    );
  }
}

class _HttpProxyDialog extends ConsumerStatefulWidget {
  const _HttpProxyDialog();

  @override
  ConsumerState<_HttpProxyDialog> createState() => _HttpProxyDialogState();
}

class _HttpProxyDialogState extends ConsumerState<_HttpProxyDialog> {
  late final TextEditingController hostController;
  late final TextEditingController portController;
  late final TextEditingController testUrlController;

  @override
  void initState() {
    super.initState();
    final proxy = ref.read(httpProxyNotifierProvider).valueOrNull;
    hostController = TextEditingController(text: proxy?.host ?? '');
    portController =
        TextEditingController(text: (proxy?.port ?? 7890).toString());
    testUrlController =
        TextEditingController(text: proxy?.testUrl ?? 'https://google.com');
  }

  @override
  void dispose() {
    hostController.dispose();
    portController.dispose();
    testUrlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    var host = hostController.text.trim();
    final port = int.tryParse(portController.text.trim());
    final testUrl = testUrlController.text.trim();

    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      SjToast.show(L10n.of(context).settingsAdvancedHttpProxyInvalidInput);
      return;
    }

    final hostLower = host.toLowerCase();
    if (hostLower.startsWith('https://') ||
        hostLower.startsWith('socks5://') ||
        hostLower.startsWith('socks4://') ||
        hostLower.startsWith('socks://')) {
      SjToast.show(L10n.of(context).settingsAdvancedHttpProxyInvalidInput);
      return;
    }

    if (hostLower.startsWith('http://')) {
      host = host.substring(7);
    }

    if (testUrl.isEmpty) {
      SjToast.show(L10n.of(context).commonInputCannotBeEmpty);
      return;
    }

    SjToast.show(L10n.of(context).settingsAdvancedHttpProxyTesting);

    final success = await SjHttpProxyOverrides.testProxy(host, port, testUrl);

    if (!mounted) return;

    if (success) {
      SjToast.show(L10n.of(context).settingsAdvancedHttpProxyTestSuccess);
    } else {
      SjToast.show(L10n.of(context).settingsAdvancedHttpProxyTestFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.of(context).settingsAdvancedHttpProxyConfig),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: hostController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: L10n.of(context).settingsAdvancedHttpProxyHost,
              hintText: L10n.of(context).settingsAdvancedHttpProxyHostHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: portController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: L10n.of(context).settingsAdvancedHttpProxyPort,
              hintText: L10n.of(context).settingsAdvancedHttpProxyPortHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: testUrlController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: L10n.of(context).settingsAdvancedHttpProxyTestUrl,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _testConnection,
          child: Text(L10n.of(context).settingsAdvancedHttpProxyTest),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).commonCancel),
        ),
        TextButton(
          onPressed: () async {
            var host = hostController.text.trim();
            final port = int.tryParse(portController.text.trim());
            final testUrl = testUrlController.text.trim();
            if (host.isEmpty || port == null || port <= 0 || port > 65535) {
              SjToast.show(
                  L10n.of(context).settingsAdvancedHttpProxyInvalidInput);
              return;
            }

            final hostLower = host.toLowerCase();
            if (hostLower.startsWith('https://') ||
                hostLower.startsWith('socks5://') ||
                hostLower.startsWith('socks4://') ||
                hostLower.startsWith('socks://')) {
              SjToast.show(
                  L10n.of(context).settingsAdvancedHttpProxyInvalidInput);
              return;
            }

            if (hostLower.startsWith('http://')) {
              host = host.substring(7);
            }

            await ref.read(httpProxyNotifierProvider.notifier).saveConfig(
                  host: host,
                  port: port,
                  testUrl: testUrl,
                );
            Navigator.of(context).pop();
          },
          child: Text(L10n.of(context).commonSave),
        ),
      ],
    );
  }
}

Future<void> _showChangelog(BuildContext context) async {
  final currentVersion = await getAppVersion();
  final lastVersion = AppMiscPrefs.lastAppVersion ?? currentVersion;

  showCupertinoSheet(
    context: navigatorKey.currentContext ?? context,
    builder: (sheetContext) => ChangelogScreen(
      lastVersion: lastVersion,
      currentVersion: currentVersion,
      onComplete: () {
        AppMiscPrefs.lastAppVersion = currentVersion;
        Navigator.pop(sheetContext);
      },
    ),
  );
}

Future<void> _showOnboarding(BuildContext context) async {
  final currentVersion = await getAppVersion();

  showCupertinoSheet(
    context: navigatorKey.currentContext ?? context,
    builder: (sheetContext) => Scaffold(
      body: OnboardingScreen(
        onComplete: () {
          AppMiscPrefs.lastAppVersion = currentVersion;
          Navigator.pop(sheetContext);
        },
      ),
    ),
  );
}

void onLogPressed(BuildContext context) {
  Navigator.push(
    context,
    CupertinoPageRoute(
      builder: (context) => const LogPage(),
    ),
  );
}
