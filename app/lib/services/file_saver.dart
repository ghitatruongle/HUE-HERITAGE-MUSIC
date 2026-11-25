import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

Future<void> shareDownloadedFile(String path, String fileName) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    return;
  }
  if (!await File(path).exists()) {
    return;
  }
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path)], title: fileName, fileNameOverrides: [fileName]),
  );
  try {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {}
}
