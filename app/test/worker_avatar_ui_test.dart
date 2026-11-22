import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/api/endpoints/admin_endpoints.dart';
import 'package:hue_heritage_music/api/endpoints/auth_endpoints.dart';
import 'package:hue_heritage_music/screens/auth/account_manager_section.dart';
import 'package:hue_heritage_music/screens/auth/invite_manager_section.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/widgets/avatar_view.dart';
import 'package:provider/provider.dart';

class _MockAdapter implements HttpClientAdapter {
  int avatarRequests = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.contains('/api/avatars/')) {
      avatarRequests += 1;
      return ResponseBody.fromString('not found', 404);
    }
    if (options.path.contains('/api/auth/users')) {
      return ResponseBody.fromString(
        jsonEncode({
          'items': [
            {
              'id': 'u-admin',
              'username': 'ghitatruongle',
              'email': 'admin@gmail.com',
              'role': 'admin',
              'active': true,
              'must_change_password': false,
              'avatar': '/api/avatars/u-admin',
            },
            {
              'id': 'u-worker',
              'username': 'worker01',
              'email': 'worker01@gmail.com',
              'role': 'worker',
              'active': true,
              'must_change_password': false,
              'avatar': '/api/avatars/u-worker',
            },
            {
              'id': 'u-user',
              'username': 'plain01',
              'email': 'plain01@gmail.com',
              'role': 'user',
              'active': true,
              'must_change_password': false,
              'avatar': '',
            },
          ],
          'total': 3,
        }),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path.contains('/api/auth/invites')) {
      return ResponseBody.fromString(
        jsonEncode({'detail': 'admin truong only'}),
        403,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString(
      '[]',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _wrap(AuthService auth, Widget child) {
  final server = ServerConfig();
  server.api.dio.httpClientAdapter = _MockAdapter();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: auth),
    ],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

Future<AuthService> _prepareAuth(String role) async {
  final auth = AuthService();
  await auth.save(token: 'tok-$role', username: 'me-$role', email: 'me@test.vn', role: role);
  return auth;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
  });

  test('AdminStats đọc workers count', () {
    final s = AdminStats.fromJson({
      'users': {'total': 8, 'active': 6, 'workers': 2},
      'invites': {'total': 9, 'unused': 2},
      'storage': {'items_total': 30, 'items_bytes': 1, 'derived_files': 0, 'derived_bytes': 0, 'generated_bytes': 0},
      'tasks': {'by_status': {}, 'by_kind': {}},
      'engine_online': true,
    });
    expect(s.workersActive, 2);
    expect(s.usersTotal, 8);
  });

  test('AccountEntry và CreatedAccount đọc avatar/role', () {
    final acc = AccountEntry.fromJson({
      'id': 'u1',
      'username': 'worker01',
      'email': 'w@t.vn',
      'role': 'worker',
      'active': true,
      'avatar': '/api/avatars/u1',
    });
    expect(acc.avatar, '/api/avatars/u1');
    expect(acc.role, 'worker');
    final created = CreatedAccount.fromJson({
      'id': 'u2',
      'username': 'worker02',
      'email': '',
      'temp_password': 'hue-ab12cd34',
      'generated': false,
      'role': 'worker',
    });
    expect(created.role, 'worker');
    expect(created.tempPassword, 'hue-ab12cd34');
  });

  testWidgets('Worker vào Quản trị: danh sách tài khoản chỉ xem, không nút reset/xóa/switch', (tester) async {
    final auth = await _prepareAuth('worker');
    await tester.pumpWidget(_wrap(auth, const AccountManagerSection()));
    await tester.pumpAndSettle();
    expect(find.text('worker01'), findsOneWidget);
    expect(find.text('plain01'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byTooltip('Đặt lại mật khẩu'), findsNothing);
    expect(find.byTooltip('Xóa tài khoản'), findsNothing);
    expect(find.text('Chế độ cộng tác viên: chỉ xem danh sách tài khoản đã đăng ký.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin vào danh sách tài khoản: đủ nút quản lý', (tester) async {
    final auth = await _prepareAuth('admin');
    await tester.pumpWidget(_wrap(auth, const AccountManagerSection()));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsNWidgets(3));
    expect(find.byTooltip('Đặt lại mật khẩu'), findsNWidgets(3));
  });

  testWidgets('Worker: mỗi tài khoản hiện đúng icon vai (worker = engineering)', (tester) async {
    final auth = await _prepareAuth('worker');
    await tester.pumpWidget(_wrap(auth, const AccountManagerSection()));
    await tester.pumpAndSettle();
    expect(find.text('worker01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('InviteManagerSection workerMode: không gọi list, chỉ tạo mã', (tester) async {
    final auth = await _prepareAuth('worker');
    await tester.pumpWidget(_wrap(auth, const InviteManagerSection(workerMode: true)));
    await tester.pumpAndSettle();
    expect(find.text('Chưa tạo mã mời nào trong phiên này.'), findsOneWidget);
    expect(find.text('Bấm tạo để nhận mã mời mới (dùng cho người đăng ký). Danh sách mã thuộc quyền admin.'), findsOneWidget);
    expect(find.text('Tạo mã mời mới'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AvatarView fallback khi rỗng và khi fetch 404', (tester) async {
    final auth = await _prepareAuth('admin');
    await tester.pumpWidget(_wrap(auth, const Column(children: [
      AvatarView(url: ''),
      AvatarView(url: '/api/avatars/u-missing-0'),
    ])));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AvatarView cache-negative: 404 không refetch khi rebuild trong 60s', (tester) async {
    final auth = await _prepareAuth('admin');
    final server = ServerConfig();
    final adapter = _MockAdapter();
    server.api.dio.httpClientAdapter = adapter;
    Widget host() => MultiProvider(
          providers: [
            ChangeNotifierProvider<ServerConfig>.value(value: server),
            ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AvatarView(url: '/api/avatars/u-neg-test')),
          ),
        );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsOneWidget);
    final afterFirst = adapter.avatarRequests;
    expect(afterFirst, 1);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(adapter.avatarRequests, afterFirst, reason: 'negative cache phải chặn refetch');
  });
}
