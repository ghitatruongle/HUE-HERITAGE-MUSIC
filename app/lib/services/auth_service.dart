import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class AuthService extends ChangeNotifier {
  static const String _tokenKey = 'hue_auth_token';
  static const String _userKey = 'hue_auth_user';
  static const String _emailKey = 'hue_auth_email';
  static const String _legacyFileName = '.hue_auth.json';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static AuthService? _instance;
  static String? _currentToken;

  String? _token;
  String? _username;
  String? _email;
  bool _isGuest = false;
  bool _loaded = false;

  AuthService() {
    _instance = this;
    _currentToken = _token;
    load();
  }

  static String? get currentToken => _currentToken;
  static AuthService? get instance => _instance;

  String? get token => _token;
  String? get username => _username;
  String? get email => _email;
  bool get isGuest => _isGuest;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty && !_isGuest;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      _username = await _storage.read(key: _userKey);
      _email = await _storage.read(key: _emailKey);
      if (_token == null || _token!.isEmpty) {
        await _migrateLegacyFile();
      }
    } catch (_) {
      _token = null;
      _username = null;
      _email = null;
    }
    _isGuest = false;
    _loaded = true;
    _currentToken = _token;
    notifyListeners();
  }

  Future<void> _migrateLegacyFile() async {
    if (kIsWeb) {
      return;
    }
    for (final path in await _legacyPaths()) {
      try {
        final f = File(path);
        if (!f.existsSync()) {
          continue;
        }
        final data = jsonDecode(f.readAsStringSync());
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          _token = token;
          _username = data['username'] as String?;
          _email = data['email'] as String?;
          await _storage.write(key: _tokenKey, value: token);
          await _storage.write(key: _userKey, value: _username ?? '');
          await _storage.write(key: _emailKey, value: _email ?? '');
        }
        f.deleteSync();
      } catch (_) {
        continue;
      }
    }
  }

  Future<List<String>> _legacyPaths() async {
    final paths = <String>['./$_legacyFileName'];
    try {
      final dir = await getApplicationSupportDirectory();
      paths.insert(0, '${dir.path}/$_legacyFileName');
    } catch (_) {}
    return paths;
  }

  void continueAsGuest({String displayName = 'Khách'}) {
    _token = null;
    _username = displayName;
    _email = null;
    _isGuest = true;
    _currentToken = null;
    notifyListeners();
  }

  Future<void> save({required String token, required String username, String? email}) async {
    _token = token;
    _username = username;
    _email = email ?? '';
    _isGuest = false;
    _currentToken = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey, value: username);
      await _storage.write(key: _emailKey, value: email ?? '');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clearToken() async {
    _token = null;
    _username = null;
    _email = null;
    _isGuest = false;
    _currentToken = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _emailKey);
    } catch (_) {}
    if (!kIsWeb) {
      for (final path in await _legacyPaths()) {
        try {
          final f = File(path);
          if (f.existsSync()) {
            f.deleteSync();
          }
        } catch (_) {}
      }
    }
    notifyListeners();
  }
}
