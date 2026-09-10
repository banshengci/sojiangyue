import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:songjiang_reader/config/local_dict_prefs.dart';
import 'package:songjiang_reader/config/reading_ui_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/settings/settings_section.dart';
import 'package:songjiang_reader/widgets/settings/settings_tile.dart';
import 'package:songjiang_reader/widgets/settings/settings_title.dart';

/// 本地词典管理 + 每日阅读目标。
class LocalDictSettingsPage extends StatefulWidget {
  const LocalDictSettingsPage({super.key});

  @override
  State<LocalDictSettingsPage> createState() => _LocalDictSettingsPageState();
}

class _LocalDictSettingsPageState extends State<LocalDictSettingsPage> {
  String? _dictPath;
  int _entryCount = 0;
  late int _goalMinutes;

  @override
  void initState() {
    super.initState();
    _dictPath = LocalDictPrefs.path;
    _goalMinutes = ReadingUiPrefs.dailyGoalMinutes;
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    final n = await LocalDictPrefs.entryCount;
    if (mounted) setState(() => _entryCount = n);
  }

  Future<void> _pickDictionary() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) {
      SjToast.show(L10n.of(context).importCannotGetFilePath);
      return;
    }
    final ok = await LocalDictPrefs.loadFromFile(path);
    if (!mounted) return;
    if (ok) {
      setState(() => _dictPath = path);
      await _refreshCount();
      if (!mounted) return;
      SjToast.show(L10n.of(context).localDictLoaded(_entryCount));
    } else {
      if (!mounted) return;
      SjToast.show(L10n.of(context).localDictLoadFailed);
    }
  }

  void _clearDictionary() {
    LocalDictPrefs.path = null;
    LocalDictPrefs.clearCache();
    setState(() {
      _dictPath = null;
      _entryCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).localDictTitle),
      ),
      body: settingsSections(
        sections: [
          SettingsSection(
            title: Text(L10n.of(context).localDictTitle),
            tiles: [
              SettingsTile.navigation(
                title: Text(L10n.of(context).localDictImport),
                value: Text(
                  _dictPath == null
                      ? L10n.of(context).localDictEmpty
                      : '$_entryCount',
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: (_) => _pickDictionary(),
              ),
              if (_dictPath != null)
                SettingsTile.navigation(
                  title: Text(L10n.of(context).localDictClear),
                  onPressed: (_) => _clearDictionary(),
                ),
            ],
          ),
          SettingsSection(
            title: Text(L10n.of(context).readingGoalTitle),
            tiles: [
              SettingsTile(
                title: Text(L10n.of(context).readingGoalMinutes(_goalMinutes)),
                description: Text(L10n.of(context).readingGoalTips),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _goalMinutes <= 0
                          ? null
                          : () {
                              setState(
                                  () => _goalMinutes = (_goalMinutes - 5).clamp(0, 240));
                              ReadingUiPrefs.dailyGoalMinutes = _goalMinutes;
                            },
                    ),
                    Text(
                      _goalMinutes == 0
                          ? L10n.of(context).commonNone
                          : '$_goalMinutes min',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        setState(
                            () => _goalMinutes = (_goalMinutes + 5).clamp(0, 240));
                        ReadingUiPrefs.dailyGoalMinutes = _goalMinutes;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
