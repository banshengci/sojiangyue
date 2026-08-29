import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/theme/songjiang_theme.dart';
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

ThemeData colorSchema(
  Prefs prefsNotifier,
  BuildContext context,
  Brightness brightness,
) {
  brightness = prefsNotifier.eInkMode
      ? Brightness.light
      : switch (prefsNotifier.themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
  Color seedColor = prefsNotifier.themeColor;
  final isDark = brightness == Brightness.dark;
  final isEinkMode = prefsNotifier.eInkMode;

  // 松江阅自有底色：浅色取宣纸暖白，深色取松烟墨绿，
  // 刻意区别于上游 Anx 的 iOS 冷灰（#F2F2F7 / #1C1C1E）。
  final lightGropedBackground = SongJiangColors.paper;
  final darkGropedBackground =
      prefsNotifier.trueDarkMode ? Color(0xFF000000) : SongJiangColors.ink;
  final gropedBackgroundColor = isEinkMode
      ? Colors.white
      : isDark
          ? darkGropedBackground
          : lightGropedBackground;

  final colorScheme = isEinkMode
      ? const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          primaryContainer: Colors.grey,
          onPrimaryContainer: Colors.black,
          secondary: Colors.grey,
          onSecondary: Colors.white,
          secondaryContainer: Colors.black12,
          onSecondaryContainer: Colors.black,
          surface: Colors.white,
          onSurface: Colors.black,
        )
      : switch (brightness) {
          Brightness.light => ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
              tertiary: SongJiangColors.pollen,
              surface: lightGropedBackground,
              surfaceContainer: SongJiangColors.paperCard,
              surfaceContainerLowest: const Color(0xFFFFFFFF),
              surfaceContainerLow: const Color(0xFFFAF7F0),
              surfaceContainerHigh: const Color(0xFFEDE8DC),
              surfaceContainerHighest: const Color(0xFFE3DDCE),
              surfaceDim: const Color(0xFFDAD5C7),
              surfaceBright: const Color(0xFFFFFDF7),
            ),
          Brightness.dark => ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.dark,
              tertiary: SongJiangColors.pollen,
              surface: darkGropedBackground,
              surfaceContainer: SongJiangColors.inkCard,
              surfaceContainerLowest: const Color(0xFF0B0F0D),
              surfaceContainerLow: const Color(0xFF171E1A),
              surfaceContainerHigh: SongJiangColors.inkCardHigh,
              surfaceContainerHighest: const Color(0xFF2E3831),
              surfaceDim: const Color(0xFF0E1210),
              surfaceBright: const Color(0xFF333C35),
            ),
        };

  ThemeData themeData = isEinkMode
      ? FlexThemeData.light(
          useMaterial3: true,
          swapLegacyOnMaterial3: true,
          colorScheme: colorScheme)
      : switch (brightness) {
          Brightness.light => FlexThemeData.light(
              useMaterial3: true,
              swapLegacyOnMaterial3: true,
              colorScheme: colorScheme,
            ),
          Brightness.dark => FlexThemeData.dark(
              useMaterial3: true,
              swapLegacyOnMaterial3: true,
              darkIsTrueBlack: prefsNotifier.trueDarkMode,
              colorScheme: colorScheme,
            )
        };

  final radius = const BorderRadius.all(Radius.circular(16));

  return themeData
      .copyWith(
          sliderTheme: const SliderThemeData(year2023: false),
          progressIndicatorTheme:
              const ProgressIndicatorThemeData(year2023: false),
          scaffoldBackgroundColor: gropedBackgroundColor,
          bottomSheetTheme: BottomSheetThemeData()
              .copyWith(backgroundColor: gropedBackgroundColor),
          drawerTheme: DrawerThemeData()
              .copyWith(backgroundColor: gropedBackgroundColor),
          dialogTheme: DialogThemeData().copyWith(
            backgroundColor: gropedBackgroundColor,
            shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(24))),
          ),

          // ---- 松江阅自有形态语言 ----
          cardTheme: CardThemeData(
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            color: colorScheme.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: radius),
            margin: EdgeInsets.zero,
          ),
          listTileTheme: ListTileThemeData(
            shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(12))),
            iconColor: colorScheme.primary,
          ),
          dividerTheme: DividerThemeData(
            thickness: 0.6,
            space: 0.6,
            color: colorScheme.outlineVariant.withAlpha(
              isDark ? 90 : 120,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(12))),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(12))),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(12))),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(12))),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(12))),
          ),
          appBarTheme: themeData.appBarTheme.copyWith(
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            backgroundColor: gropedBackgroundColor,
          ),
          floatingActionButtonTheme: themeData.floatingActionButtonTheme
              .copyWith(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          const BorderRadius.all(Radius.circular(16)))),
          // 底部导航：选中项用松绿实心胶囊指示，未选中保持低对比
          bottomNavigationBarTheme: themeData.bottomNavigationBarTheme.copyWith(
            elevation: 0,
            backgroundColor: Colors.transparent,
            selectedItemColor: colorScheme.primary,
            unselectedItemColor: colorScheme.onSurfaceVariant.withAlpha(160),
            selectedLabelStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2),
            unselectedLabelStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.2),
            showSelectedLabels: true,
            showUnselectedLabels: true,
          ),
          navigationBarTheme: themeData.navigationBarTheme.copyWith(
            elevation: 0,
            backgroundColor: Colors.transparent,
            indicatorColor: colorScheme.primary.withAlpha(isDark ? 60 : 36),
            surfaceTintColor: Colors.transparent,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          ),
          navigationRailTheme: themeData.navigationRailTheme.copyWith(
            elevation: 0,
            backgroundColor: Colors.transparent,
            selectedIconTheme: IconThemeData(color: colorScheme.primary),
            unselectedIconTheme: IconThemeData(
                color: colorScheme.onSurfaceVariant.withAlpha(160)),
            indicatorColor: colorScheme.primary.withAlpha(isDark ? 60 : 36),
            indicatorShape: const StadiumBorder(),
          ),
          chipTheme: themeData.chipTheme.copyWith(
            shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(10))),
          ),
          switchTheme: SwitchThemeData(
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) =>
                states.contains(WidgetState.selected)
                    ? const Icon(Icons.check, size: 16)
                    : null),
          ))
      .useSystemChineseFont(brightness);
}
