import 'package:dio/dio.dart';

import '../../models/auth_user.dart';

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
}
