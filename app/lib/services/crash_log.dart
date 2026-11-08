import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CrashLog {
  static const int _maxBytes = 256 * 1024;
  static const int _keepFiles = 5;
  static Future<void>? _pending;
  static bool _flushed = false;

  static Future<void> write(String message) async {
    if (kIsWeb) {
      return;
    }
    final prev = _pending;
    final done = Completer<void>();
    _pending = done.future;
    try {
      await prev;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/hue_crash_log.txt');
      if (await file.exists() && await file.length() > _maxBytes) {
        await _rotate(dir, file);
      }
      final stamp = DateTime.now().toIso8601String();
      await file.writeAsString('[$stamp] $message\n', mode: FileMode.append);
    } catch (_) {
    } finally {
      done.complete();
    }
  }

  static Future<void> _rotate(Directory dir, File file) async {
    try {
      final oldest = File('${dir.path}/hue_crash_log.$_keepFiles.txt');
      if (await oldest.exists()) {
        await oldest.delete();
      }
      for (var i = _keepFiles - 1; i >= 1; i--) {
        final f = File('${dir.path}/hue_crash_log.$i.txt');
        if (await f.exists()) {
          await f.rename('${dir.path}/hue_crash_log.${i + 1}.txt');
        }
      }
      await file.rename('${dir.path}/hue_crash_log.1.txt');
    } catch (_) {}
  }

  static Future<void> flushToServer(Dio dio, String appVersion, String platform) async {
    if (kIsWeb || _flushed) {
      return;
    }
    _flushed = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/hue_crash_log.txt');
      if (!await file.exists()) {
        return;
      }
      String content = await file.readAsString();
      if (content.trim().isEmpty) {
        return;
      }
      final bytes = utf8.encode(content);
      if (bytes.length > _maxBytes) {
        content = utf8.decode(bytes.sublist(bytes.length - _maxBytes + 8), allowMalformed: true);
      }
      final lastLine = content.trim().split('\n').last;
      final summary = lastLine.length > 200 ? lastLine.substring(0, 200) : lastLine;
      await dio.post('/api/crash-reports', data: {
        'app_version': appVersion,
        'platform': platform,
        'summary': summary,
        'detail': content,
      });
      await file.writeAsString('', mode: FileMode.write);
    } catch (_) {}
  }
}
