import 'package:dio/dio.dart';

import '../../models/auth_user.dart';
import '../api_client.dart';

class InviteEntry {
  final String id;
  final String code;
  final String note;
  final bool used;
  final int maxUses;
  final int usedCount;
  final int? remainingUses;
  final bool expired;
  final bool active;
  final DateTime? expiresAt;

  InviteEntry({
    required this.id,
    required this.code,
    required this.note,
    required this.used,
    this.maxUses = 1,
    this.usedCount = 0,
    this.remainingUses,
    this.expired = false,
    this.active = true,
    this.expiresAt,
  });

  static InviteEntry fromJson(Map<String, dynamic> j) {
    final maxUses = j['max_uses'] is num ? (j['max_uses'] as num).toInt() : 1;
    final usedFlag = j['used'] == true;
    final usedCount = j['used_count'] is num ? (j['used_count'] as num).toInt() : (usedFlag ? 1 : 0);
    final remainingUses = j['remaining_uses'] is num
        ? (j['remaining_uses'] as num).toInt()
        : (maxUses == 0 ? null : (maxUses - usedCount).clamp(0, maxUses));
    final expired = j['expired'] == true;
    final active = j.containsKey('active') ? j['active'] == true : (!usedFlag && !expired);
    final rawExpires = j['expires_at']?.toString();
    final expiresAt = rawExpires != null && rawExpires.isNotEmpty ? DateTime.tryParse(rawExpires)?.toLocal() : null;
    return InviteEntry(
      id: j['id']?.toString() ?? '',
      code: j['code']?.toString() ?? '',
      note: j['note']?.toString() ?? '',
      used: usedFlag,
      maxUses: maxUses,
      usedCount: usedCount,
      remainingUses: remainingUses,
      expired: expired,
      active: active,
      expiresAt: expiresAt,
    );
  }
}

class AccountEntry {
  final String id;
  final String username;
  final String email;
  final String role;
  final bool active;
  final bool mustChangePassword;
  final String avatar;

  AccountEntry({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.active,
    this.mustChangePassword = false,
    this.avatar = '',
  });

  static AccountEntry fromJson(Map<String, dynamic> j) => AccountEntry(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        role: j['role']?.toString() ?? 'user',
        active: j['active'] != false,
        mustChangePassword: j['must_change_password'] == true,
        avatar: j['avatar']?.toString() ?? '',
      );
}

class CreatedAccount {
  final String id;
  final String username;
  final String email;
  final String tempPassword;
  final bool generated;
  final String role;

  CreatedAccount({
    required this.id,
    required this.username,
    required this.email,
    required this.tempPassword,
    required this.generated,
    this.role = 'user',
  });

  static CreatedAccount fromJson(Map<String, dynamic> j) => CreatedAccount(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        tempPassword: j['temp_password']?.toString() ?? '',
        generated: j['generated'] == true,
        role: j['role']?.toString() ?? 'user',
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
    return AuthUser.fromJson(ApiClient.requireMap(res.data, res.requestOptions));
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
    return AuthUser.fromJson(ApiClient.requireMap(res.data, res.requestOptions));
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

  Future<InviteEntry> createInvite({
    String code = '',
    String note = '',
    int maxUses = 1,
    int? expiresMinutes,
    double? expiresHours,
  }) async {
    final body = <String, dynamic>{
      'code': code,
      'note': note,
      'max_uses': maxUses,
      if (expiresMinutes != null) 'expires_minutes': expiresMinutes,
      if (expiresHours != null) 'expires_hours': expiresHours,
    };
    final res = await dio.post('/api/auth/invites', data: body);
    return InviteEntry.fromJson(ApiClient.requireMap(res.data, res.requestOptions));
  }

  Future<void> deleteInvite(String id) async {
    await dio.delete('/api/auth/invites/$id');
  }

  Future<String> changePassword({required String oldPassword, required String newPassword}) async {
    final res = await dio.post(
      '/api/auth/change-password',
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
    return ApiClient.requireMap(res.data, res.requestOptions)['token']?.toString() ?? '';
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

  Future<String> setAccountRole(String id, String role) async {
    final res = await dio.patch('/api/auth/users/$id/role', data: {'role': role});
    final map = ApiClient.requireMap(res.data, res.requestOptions);
    return map['role']?.toString() ?? role;
  }

  Future<void> deleteAccount(String id) async {
    await dio.delete('/api/auth/users/$id');
  }

  Future<String> resetAccountPassword(String id) async {
    final res = await dio.post('/api/auth/users/$id/reset-password');
    return ApiClient.requireMap(res.data, res.requestOptions)['temp_password']?.toString() ?? '';
  }

  Future<void> adminUnlock(String password) async {
    await dio.post('/api/auth/admin-unlock', data: {'password': password});
  }

  Future<CreatedAccount> createUser({
    required String username,
    String email = '',
    String password = '',
    String note = '',
    String role = 'user',
  }) async {
    final res = await dio.post(
      '/api/auth/users',
      data: {'username': username, 'email': email, 'password': password, 'note': note, 'role': role},
    );
    return CreatedAccount.fromJson(ApiClient.requireMap(res.data, res.requestOptions));
  }

  Future<String> uploadAvatar({
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    final res = await dio.post('/api/auth/me/avatar', data: form);
    return ApiClient.requireMap(res.data, res.requestOptions)['avatar']?.toString() ?? '';
  }
}
