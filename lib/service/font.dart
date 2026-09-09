import 'dart:io';

import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/main.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:file_picker/file_picker.dart';

Future<void> importFont() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['ttf', 'otf'],
    allowMultiple: true,
  );

  if (result == null) {
    return;
  }

  List<PlatformFile> files = result.files;
  for (var file in files) {
    final fontDir = getFontDir();
    File newFile = File(file.path!);
    newFile.copy('${fontDir.path}/${file.name}');

    SjToast.show(L10n.of(navigatorKey.currentContext!).commonSuccess);
  }
}
