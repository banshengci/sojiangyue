import 'dart:io';

import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:songjiang_reader/config/ai_prefs.dart';
import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/config/bgimg_prefs.dart';
import 'package:songjiang_reader/config/bookshelf_prefs.dart';
import 'package:songjiang_reader/config/developer_prefs.dart';
import 'package:songjiang_reader/config/excerpt_share_prefs.dart';
import 'package:songjiang_reader/config/http_proxy_prefs.dart';
import 'package:songjiang_reader/config/iap_prefs.dart';
import 'package:songjiang_reader/config/local_dict_prefs.dart';
import 'package:songjiang_reader/config/notes_prefs.dart';
import 'package:songjiang_reader/config/opds_prefs.dart';
import 'package:songjiang_reader/config/reading_style_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/config/translate_prefs.dart';
import 'package:songjiang_reader/config/tts_prefs.dart';
import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/enums/sync_direction.dart';
import 'package:songjiang_reader/enums/sync_trigger.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/window_info.dart';
import 'package:songjiang_reader/page/home_page.dart';
import 'package:songjiang_reader/page/migration_page.dart';
import 'package:songjiang_reader/service/book_player/book_player_server.dart';
import 'package:songjiang_reader/service/network/http_proxy_overrides.dart';
import 'package:songjiang_reader/service/tts/tts_handler.dart';
import 'package:songjiang_reader/utils/get_path/macos_migration.dart';
import 'package:songjiang_reader/utils/color_scheme.dart';
import 'package:songjiang_reader/utils/error/common.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/window_position_validator.dart';
import 'package:songjiang_reader/providers/sync.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:heroine/heroine.dart';
import 'package:provider/provider.dart' as provider;
import 'package:window_manager/window_manager.dart';

final navigatorKey = GlobalKey<NavigatorState>();
late AudioHandler audioHandler;
final heroineController = HeroineController();

/// Whether macOS data migration is needed (checked at startup)
bool _needsMigration = false;
MigrationCheckResult? _migrationCheckResult;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 领域 Prefs 须先于 Prefs() 单例初始化（单例构造会触发 initPrefs）
  await HttpProxyPrefs.ensureInitialized();
  await TtsPrefs.ensureInitialized();
  await ThemePrefs.ensureInitialized();
  await BgimgPrefs.ensureInitialized();
  await DeveloperPrefs.ensureInitialized();
  await ExcerptSharePrefs.ensureInitialized();
  await IapPrefs.ensureInitialized();
  await LocalDictPrefs.ensureInitialized();
  await ReadingStylePrefs.ensureInitialized();
  await SyncPrefs.ensureInitialized();
  await AiPrefs.ensureInitialized();
  await BookshelfPrefs.ensureInitialized();
  await NotesPrefs.ensureInitialized();
  await OpdsPrefs.ensureInitialized();
  await ReadingUiPrefs.ensureInitialized();
  await TranslatePrefs.ensureInitialized();
  await AppMiscPrefs.ensureInitialized();
  await Prefs().initPrefs();
  HttpOverrides.global = SjHttpProxyOverrides();

  // Initialize desktop window with validated position
  if (SjPlatform.isWindows || SjPlatform.isMacOS) {
    await initializeDesktopWindow();
  }

  // Check if migration is needed before initializing paths
  if (SjPlatform.isMacOS) {
    _migrationCheckResult = await checkMigrationNeeded();
    _needsMigration = _migrationCheckResult?.needsMigration ?? false;
  }

  // If no migration needed, initialize paths normally
  if (!_needsMigration) {
    await initBasePath();
    SjLog.init();
    SjError.init();
    await DBHelper().initDB();
  }

  // 必须 await：本地 Server 需在导入书籍前完成端口绑定，
  // 否则 getBookMetadata 取 Server().port 时 _server 尚为 null 会抛空指针，
  // 导入流程在 30s 超时里静默失败，表现为「导入了但书架不显示」。
  await Server().start();

  audioHandler = await AudioService.init(
    builder: () => TtsHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.songjiang.reader.tts.channel.audio',
      androidNotificationChannelName: '松江阅 TTS',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  SmartDialog.config.custom = SmartConfigCustom(
    maskColor: Colors.black.withAlpha(35),
    useAnimation: true,
    animationType: SmartAnimationType.centerFade_otherSlide,
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp>
    with WidgetsBindingObserver, WindowListener {
  static const Locale _englishFallbackLocale = Locale('en');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    await Server().stop();
    await webViewEnvironment?.dispose();
    webViewEnvironment = null;
    await DBHelper.close();
    await windowManager.destroy();
  }

  @override
  Future<void> onWindowMoved() async {
    await _updateWindowInfo();
  }

  @override
  Future<void> onWindowMaximize() async {
    await _updateWindowInfo();
  }

  @override
  Future<void> onWindowUnmaximize() async {
    await _updateWindowInfo();
  }

  @override
  Future<void> onWindowResized() async {
    await _updateWindowInfo();
  }

  Future<void> _updateWindowInfo() async {
    if (!SjPlatform.isWindows && !SjPlatform.isMacOS) {
      return;
    }
    final windowOffset = await windowManager.getPosition();
    final windowSize = await windowManager.getSize();
    final isMaximized = await windowManager.isMaximized();

    AppMiscPrefs.windowInfo = WindowInfo(
        x: windowOffset.dx,
        y: windowOffset.dy,
        width: windowSize.width,
        height: windowSize.height,
        isMaximized: isMaximized);
    SjLog.info('onWindowClose: Offset: $windowOffset, Size: $windowSize');
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (SyncPrefs.webdavStatus) {
        ref
            .read(syncProvider.notifier)
            .syncData(SyncDirection.both, ref, trigger: SyncTrigger.auto);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (SjPlatform.isIOS) {
        Server().start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider.MultiProvider(
      providers: [
        provider.ChangeNotifierProvider(
          create: (_) => Prefs(),
        ),
      ],
      child: provider.Consumer<Prefs>(
        builder: (context, prefsNotifier, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            scrollBehavior: ScrollConfiguration.of(context).copyWith(
              physics: const BouncingScrollPhysics(),
              // dragDevices: {
              //   PointerDeviceKind.touch,
              //   PointerDeviceKind.mouse,
              // },
            ),
            navigatorObservers: [
              FlutterSmartDialog.observer,
              heroineController
            ],
            builder: FlutterSmartDialog.init(),
            navigatorKey: navigatorKey,
            locale: AppMiscPrefs.locale,
            localeListResolutionCallback: _resolveLocale,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            title: '松江阅',
            themeMode: ThemePrefs.themeMode,
            theme: colorSchema(context, Brightness.light),
            darkTheme: colorSchema(context, Brightness.dark),
            home: _needsMigration
                ? _MigrationWrapper(
                    migrationCheckResult: _migrationCheckResult!)
                : const HomePage(),
          );
        },
      ),
    );
  }

  Locale _resolveLocale(
    List<Locale>? preferredLocales,
    Iterable<Locale> supportedLocales,
  ) {
    if (preferredLocales == null || preferredLocales.isEmpty) {
      return _englishFallbackLocale;
    }

    final Locale resolvedLocale = basicLocaleListResolution(
      preferredLocales,
      supportedLocales,
    );

    final bool hasMatch = preferredLocales.any((Locale preferredLocale) {
      return supportedLocales.any((Locale supportedLocale) {
        if (preferredLocale.languageCode != supportedLocale.languageCode) {
          return false;
        }

        final String? preferredCountryCode = preferredLocale.countryCode;
        final String? supportedCountryCode = supportedLocale.countryCode;

        return preferredCountryCode == null ||
            supportedCountryCode == null ||
            preferredCountryCode == supportedCountryCode;
      });
    });

    return hasMatch ? resolvedLocale : _englishFallbackLocale;
  }
}

/// Widget that wraps the migration flow on macOS.
/// Shows MigrationPage during migration, then navigates to HomePage.
class _MigrationWrapper extends StatefulWidget {
  final MigrationCheckResult migrationCheckResult;

  const _MigrationWrapper({required this.migrationCheckResult});

  @override
  State<_MigrationWrapper> createState() => _MigrationWrapperState();
}

class _MigrationWrapperState extends State<_MigrationWrapper> {
  bool _migrationComplete = false;

  Future<void> _onMigrationComplete() async {
    // Initialize paths and DB after migration
    await initBasePath();
    SjLog.init();
    SjError.init();
    await DBHelper().initDB();

    if (mounted) {
      setState(() {
        _migrationComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_migrationComplete) {
      return const HomePage();
    }
    return MigrationPage(onMigrationComplete: _onMigrationComplete);
  }
}
