import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../api/api_client.dart';
import '../core/constants/app_constants.dart';

class ServerConfig extends ChangeNotifier {
  static const String _configAsset = 'GHITA_API.json';

  String _baseUrl = AppConstants.defaultServerUrl;
  ApiClient _api = ApiClient();

  String get baseUrl => _baseUrl;
  ApiClient get api => _api;

  static String normalize(String raw) {
    var cleaned = raw.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isEmpty) {
      return AppConstants.defaultServerUrl;
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
    if (url == null || url.trim().isEmpty) {
      return;
    }
    _baseUrl = normalize(url);
    _api = ApiClient(baseUrl: _baseUrl);
    notifyListeners();
  }

  Future<String?> _readConfigUrl() async {
    try {
      if (kIsWeb) {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          responseType: ResponseType.plain,
        ));
        final res = await dio.get(_configAsset);
        final data = jsonDecode(res.data.toString());
        if (data is Map) {
          return data['server_url']?.toString();
        }
        return null;
      }
      final raw = await rootBundle.loadString(_configAsset);
      final data = jsonDecode(raw);
      if (data is Map) {
        return data['server_url']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
