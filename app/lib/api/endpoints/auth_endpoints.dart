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
}
