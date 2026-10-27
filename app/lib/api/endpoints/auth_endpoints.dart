import 'package:dio/dio.dart';

import '../../models/auth_user.dart';

class InviteEntry {
  final String id;
  final String code;
  final String note;
  final bool used;

  InviteEntry({required this.id, required this.code, required this.note, required this.used});

  static InviteEntry fromJson(Map<String, dynamic> j) => InviteEntry(
        id: j['id']?.toString() ?? '',
        code: j['code']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
        used: j['used'] == true,
      );
}

class AccountEntry {
  final String id;
  final String username;
  final String email;
  final String role;
  final bool active;

  AccountEntry({required this.id, required this.username, required this.email, required this.role, required this.active});

  static AccountEntry fromJson(Map<String, dynamic> j) => AccountEntry(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        role: j['role']?.toString() ?? 'user',
        active: j['active'] != false,
      );
}

class AuthEndpoints {
  final Dio dio;

  AuthEndpoints(this.dio);

  Future<AuthUser> register({
    required String username,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final res = await dio.post(
      '/api/auth/register',
      data: {
        'username': username,
        'email': email,
        'password': password,
        'invite_code': inviteCode,
      },
    );
    return AuthUser.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<AuthUser> login({
    required String identifier,
    required String password,
  }) async {
    final res = await dio.post(
      '/api/auth/login',
      data: {
        'identifier': identifier,
        'password': password,
      },
    );
    return AuthUser.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<List<InviteEntry>> listInvites() async {
    final res = await dio.get('/api/auth/invites');
    final raw = res.data;
    final list = <InviteEntry>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(InviteEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return list;
  }

  Future<InviteEntry> createInvite({String code = '', String note = ''}) async {
    final res = await dio.post('/api/auth/invites', data: {'code': code, 'note': note});
    return InviteEntry.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<void> deleteInvite(String id) async {
    await dio.delete('/api/auth/invites/$id');
  }

  Future<String> changePassword({required String oldPassword, required String newPassword}) async {
    final res = await dio.post(
      '/api/auth/change-password',
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
    return (res.data as Map)['token']?.toString() ?? '';
  }

  Future<void> revokeAllTokens() async {
    await dio.post('/api/auth/revoke-all');
  }

  Future<List<AccountEntry>> listAccounts() async {
    final res = await dio.get('/api/auth/users');
    final raw = res.data;
    final list = <AccountEntry>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(AccountEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return list;
  }

  Future<void> setAccountActive(String id, bool active) async {
    await dio.patch('/api/auth/users/$id/active', data: {'active': active});
  }

  Future<void> deleteAccount(String id) async {
    await dio.delete('/api/auth/users/$id');
  }

  Future<String> resetAccountPassword(String id) async {
    final res = await dio.post('/api/auth/users/$id/reset-password');
    return (res.data as Map)['temp_password']?.toString() ?? '';
  }
}
