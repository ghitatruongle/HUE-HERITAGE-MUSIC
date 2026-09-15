import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../api/api_client.dart';

class ServerConfig extends ChangeNotifier {
  static const String _configAsset = 'GHITA_API.json';
  static const String _exampleAsset = 'GHITA_API.example.json';

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
    _baseUrl = normalize(url ?? '');
    _api = ApiClient(baseUrl: _baseUrl);
    notifyListeners();
  }

  Future<String?> _readConfigUrl() async {
    for (final asset in [_configAsset, _exampleAsset]) {
      try {
        final raw = await _readAsset(asset);
        if (raw == null) continue;
        final data = jsonDecode(raw);
        if (data is Map) {
          final url = data['server_url']?.toString();
          if (url != null && url.trim().isNotEmpty && url != 'http://192.0.2.10:8000') {
            return url;
          }
        }
      } catch (_) {
        continue;
      }
    }
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
