import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../api/api_client.dart';

class ServerConfig extends ChangeNotifier {
  static const String _configAsset = 'GHITA_API.json';
  static const String _exampleAsset = 'GHITA_API.example.json';
  static const String _placeholderUrl = 'http://192.0.2.10:8000';

  String _baseUrl = '';
  ApiClient _api = ApiClient();

  String get baseUrl => _baseUrl;
  ApiClient get api => _api;
  bool get hasServer => _baseUrl.isNotEmpty;

  static String normalize(String raw) {
    var cleaned = raw.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isEmpty) {
      return '';
    }
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      cleaned = 'http://$cleaned';
    }
    while (cleaned.endsWith('/api')) {
      cleaned = cleaned.substring(0, cleaned.length - 4);
    }
    return cleaned;
  }

  Future<void> load() async {
    final url = await _readConfigUrl();
    var normalized = normalize(url ?? '');
    if (kIsWeb) {
      if (normalized.isEmpty ||
          normalized.contains('127.0.0.1') ||
          normalized.contains('localhost')) {
        normalized = normalize(Uri.base.origin);
      }
    }
    _baseUrl = normalized;
    _api = ApiClient(baseUrl: _baseUrl);
    notifyListeners();
  }

  Future<String?> _readConfigUrl() async {
    if (!kIsWeb) {
      final localUrl = await _readLocalFileUrl();
      if (localUrl != null) {
        return localUrl;
      }
    }
    for (final asset in [_configAsset, _exampleAsset]) {
      try {
        final raw = await _readAsset(asset);
        if (raw == null) continue;
        final url = _extractUrl(raw);
        if (url != null) {
          return url;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<String?> _readLocalFileUrl() async {
    final dirs = <String>[
      File(Platform.resolvedExecutable).parent.path,
      Directory.current.path,
    ];
    for (final dir in dirs) {
      try {
        final file = File('$dir/$_configAsset');
        if (!file.existsSync()) {
          continue;
        }
        final url = _extractUrl(await file.readAsString());
        if (url != null) {
          return url;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? _extractUrl(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        final url = data['server_url']?.toString();
        if (url != null && url.trim().isNotEmpty && url != _placeholderUrl) {
          return url;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _readAsset(String asset) async {
    if (kIsWeb) {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.plain,
      ));
      final res = await dio.get(asset);
      return res.data?.toString();
    }
    return rootBundle.loadString(asset);
  }
}
