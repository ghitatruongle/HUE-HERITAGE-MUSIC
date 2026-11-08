import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/services/auth_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  final int status;
  _FakeAdapter(this.status);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"detail":"fake"}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('Timeout phân lớp: mặc định 30s, DSP 15 phút, upload gửi 2 phút', () {
    final client = ApiClient(baseUrl: 'http://server.test');
    expect(client.dio.options.receiveTimeout, const Duration(seconds: 30));
    expect(client.dio.options.connectTimeout, const Duration(seconds: 30));
    expect(client.dio.options.sendTimeout, const Duration(minutes: 2));
    expect(ApiClient.dspOptions.receiveTimeout, const Duration(minutes: 15));
  });

  test('401 từ endpoint nghiệp vụ ngoài /auth/ → xóa token', () async {
    final auth = AuthService();
    await auth.save(token: 'tok123', username: 'tester');
    expect(AuthService.currentToken, 'tok123');

    final client = ApiClient(baseUrl: 'http://server.test');
    client.dio.httpClientAdapter = _FakeAdapter(401);
    await expectLater(client.dio.get('/api/lessons/list'), throwsException);
    var cleared = false;
    for (var i = 0; i < 50; i++) {
      if (auth.token == null) {
        cleared = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(cleared, isTrue);
    expect(auth.token, isNull);
    expect(AuthService.currentToken, isNull);
  });

  test('401 từ /api/auth/admin-unlock → giữ token phiên', () async {
    final auth = AuthService();
    await auth.save(token: 'tok456', username: 'tester');
    expect(AuthService.currentToken, 'tok456');

    final client = ApiClient(baseUrl: 'http://server.test');
    client.dio.httpClientAdapter = _FakeAdapter(401);
    await expectLater(client.dio.get('/api/auth/admin-unlock'), throwsException);
    expect(auth.token, 'tok456');
    expect(AuthService.currentToken, 'tok456');
  });

  test('401 từ /api/auth/change-password → giữ token phiên', () async {
    final auth = AuthService();
    await auth.save(token: 'tok789', username: 'tester');
    final client = ApiClient(baseUrl: 'http://server.test');
    client.dio.httpClientAdapter = _FakeAdapter(401);
    await expectLater(
      client.dio.post('/api/auth/change-password', data: {}),
      throwsException,
    );
    expect(auth.token, 'tok789');
  });
}
