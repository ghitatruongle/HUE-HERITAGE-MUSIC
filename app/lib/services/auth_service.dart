import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class AuthService extends ChangeNotifier {
  static const String _tokenKey = 'hue_auth_token';
  static const String _userKey = 'hue_auth_user';
  static const String _emailKey = 'hue_auth_email';
  static const String _roleKey = 'hue_auth_role';
  static const String _legacyFileName = '.hue_auth.json';
  static const String _probeKey = 'hue_storage_probe';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static AuthService? _instance;
  static String? _currentToken;

  String? _token;
  String? _username;
  String? _email;
  String _role = 'user';
  bool _isGuest = false;
  bool _loaded = false;
  bool _secureStorageBroken = false;
  int _stateSeq = 0;

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
  String get role => _role;
  bool get isAdmin => _role == 'admin' && !_isGuest;
  bool get isGuest => _isGuest;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty && !_isGuest;
  bool get isLoaded => _loaded;
  bool get secureStorageBroken => _secureStorageBroken;

  Future<void> _probeSecureStorage() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _storage.write(key: _probeKey, value: 'ok');
      final check = await _storage.read(key: _probeKey);
      await _storage.delete(key: _probeKey);
      if (check != 'ok') {
        _secureStorageBroken = true;
      }
    } on PlatformException {
      _secureStorageBroken = true;
    } catch (_) {}
  }

  Future<void> load() async {
    final seq = _stateSeq;
    String? token;
    String? username;
    String? email;
    String role = 'user';
    try {
      token = await _storage.read(key: _tokenKey);
      username = await _storage.read(key: _userKey);
      email = await _storage.read(key: _emailKey);
      role = await _storage.read(key: _roleKey) ?? 'user';
      if (token == null || token.isEmpty) {
        await _migrateLegacyFile(token: token, username: username, email: email, role: role, seq: seq);
        return;
      }
    } catch (_) {
      token = null;
      username = null;
      email = null;
      role = 'user';
    }
    if (seq != _stateSeq) {
      return;
    }
    _token = token;
    _username = username;
    _email = email;
    _role = role;
    await _probeSecureStorage();
    if (seq != _stateSeq) {
      return;
    }
    _isGuest = false;
    _loaded = true;
    _currentToken = _token;
    notifyListeners();
  }

  Future<void> _migrateLegacyFile({String? token, String? username, String? email, String? role, int? seq}) async {
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
        final legacyToken = data['token'] as String?;
        if (legacyToken != null && legacyToken.isNotEmpty) {
          token = legacyToken;
          username = data['username'] as String? ?? username;
          email = data['email'] as String? ?? email;
          await _storage.write(key: _tokenKey, value: legacyToken);
          await _storage.write(key: _userKey, value: username ?? '');
          await _storage.write(key: _emailKey, value: email ?? '');
        }
        f.deleteSync();
      } catch (_) {
        continue;
      }
    }
    if (seq != null && seq != _stateSeq) {
      return;
    }
    _token = token;
    _username = username;
    _email = email;
    _role = role ?? 'user';
    _isGuest = false;
    _loaded = true;
    _currentToken = _token;
    notifyListeners();
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

  Future<void> save({required String token, required String username, String? email, String role = 'user'}) async {
    _stateSeq++;
    _token = token;
    _username = username;
    _email = email ?? '';
    _role = role == 'admin' ? 'admin' : 'user';
    _isGuest = false;
    _currentToken = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey, value: username);
      await _storage.write(key: _emailKey, value: email ?? '');
      await _storage.write(key: _roleKey, value: _role);
    } on PlatformException {
      _secureStorageBroken = true;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clearToken() async {
    _stateSeq++;
    _token = null;
    _username = null;
    _email = null;
    _role = 'user';
    _isGuest = false;
    _currentToken = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _roleKey);
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
