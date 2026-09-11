import 'package:songjiang_reader/design/songjiang/sj_icon.dart';
import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/config/developer_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/page/settings_page/ai.dart';
import 'package:songjiang_reader/page/settings_page/advanced.dart';
import 'package:songjiang_reader/page/settings_page/appearance.dart';
import 'package:songjiang_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:songjiang_reader/page/settings_page/narrate.dart';
import 'package:songjiang_reader/page/settings_page/opds.dart';
import 'package:songjiang_reader/page/settings_page/reading.dart';
import 'package:songjiang_reader/page/settings_page/settings_page.dart';
import 'package:songjiang_reader/page/settings_page/storage.dart';
import 'package:songjiang_reader/page/settings_page/sync.dart';
import 'package:songjiang_reader/page/settings_page/local_dict_settings.dart';
import 'package:songjiang_reader/page/settings_page/translate.dart';
import 'package:songjiang_reader/page/vocab_list_page.dart';
import 'package:songjiang_reader/theme/songjiang_icons.dart';
import 'package:songjiang_reader/utils/env_var.dart';
import 'package:songjiang_reader/widgets/settings/about.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MoreSettings extends StatelessWidget {
  const MoreSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.settings_outlined),
      title: Text(L10n.of(context).settingsMoreSettings),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          CupertinoPageRoute(
              fullscreenDialog: false,
              builder: (context) => const SubMoreSettings()),
        );
      },
    );
  }
}

class SubMoreSettings extends StatefulWidget {
  const SubMoreSettings({super.key});

  @override
  State<SubMoreSettings> createState() => _SubMoreSettingsState();
}

class _SubMoreSettingsState extends State<SubMoreSettings> {
  int selectedIndex = 0;
  Widget? settingsDetail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final showDeveloperEntry = DeveloperPrefs.developerOptionsEnabled;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text(L10n.of(context).settingsMoreSettings),
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            List<Map<String, dynamic>> settings = [
              {
                "title": L10n.of(context).settingsAppearance,
                "icon": const SjIcon(SjIconName.typography),
                "sections": const AppearanceSetting(),
                "subtitles": [
                  L10n.of(context).settingsAppearanceTheme,
                  L10n.of(context).settingsAppearanceDisplay,
                  L10n.of(context).settingsBookshelfCover,
                ],
              },
              {
                "title": L10n.of(context).settingsReading,
                "icon": const SjIcon(SjIconName.read),
                "sections": const ReadingSettings(),
                "subtitles": [
                  L10n.of(context).readingPageReading,
                  L10n.of(context).downloadFonts,
                  L10n.of(context).readingPageStyle,
                  L10n.of(context).readingPageOther,
                ],
              },
              {
                "title": L10n.of(context).settingsSync,
                "icon": const SjIcon(SjIconName.sync),
                "sections": const SyncSetting(),
                "subtitles": [
                  L10n.of(context).settingsSyncWebdav,
                  L10n.of(context).exportAndImport,
                ],
              },
              {
                "title": L10n.of(context).opdsTitle,
                "icon": const SjIcon(SjIconName.opds),
                "sections": const OpdsSettingsPage(),
                "subtitles": [
                  L10n.of(context).opdsAddCatalog,
                  L10n.of(context).opdsBrowse,
                ],
              },
              {
                "title": L10n.of(context).settingsNarrate,
                "icon": const SjIcon(SjIconName.listen),
                "sections": const NarrateSettings(),
                "subtitles": [
                  L10n.of(context).settingsNarrateVoice,
                  L10n.of(context).settingsNarrateVoiceModel,
                ],
              },
              {
                "title": L10n.of(context).settingsTranslate,
                "icon": const SjIcon(SjIconName.translate),
                "sections": const TranslateSetting(),
                "subtitles": [
                  L10n.of(context).settingsTranslate,
                ],
              },
              if (EnvVar.enableAIFeature)
                {
                  "title": L10n.of(context).settingsAi,
                  "icon": const SjIcon(SjIconName.aiDeepRead),
                  "sections": const AISettings(),
                  "subtitles": [
                    L10n.of(context).settingsAiServices,
                    L10n.of(context).settingsAiPrompt,
                  ],
                },
              {
                "title": L10n.of(context).storage,
                "icon": const SjIcon(SjIconName.sync),
                "sections": const StorageSettings(),
                "subtitles": [
                  L10n.of(context).storageInfo,
                  L10n.of(context).storageDataFileDetails,
                ],
              },
              {
                "title": L10n.of(context).settingsAdvanced,
                "icon": const SjIcon(SjIconName.settings),
                "sections": const AdvancedSetting(),
                "subtitles": [
                  L10n.of(context).chapterSplitting,
                  L10n.of(context).settingsAdvancedLog,
                  L10n.of(context).duplicateFile,
                  L10n.of(context).settingsAdvancedJavascript,
                  L10n.of(context).settingsAdvancedNetwork,
                ],
              },
            ];

            settingsDetail ??= SettingsPageBody(
              isMobile: false,
              title: settings[0]["title"],
              sections: settings[0]["sections"],
            );

            void setDetail(Widget detail, int id) {
              setState(() {
                settingsDetail = detail;
                selectedIndex = id;
              });
            }

            Widget settingsList(bool isMobile, bool showDeveloper) {
              final children = <Widget>[
                for (int index = 0; index < settings.length; index++)
                  SettingsPageBuilder(
                    isMobile: isMobile,
                    id: index,
                    selectedIndex: selectedIndex,
                    setDetail: setDetail,
                    icon: IconTheme(
                      data: IconThemeData(
                          color: Theme.of(context).colorScheme.primary),
                      child: settings[index]["icon"] as Widget,
                    ),
                    title: settings[index]["title"],
                    sections: settings[index]["sections"],
                    subTitles: settings[index]["subtitles"],
                  ),
                ListTile(
                  leading: IconTheme(
                    data: IconThemeData(
                        color: Theme.of(context).colorScheme.primary),
                    child: const SjIcon(SjIconName.note),
                  ),
                  title: Text(L10n.of(context).vocabTitle),
                  trailing: const Icon(SongJiangIcons.chevronRight),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (context) => const VocabListPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: IconTheme(
                    data: IconThemeData(
                        color: Theme.of(context).colorScheme.primary),
                    child: const SjIcon(SjIconName.read),
                  ),
                  title: Text(L10n.of(context).localDictTitle),
                  trailing: const Icon(SongJiangIcons.chevronRight),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (context) => const LocalDictSettingsPage(),
                      ),
                    );
                  },
                ),
                if (showDeveloper)
                  ListTile(
                    leading: Icon(Icons.developer_mode,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('Developer Options'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (context) => const DeveloperOptionsPage(),
                        ),
                      );
                    },
                  ),
                const About(leadingColor: true),
              ];

              return ListView(
                children: children,
              );
            }

            if (constraints.maxWidth > 600) {
              return Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: settingsList(false, showDeveloperEntry),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(
                    flex: 2,
                    child: settingsDetail!,
                  ),
                ],
              );
            } else {
              return settingsList(true, showDeveloperEntry);
            }
          }),
        );
      },
    );
  }
}
