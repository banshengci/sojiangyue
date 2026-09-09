import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/utils/theme_mode_to_string.dart';
import 'package:songjiang_reader/config/theme_prefs.dart';
import 'package:songjiang_reader/widgets/common/sj_segmented_button.dart';
import 'package:flutter/material.dart';

class ChangeThemeMode extends StatefulWidget {
  const ChangeThemeMode({super.key});

  @override
  ChangeThemeModeState createState() => ChangeThemeModeState();
}

class ChangeThemeModeState extends State<ChangeThemeMode> {
  late String _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = themeModeToString(ThemePrefs.themeMode);
  }

  @override
  Widget build(BuildContext context) {
    return SjSegmentedButton<String>(
      segments: <SegmentButtonItem<String>>[
        SegmentButtonItem(
          value: 'auto',
          label: L10n.of(context).settingsSystemMode,
          icon: const Icon(Icons.brightness_auto),
        ),
        SegmentButtonItem(
          value: 'dark',
          label: L10n.of(context).settingsDarkMode,
          icon: const Icon(Icons.brightness_2),
        ),
        SegmentButtonItem(
          value: 'light',
          label: L10n.of(context).settingsLightMode,
          icon: const Icon(Icons.brightness_5),
        ),
      ],
      selected: {_themeMode},
      onSelectionChanged: (Set<String> newSelection) {
        final String mode = newSelection.first;
        ThemePrefs.saveThemeMode(mode);
        setState(() {
          _themeMode = mode;
        });
      },
    );
  }
}
