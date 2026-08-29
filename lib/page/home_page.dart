import 'dart:ui';

import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/enums/sync_direction.dart';
import 'package:songjiang_reader/enums/sync_trigger.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/service/initialization_check.dart';
import 'package:songjiang_reader/page/home_page/bookshelf_page.dart';
import 'package:songjiang_reader/page/home_page/notes_page.dart';
import 'package:songjiang_reader/page/home_page/settings_page.dart';
import 'package:songjiang_reader/page/home_page/statistics_page.dart';
import 'package:songjiang_reader/service/receive_file/receive_share.dart';
import 'package:songjiang_reader/service/vibration_service.dart';
import 'package:songjiang_reader/utils/check_update.dart';
import 'package:songjiang_reader/utils/env_var.dart';
import 'package:songjiang_reader/utils/get_path/get_temp_dir.dart';
import 'package:songjiang_reader/utils/load_default_font.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';
import 'package:songjiang_reader/providers/sync.dart';
import 'package:songjiang_reader/providers/iap.dart';
import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/container/filled_container.dart';
import 'package:songjiang_reader/widgets/settings/about.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:url_launcher/url_launcher.dart';

WebViewEnvironment? webViewEnvironment;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _currentTab = 'bookshelf';

  bool? _expanded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => initAnx());
  }

  Future<void> _checkWindowsWebview() async {
    final availableVersion = await WebViewEnvironment.getAvailableVersion();
    AnxLog.info('WebView2 version: $availableVersion');

    if (availableVersion == null) {
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: const Icon(Icons.error),
          content: Text(L10n.of(context).webview2NotInstalled),
          actions: [
            TextButton(
              onPressed: () => {
                launchUrl(
                    Uri.parse(
                        'https://developer.microsoft.com/en-us/microsoft-edge/webview2'),
                    mode: LaunchMode.externalApplication)
              },
              child: Text(L10n.of(context).webview2Install),
            ),
          ],
        ),
      );
    } else {
      webViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
            userDataFolder: (await getAnxTempDir()).path),
      );
    }
  }

  void _showDbUpdatedDialog() {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).commonAttention),
        content: Text(L10n.of(context).dbUpdatedTip),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> initAnx() async {
    if (EnvVar.enableInAppPurchase) {
      ref.read(iapProvider.future);
    }
    AnxToast.init(context);
    checkUpdate(false);
    InitializationCheck.check();
    if (Prefs().webdavStatus) {
      await Sync().init();
      await Sync().syncData(SyncDirection.both, ref, trigger: SyncTrigger.auto);
    }
    loadDefaultFont();

    if (AnxPlatform.isWindows) {
      await _checkWindowsWebview();
    }

    if (AnxPlatform.isAndroid || AnxPlatform.isIOS || AnxPlatform.isOhos) {
      receiveShareIntent(ref);
    }

    if (DBHelper.updatedDB) {
      _showDbUpdatedDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 松江阅底部导航固定为四个：书架 / 统计 / 笔记 / 设置。
    // AI 不占用底栏入口，改由「更多设置 → AI 对话」与阅读页侧栏进入。
    List<Map<String, dynamic>> navBarItems = [
      {
        'icon': EvaIcons.book_open,
        'label': L10n.of(context).navBarBookshelf,
        'identifier': 'bookshelf'
      },
      if (Prefs().bottomNavigatorShowStatistics)
        {
          'icon': Icons.show_chart,
          'label': L10n.of(context).navBarStatistics,
          'identifier': 'statistics'
        },
      if (Prefs().bottomNavigatorShowNote)
        {
          'icon': Icons.note,
          'label': L10n.of(context).navBarNotes,
          'identifier': 'notes'
        },
      {
        'icon': EvaIcons.settings_2,
        'label': L10n.of(context).navBarSettings,
        'identifier': 'settings'
      },
    ];

    int currentIndex = navBarItems
        .indexWhere((element) => element['identifier'] == _currentTab);
    if (currentIndex == -1) {
      currentIndex = 0;
      _currentTab = 'bookshelf';
    }

    Widget pages(
      int index,
      BoxConstraints constraints,
      ScrollController? controller,
    ) {
      final page = [
        BookshelfPage(controller: controller),
        if (Prefs().bottomNavigatorShowStatistics)
          StatisticPage(controller: controller),
        if (Prefs().bottomNavigatorShowNote) NotesPage(controller: controller),
        SettingsPage(controller: controller),
      ];
      return page[index];
    }

    void onBottomTap(int index, bool fromRail) {
      VibrationService.heavy();
      setState(() {
        _currentTab = navBarItems[index]['identifier'];
      });
    }

    List<NavigationRailDestination> railBarItems = navBarItems.map((item) {
      return NavigationRailDestination(
        icon: Icon(item['icon'] as IconData),
        label: Text(item['label'] as String),
      );
    }).toList();

    List<BottomNavigationBarItem> bottomBarItems = navBarItems.map((item) {
      return BottomNavigationBarItem(
        icon: Icon(item['icon'] as IconData),
        label: item['label'] as String,
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        _expanded ??= constraints.maxWidth > 1000;
        if (constraints.maxWidth > 600) {
          return Scaffold(
            extendBody: true,
            body: Row(
              children: [
                SafeArea(
                  bottom: false,
                  child: FilledContainer(
                    margin: const EdgeInsets.all(16),
                    color: ElevationOverlay.applySurfaceTint(
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).colorScheme.primary,
                      3,
                    ),
                    radius: 20,
                    child: SafeArea(
                      child: NavigationRail(
                        leading: InkWell(
                          onTap: () => openAboutDialog(),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                width: 34,
                                height: 34,
                                SongJiangBrand.logoAsset,
                              ),
                            ),
                          ),
                        ),
                        groupAlignment: 1,
                        extended: false,
                        selectedIndex: currentIndex,
                        onDestinationSelected: (int index) =>
                            onBottomTap(index, true),
                        destinations: railBarItems,
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: Colors.transparent,
                        // elevation: 0,
                      ),
                    ),
                  ),
                ),
                Expanded(child: pages(currentIndex, constraints, null)),
              ],
            ),
          );
        } else {
          return Scaffold(
            extendBody: true,
            body: BottomBar(
              width: 330,
              body: (_, controller) =>
                  pages(currentIndex, constraints, controller),
              hideOnScroll: Prefs().autoHideBottomBar,
              scrollOpposite: false,
              curve: Curves.easeIn,
              barColor: Colors.transparent,
              iconDecoration: BoxDecoration(
                color: Prefs().autoHideBottomBar
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(500),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainer
                          .withAlpha(123),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                        width: 0.5,
                      ),
                    ),
                    child: BottomNavigationBar(
                      selectedFontSize: 12,
                      enableFeedback: true,
                      type: BottomNavigationBarType.fixed,
                      landscapeLayout:
                          BottomNavigationBarLandscapeLayout.linear,
                      currentIndex: currentIndex,
                      onTap: (int index) => onBottomTap(index, false),
                      items: bottomBarItems,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      // height: 64,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      },
    );
  }
}
