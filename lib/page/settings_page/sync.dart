import 'dart:convert';
import 'dart:io';

import 'package:songjiang_reader/config/remote_config.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:songjiang_reader/dao/database.dart';
import 'package:songjiang_reader/enums/sync_protocol.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/providers/sync.dart';
import 'package:songjiang_reader/service/sync/sync_client_factory.dart';
import 'package:songjiang_reader/utils/platform_utils.dart';
import 'package:songjiang_reader/utils/save_file_to_download.dart';
import 'package:songjiang_reader/utils/get_path/get_temp_dir.dart';
import 'package:songjiang_reader/utils/get_path/databases_path.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/sync_test_helper.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/config/sync_prefs.dart';
import 'package:songjiang_reader/utils/webdav/test_webdav.dart';
import 'package:songjiang_reader/widgets/settings/settings_title.dart';
import 'package:songjiang_reader/widgets/settings/webdav_switch.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:songjiang_reader/widgets/settings/settings_section.dart';
import 'package:songjiang_reader/widgets/settings/settings_tile.dart';

const String _prefsBackupFileName = 'songjiang_shared_prefs.json';

class SyncSetting extends ConsumerStatefulWidget {
  const SyncSetting({super.key});

  @override
  ConsumerState<SyncSetting> createState() => _SyncSettingState();
}

class _SyncSettingState extends ConsumerState<SyncSetting> {
  @override
  Widget build(BuildContext context) {
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncWebdav),
          tiles: [
            webdavSwitch(context, setState, ref),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                value: Text(SyncPrefs.getSyncInfo(SyncProtocol.webdav)['url'] ??
                    'Not set'),
                // enabled: SyncPrefs.webdavStatus,
                onPressed: (context) async {
                  showWebdavDialog(context);
                }),
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 20, 10),
                child: GestureDetector(
                  onTap: () async {
                    final helpUrl = RemoteConfig.webdavHelpUrl;
                    if (helpUrl.isEmpty) return;
                    if (!await launchUrl(
                        Uri.parse(helpUrl),
                        mode: LaunchMode.externalApplication)) {
                      SjToast.show(L10n.of(context).commonFailed);
                    }
                  },
                  child: Text(
                    L10n.of(context).settingsNarrateClickForHelp,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      decoration: TextDecoration.underline,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdavSyncNow),
                leading: const Icon(Icons.sync_alt),
                // value: Text(Prefs().syncDirection),
                enabled: SyncPrefs.webdavStatus,
                onPressed: (context) {
                  chooseDirection(ref);
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).webdavOnlyWifi),
                leading: const Icon(Icons.wifi),
                initialValue: SyncPrefs.onlySyncWhenWifi,
                onToggle: (bool value) {
                  setState(() {
                    SyncPrefs.onlySyncWhenWifi = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncCompletedToast),
                leading: const Icon(Icons.notifications),
                initialValue: SyncPrefs.syncCompletedToast,
                onToggle: (bool value) {
                  setState(() {
                    SyncPrefs.syncCompletedToast = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncAutoSync),
                leading: const Icon(Icons.sync),
                initialValue: SyncPrefs.autoSync,
                enabled: SyncPrefs.webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    SyncPrefs.autoSync = value;
                  });
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).restoreBackup),
                leading: const Icon(Icons.restore),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showBackupManagementDialog();
                })
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).exportAndImport),
          tiles: [
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportExport),
                leading: const Icon(Icons.cloud_upload),
                onPressed: (context) {
                  exportData(context);
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportImport),
                leading: const Icon(Icons.cloud_download),
                onPressed: (context) {
                  importData();
                }),
          ],
        ),
      ],
    );
  }

  void _showDataDialog(String title) {
    Future.microtask(() {
      SmartDialog.show(
        builder: (BuildContext context) => SimpleDialog(
          title: Center(child: Text(title)),
          children: const [
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    });
  }

  Future<void> exportData(BuildContext context) async {
    SjLog.info('exportData: start');
    if (!mounted) return;

    _showDataDialog(L10n.of(context).exporting);

    final File prefsBackupFile = await _createPrefsBackupFile();

    RootIsolateToken token = RootIsolateToken.instance!;
    final zipPath = await compute(createZipFile, {
      'token': token,
      'prefsBackupFilePath': prefsBackupFile.path,
    });

    final file = File(zipPath);
    SmartDialog.dismiss();
    if (await file.exists()) {
      // SaveFileDialogParams params = SaveFileDialogParams(
      //   sourceFilePath: file.path,
      //   mimeTypesFilter: ['application/zip'],
      // );
      // final filePath = await FlutterFileDialog.saveFile(params: params);
      String fileName =
          'SongJiang-Backup-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}-v3.zip';

      String? filePath = await saveFileToDownload(
          sourceFilePath: file.path,
          fileName: fileName,
          mimeType: 'application/zip');

      await file.delete();

      if (filePath != null) {
        SjLog.info('exportData: Saved to: $filePath');
        SjToast.show(L10n.of(navigatorKey.currentContext!).exportTo(filePath));
      } else {
        SjLog.info('exportData: Cancelled');
        SjToast.show(L10n.of(navigatorKey.currentContext!).commonCanceled);
      }
    }
  }

  Future<void> importData() async {
    SjLog.info('importData: start');
    if (!mounted) return;

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null) {
      return;
    }

    String? filePath = result.files.single.path;
    if (filePath == null) {
      SjLog.info('importData: cannot get file path');
      SjToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }

    File zipFile = File(filePath);
    if (!await zipFile.exists()) {
      SjLog.info('importData: zip file not found');
      SjToast.show(
          L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
      return;
    }
    _showDataDialog(L10n.of(navigatorKey.currentContext!).importing);

    String pathSeparator = Platform.pathSeparator;

    Directory cacheDir = await getSjTempDir();
    String cachePath = cacheDir.path;
    String extractPath = '$cachePath${pathSeparator}songjiang_reader_import';

    try {
      await Directory(extractPath).create(recursive: true);

      await compute(extractZipFile, {
        'zipFilePath': zipFile.path,
        'destinationPath': extractPath,
      });

      String docPath = await getSjDocumentsPath();
      _copyDirectorySync(Directory('$extractPath${pathSeparator}file'),
          getFileDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}cover'),
          getCoverDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}font'),
          getFontDir(path: docPath));
      _copyDirectorySync(Directory('$extractPath${pathSeparator}bgimg'),
          getBgimgDir(path: docPath));

      DBHelper.close();
      _copyDirectorySync(Directory('$extractPath${pathSeparator}databases'),
          await getSjDatabasesDir());
      DBHelper().initDB();

      await _restorePrefsFromBackup(extractPath);

      SjLog.info('importData: import success');
      SjToast.show(
          L10n.of(navigatorKey.currentContext!).importSuccessRestartApp);
    } catch (e) {
      SjLog.info('importData: error while unzipping or copying files: $e');
      SjToast.show(
          L10n.of(navigatorKey.currentContext!).importFailed(e.toString()));
    } finally {
      SmartDialog.dismiss();
      await Directory(extractPath).delete(recursive: true);
    }
  }

  void _copyDirectorySync(Directory source, Directory destination) {
    if (!source.existsSync()) {
      return;
    }
    if (destination.existsSync()) {
      destination.deleteSync(recursive: true);
    }
    destination.createSync(recursive: true);
    source.listSync(recursive: false).forEach((entity) {
      final newPath = destination.path +
          Platform.pathSeparator +
          path.basename(entity.path);
      if (entity is File) {
        entity.copySync(newPath);
      } else if (entity is Directory) {
        _copyDirectorySync(entity, Directory(newPath));
      }
    });
  }
}

Future<String> createZipFile(Map<String, dynamic> params) async {
  RootIsolateToken token = params['token'];
  final String prefsBackupFilePath = params['prefsBackupFilePath'];
  final File prefsBackupFile = File(prefsBackupFilePath);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final date =
      '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  final zipPath = '${(await getSjTempDir()).path}/SongJiang-Backup-$date.zip';
  final docPath = await getSjDocumentsPath();
  final directoryList = [
    getFileDir(path: docPath),
    getCoverDir(path: docPath),
    getFontDir(path: docPath),
    getBgimgDir(path: docPath),
    if (!SjPlatform.isOhos) await getSjDatabasesDir(),
    // await getSjSharedPrefsDir(),
    // await getSjSharedPrefsFile(),
    prefsBackupFile,
  ];

  SjLog.info('exportData: directoryList: $directoryList');

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  if (SjPlatform.isOhos) {
    final dbDir = await getSjDatabasesDir();
    final dbFile = File('${dbDir.path}/app_database.db');
    if (await dbFile.exists()) {
      await encoder.addFile(dbFile, 'databases/app_database.db');
    }
  } else {
    final dbDir = await getSjDatabasesDir();
    await encoder.addDirectory(dbDir);
  }

  for (final dir in directoryList) {
    if (dir is Directory) {
      await encoder.addDirectory(dir);
    } else if (dir is File) {
      await encoder.addFile(dir);
    }
  }
  encoder.close();
  if (await prefsBackupFile.exists()) {
    await prefsBackupFile.delete();
  }
  return zipPath;
}

Future<void> extractZipFile(Map<String, String> params) async {
  final zipFilePath = params['zipFilePath']!;
  final destinationPath = params['destinationPath']!;

  final input = InputFileStream(zipFilePath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    extractArchiveToDiskSync(archive, destinationPath);
    archive.clearSync();
  } finally {
    await input.close();
  }
}

Future<File> _createPrefsBackupFile() async {
  final Directory tempDir = await getSjTempDir();
  final File backupFile = File('${tempDir.path}/$_prefsBackupFileName');
  final Map<String, dynamic> prefsMap = await Prefs().buildPrefsBackupMap();
  await backupFile.writeAsString(jsonEncode(prefsMap));
  return backupFile;
}

Future<bool> _restorePrefsFromBackup(String extractPath) async {
  final File backupFile = File('$extractPath/$_prefsBackupFileName');
  if (!await backupFile.exists()) {
    return false;
  }
  try {
    final dynamic decoded = jsonDecode(await backupFile.readAsString());
    if (decoded is Map<String, dynamic>) {
      await Prefs().applyPrefsBackupMap(decoded);
      return true;
    }
    SjLog.info('importData: prefs backup has unexpected format');
  } catch (e) {
    SjLog.info('importData: failed to restore prefs backup: $e');
  }
  return false;
}

void showWebdavDialog(BuildContext context) {
  final title = L10n.of(context).settingsSyncWebdav;
  // final prefs = Prefs().saveWebdavInfo;
  final webdavInfo = SyncPrefs.getSyncInfo(SyncProtocol.webdav);
  final webdavUrlController = TextEditingController(text: webdavInfo['url']);
  final webdavUsernameController =
      TextEditingController(text: webdavInfo['username']);
  final webdavPasswordController =
      TextEditingController(text: webdavInfo['password']);
  Widget buildTextField(String labelText, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        obscureText: labelText == L10n.of(context).settingsSyncWebdavPassword
            ? true
            : false,
        controller: controller,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
        ),
      ),
    );
  }

  showDialog(
    context: context,
    builder: (context) {
      return SimpleDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(20),
        children: [
          buildTextField(
              L10n.of(context).settingsSyncWebdavUrl, webdavUrlController),
          buildTextField(L10n.of(context).settingsSyncWebdavUsername,
              webdavUsernameController),
          buildTextField(L10n.of(context).settingsSyncWebdavPassword,
              webdavPasswordController),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => SyncTestHelper.handleFullTestConnection(
                  context,
                  protocol: SyncProtocol.webdav,
                  config: {
                    'url': webdavUrlController.text.trim(),
                    'username': webdavUsernameController.text,
                    'password': webdavPasswordController.text,
                  },
                ),
                icon: const Icon(Icons.wifi_find),
                label: Text(L10n.of(context).settingsSyncWebdavTestConnection),
              ),
              TextButton(
                onPressed: () {
                  webdavInfo['url'] = webdavUrlController.text.trim();
                  webdavInfo['username'] = webdavUsernameController.text;
                  webdavInfo['password'] = webdavPasswordController.text;
                  SyncPrefs.setSyncInfo(SyncProtocol.webdav, webdavInfo);
                  SyncClientFactory.initializeCurrentClient();
                  Navigator.pop(context);
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          ),
        ],
      );
    },
  );
}
