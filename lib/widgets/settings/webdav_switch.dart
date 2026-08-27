import 'package:songjiang_reader/config/shared_preference_provider.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/providers/sync.dart';
import 'package:songjiang_reader/utils/webdav/test_webdav.dart';
import 'package:songjiang_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

AbstractSettingsTile webdavSwitch(
    BuildContext context, Function setState, WidgetRef ref) {
  return SettingsTile.switchTile(
    leading: const Icon(Icons.cached),
    initialValue: Prefs().webdavStatus,
    onToggle: (bool value) async {
      setState(() {
        Prefs().saveWebdavStatus(value);
      });
      if (value) {
        bool result = await testEnableWebdav();
        if (!result) {
          setState(() {
            Prefs().saveWebdavStatus(!value);
          });
        } else {
          Sync().init();
          chooseDirection(ref);
        }
      }
    },
    title: Text(L10n.of(context).settingsSyncEnableWebdav),
  );
}
