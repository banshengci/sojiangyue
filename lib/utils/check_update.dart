import 'package:songjiang_reader/config/remote_config.dart';
import 'package:songjiang_reader/config/app_misc_prefs.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/utils/app_version.dart';
import 'package:songjiang_reader/utils/env_var.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/markdown/styled_markdown.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// 检查应用更新。
///
/// 优先从 [RemoteConfig.updateApiUrl]（默认指向 GitHub Releases API）拉取最新版本信息，
/// 通过 [RemoteConfig.updateDownloadUrl] 提供下载入口。
/// 完全由 dart-define 在构建时配置，未配置则本函数直接返回。
Future<void> checkUpdate(bool manualCheck) async {
  if (!EnvVar.enableCheckUpdate) {
    return;
  }
  final apiUrl = RemoteConfig.updateApiUrl;
  if (apiUrl == null) {
    if (manualCheck) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        SjToast.show(L10n.of(ctx).commonFailed);
      }
    }
    return;
  }
  // if is today
  if (!manualCheck &&
      DateTime.now().difference(AppMiscPrefs.lastShowUpdate) <
          const Duration(days: 1)) {
    return;
  }
  AppMiscPrefs.lastShowUpdate = DateTime.now();

  Response response;
  try {
    response = await Dio().get(apiUrl);
  } catch (e) {
    if (manualCheck) {
      // 网络等待期间用户可能已离开当前页面，故在使用点重新取 context 并判断可用性，
      // 不要用 await 之前捕获的陈旧 context。
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        SjToast.show(L10n.of(ctx).commonFailed);
      }
    }
    SjLog.severe('Update: Failed to check for updates $e');
    return;
  }

  // 解析响应：GitHub Releases API（tag_name + body）或自定义 JSON（version + body）。
  String? newVersion;
  String body = '';
  final data = response.data;
  if (data is Map) {
    newVersion = (data['tag_name'] ?? data['version'])?.toString();
    body = (data['body'] ?? '').toString();
  }
  if (newVersion == null || newVersion.isEmpty) {
    SjLog.severe('Update: invalid response payload');
    if (manualCheck) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        SjToast.show(L10n.of(ctx).commonFailed);
      }
    }
    return;
  }

  // 去掉开头的 'v'（如 "v1.2.3" -> "1.2.3"）
  if (newVersion.startsWith('v') || newVersion.startsWith('V')) {
    newVersion = newVersion.substring(1);
  }
  String currentVersion = (await getAppVersion()).split('+').first;
  SjLog.info('Update: new version $newVersion');

  List<String> newVersionList = newVersion.split('.');
  List<String> currentVersionList = currentVersion.split('.');
  // 容错：版本段数不等时补 0
  while (newVersionList.length < currentVersionList.length) {
    newVersionList.add('0');
  }
  while (currentVersionList.length < newVersionList.length) {
    currentVersionList.add('0');
  }
  SjLog.info(
      'Current version: $currentVersionList, New version: $newVersionList');
  bool needUpdate = false;
  for (int i = 0; i < newVersionList.length; i++) {
    int newVer = int.tryParse(newVersionList[i]) ?? 0;
    int curVer = int.tryParse(currentVersionList[i]) ?? 0;
    if (newVer > curVer) {
      needUpdate = true;
      break;
    } else if (newVer < curVer) {
      needUpdate = false;
      break;
    }
  }

  if (needUpdate) {
    if (manualCheck) {
      // 「手动检查」时外层会先弹出一个加载对话框，这里关掉它。
      // 若等待期间该对话框已随页面一起销毁，pop 会误关其它路由，故先确认 navigator 可用。
      final nav = navigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
      }
    }
    SmartDialog.show(
      builder: (BuildContext context) {
        final cleanBody = body.split('\n').skip(1).join('\n');
        final downloadUrl = RemoteConfig.updateDownloadUrl;
        return AlertDialog(
          title: Text(L10n.of(context).commonNewVersion,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              )),
          content: SingleChildScrollView(
            child: StyledMarkdown(
                data: '''### ${L10n.of(context).updateNewVersion} $newVersion\n
${L10n.of(context).updateCurrentVersion} $currentVersion\n
$cleanBody'''),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
              },
              child: Text(L10n.of(context).commonCancel),
            ),
            if (downloadUrl.isNotEmpty)
              TextButton(
                onPressed: () {
                  launchUrl(Uri.parse(downloadUrl),
                      mode: LaunchMode.externalApplication);
                },
                child: Text(L10n.of(context).updateViaGithub),
              ),
          ],
        );
      },
    );
  } else {
    if (manualCheck) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        SjToast.show(L10n.of(ctx).commonNoNewVersion);
      }
    }
  }
}