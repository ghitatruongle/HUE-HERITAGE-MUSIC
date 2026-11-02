import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../core/localization/app_strings.dart';

class AuthService extends ChangeNotifier {
  static const String _tokenKey = 'hue_auth_token';
  static const String _userKey = 'hue_auth_user';
  static const String _emailKey = 'hue_auth_email';
  static const String _roleKey = 'hue_auth_role';
  static const String _mcpKey = 'hue_auth_mcp';
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
  bool _mustChangePassword = false;
  bool _sessionExpiredNotice = false;
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
  bool get mustChangePassword => _mustChangePassword;
  bool get sessionExpiredNotice => _sessionExpiredNotice;

  void consumeSessionExpiredNotice() {
    _sessionExpiredNotice = false;
  }

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
    String mcp = '0';
    try {
      token = await _storage.read(key: _tokenKey);
      username = await _storage.read(key: _userKey);
      email = await _storage.read(key: _emailKey);
      role = await _storage.read(key: _roleKey) ?? 'user';
      mcp = await _storage.read(key: _mcpKey) ?? '0';
      if (token == null || token.isEmpty) {
        await _migrateLegacyFile(token: token, username: username, email: email, role: role, seq: seq);
        return;
      }
    } catch (_) {
      token = null;
      username = null;
      email = null;
      role = 'user';
      mcp = '0';
    }
    if (seq != _stateSeq) {
      return;
    }
    _token = token;
    _username = username;
    _email = email;
    _role = role;
    _mustChangePassword = mcp == '1';
    await _probeSecureStorage();
    if (seq != _stateSeq) {
      return;
    }
    _isGuest = false;
    _loaded = true;
    _currentToken = _token;
    notifyListeners();
  }

  Future<void> validateSession(String serverUrl, {Dio? dio}) async {
    final token = _token;
    if (token == null || token.isEmpty || _isGuest || serverUrl.isEmpty) {
      return;
    }
    final seq = _stateSeq;
    try {
      final client = dio ??
          Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ));
      client.options.validateStatus = (code) => code != null && code < 500;
      final res = await client.get(
        '$serverUrl/api/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (seq != _stateSeq) {
        return;
      }
      if (res.statusCode == 200 && res.data is Map) {
        final data = Map<String, dynamic>.from(res.data as Map);
        _username = (data['username'] ?? _username ?? '').toString();
        _email = (data['email'] ?? _email ?? '').toString();
        _role = (data['role'] ?? _role).toString() == 'admin' ? 'admin' : 'user';
        _mustChangePassword = data['must_change_password'] == true;
        final fresh = (data['token'] ?? '').toString();
        if (fresh.isNotEmpty) {
          _token = fresh;
        }
        _currentToken = _token;
        notifyListeners();
        try {
          if (fresh.isNotEmpty) {
            await _storage.write(key: _tokenKey, value: fresh);
          }
          await _storage.write(key: _userKey, value: _username ?? '');
          await _storage.write(key: _emailKey, value: _email ?? '');
          await _storage.write(key: _roleKey, value: _role);
          await _storage.write(key: _mcpKey, value: _mustChangePassword ? '1' : '0');
        } on PlatformException {
          _secureStorageBroken = true;
        } catch (_) {}
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        _sessionExpiredNotice = true;
        await clearToken();
      }
    } catch (_) {}
  }

  Future<void> _migrateLegacyFile({String? token, String? username, String? email, String? role, int? seq}) async {
    if (kIsWeb) {
      _finishLoad(seq: seq, token: null, username: null, email: null, role: role);
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
    _finishLoad(seq: seq, token: token, username: username, email: email, role: role);
  }

  void _finishLoad({int? seq, String? token, String? username, String? email, String? role}) {
    if (seq != null && seq != _stateSeq) {
      return;
    }
    _token = token;
    _username = username;
    _email = email;
    _role = role ?? 'user';
    _mustChangePassword = false;
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

  void continueAsGuest({String? displayName}) {
    _token = null;
    _username = displayName ?? const AppStrings('vi').authGuestUsername;
    _email = null;
    _isGuest = true;
    _mustChangePassword = false;
    _currentToken = null;
    notifyListeners();
  }

  Future<void> save({
    required String token,
    required String username,
    String? email,
    String role = 'user',
    bool mustChangePassword = false,
  }) async {
    _stateSeq++;
    _token = token;
    _username = username;
    _email = email ?? '';
    _role = role == 'admin' ? 'admin' : 'user';
    _isGuest = false;
    _mustChangePassword = mustChangePassword;
    _sessionExpiredNotice = false;
    _currentToken = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _userKey, value: username);
      await _storage.write(key: _emailKey, value: email ?? '');
      await _storage.write(key: _roleKey, value: _role);
      await _storage.write(key: _mcpKey, value: _mustChangePassword ? '1' : '0');
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
    _mustChangePassword = false;
    _currentToken = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _roleKey);
      await _storage.delete(key: _mcpKey);
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
