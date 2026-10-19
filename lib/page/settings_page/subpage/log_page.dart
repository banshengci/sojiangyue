import 'dart:io';

import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/utils/save_file_to_download.dart';
import 'package:songjiang_reader/utils/get_path/log_file.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<String> logs = [];

  @override
  void initState() {
    initData();
    super.initState();
  }

  Future<void> initData() async {
    File logFile = await getLogFile();
    setState(() {
      logs = logFile.readAsLinesSync().reversed.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).settingsAdvancedLog),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              initData();
            },
          ),
          IconButton(
              onPressed: () => showMoreAction(context),
              icon: const Icon(Icons.more_vert)),
        ],
      ),
      body: ListView(
        children: [for (final log in logs) logItem(log, context)],
      ),
    );
  }

  /// 弹出菜单里的一行：图标 + 文案。
  ///
  /// 不用 ListTile 是有原因的——PopupMenuItem 自带带底色的 DecoratedBox，
  /// 套 ListTile 会盖住水波纹，debug 下每次打开菜单都报一条断言。
  Widget _menuRow({required IconData icon, required String label}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }

  void showMoreAction(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).padding.top + kToolbarHeight,
        0.0,
        0.0,
      ),
      items: [
        // 不要在 PopupMenuItem 里套 ListTile：PopupMenuItem 内部是带底色的
        // DecoratedBox，ListTile 的水波纹会被盖住，debug 下每次打开菜单都会报
        // 「ListTile background color or ink splashes may be invisible」。
        PopupMenuItem<VoidCallback>(
          value: clearLog,
          onTap: clearLog,
          child: _menuRow(
            icon: Icons.delete,
            label: L10n.of(context).settingsAdvancedLogClearLog,
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: exportLog,
          onTap: exportLog,
          child: _menuRow(
            icon: Icons.file_upload_outlined,
            label: L10n.of(context).settingsAdvancedLogExportLog,
          ),
        ),
      ],
    );
  }

  Future<void> clearLog() async {
    SjLog.clear();
    initData();
  }

  Future<void> exportLog() async {
    File logFile = await getLogFile();
    // SaveFileDialogParams params = SaveFileDialogParams(
    //   sourceFilePath: logFile.path,
    // );
    // await FlutterFileDialog.saveFile(params: params);
    String fileName =
        'SongJiang-Log-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}.txt';
    String? filePath = await saveFileToDownload(
        bytes: await logFile.readAsBytes(),
        fileName: fileName,
        mimeType: 'text/plain');

    SjToast.show("saved $filePath");
  }
}

Widget logItem(String logStr, BuildContext context) {
  final log = SjLog.parse(logStr);
  return SelectionArea(
      child: Container(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
          decoration: BoxDecoration(
            color: log.color,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(log.level.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ),
        Text(log.time.toString()),
        const SizedBox(height: 5),
        Text(log.message),
        Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: logStr));
              },
              child: Text(L10n.of(context).commonCopy),
            ),
          ],
        ),
        const Divider(),
      ],
    ),
  ));
}
