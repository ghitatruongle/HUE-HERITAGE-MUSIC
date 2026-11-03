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
  final bool mustChangePassword;

  AccountEntry({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.active,
    this.mustChangePassword = false,
  });

  static AccountEntry fromJson(Map<String, dynamic> j) => AccountEntry(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        role: j['role']?.toString() ?? 'user',
        active: j['active'] != false,
        mustChangePassword: j['must_change_password'] == true,
      );
}

class CreatedAccount {
  final String id;
  final String username;
  final String email;
  final String tempPassword;
  final bool generated;

  CreatedAccount({
    required this.id,
    required this.username,
    required this.email,
    required this.tempPassword,
    required this.generated,
  });

  static CreatedAccount fromJson(Map<String, dynamic> j) => CreatedAccount(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        tempPassword: j['temp_password']?.toString() ?? '',
        generated: j['generated'] == true,
      );
}

class AccountPage {
  final List<AccountEntry> items;
  final int total;

  AccountPage({required this.items, required this.total});
}

class InvitePage {
  final List<InviteEntry> items;
  final int total;

  InvitePage({required this.items, required this.total});
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

  Future<InvitePage> listInvites({int limit = 50, int offset = 0}) async {
    final res = await dio.get(
      '/api/auth/invites',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final raw = res.data;
    final list = <InviteEntry>[];
    int total = 0;
    if (raw is Map) {
      total = raw['total'] is num ? (raw['total'] as num).toInt() : 0;
      final items = raw['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            list.add(InviteEntry.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
    }
    return InvitePage(items: list, total: total);
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

  Future<AccountPage> listAccounts({int limit = 50, int offset = 0}) async {
    final res = await dio.get(
      '/api/auth/users',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final raw = res.data;
    final list = <AccountEntry>[];
    int total = 0;
    if (raw is Map) {
      total = raw['total'] is num ? (raw['total'] as num).toInt() : 0;
      final items = raw['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            list.add(AccountEntry.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
    }
    return AccountPage(items: list, total: total);
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

  Future<void> adminUnlock(String password) async {
    await dio.post('/api/auth/admin-unlock', data: {'password': password});
  }

  Future<CreatedAccount> createUser({
    required String username,
    String email = '',
    String password = '',
    String note = '',
  }) async {
    final res = await dio.post(
      '/api/auth/users',
      data: {'username': username, 'email': email, 'password': password, 'note': note},
    );
    return CreatedAccount.fromJson(Map<String, dynamic>.from(res.data as Map));
  }
}
