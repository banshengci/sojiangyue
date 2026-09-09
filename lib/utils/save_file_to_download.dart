import 'dart:io';
import 'package:songjiang_reader/utils/platform_utils.dart';

import 'package:songjiang_reader/utils/get_path/get_download_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

Future<String?> saveFileToDownload(
    {Uint8List? bytes,
    String? sourceFilePath,
    required String fileName,
    String? mimeType}) async {
  String downloadPath = await getDownloadPath();
  String fileSavePath = '$downloadPath/$fileName';

  switch (SjPlatform.type) {
    case SjPlatformEnum.android:
    case SjPlatformEnum.ios:
    case SjPlatformEnum.ohos:
      SaveFileDialogParams params = SaveFileDialogParams(
        sourceFilePath: sourceFilePath,
        data: bytes,
        mimeTypesFilter: [mimeType ?? 'application/zip'],
        fileName: fileName,
      );
      final filePath = await FlutterFileDialog.saveFile(params: params);
      return filePath;
    case SjPlatformEnum.macos:
      String? outputFile = await FilePicker.platform.saveFile(
        fileName: fileName,
      );
      bytes ??= await File(sourceFilePath!).readAsBytes();
      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        return outputFile;
      }
      return outputFile;
    case SjPlatformEnum.windows:
      final file = File(fileSavePath);

      if (!await file.exists()) {
        await file.create(recursive: true);
      }

      bytes ??= await File(sourceFilePath!).readAsBytes();
      await file.writeAsBytes(bytes);
      return fileSavePath;
  }
}
