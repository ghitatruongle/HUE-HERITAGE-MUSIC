import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/api/endpoints/auth_endpoints.dart';
import 'package:hue_heritage_music/screens/auth/account_manager_section.dart';
import 'package:hue_heritage_music/screens/auth/invite_manager_section.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> postedInvites = [];
  final List<(String, Map<String, dynamic>)> rolePatches = [];
  int inviteGetCalls = 0;
  bool requireReauthOnce = false;
  bool workerCapReached = false;
  bool adminUnlocked = false;
  String plainRole = 'user';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/api/avatars/')) {
      return ResponseBody.fromString('not found', 404);
    }
    if (path == '/api/auth/invites' && options.method == 'GET') {
      inviteGetCalls += 1;
      return ResponseBody.fromString(
        jsonEncode({
          'total': 3,
          'items': [
            {
              'id': 'i-multi',
              'code': 'HUE-MULTI05',
              'note': 'Lớp ca huế',
              'max_uses': 5,
              'used_count': 2,
              'remaining_uses': 3,
              'used': false,
              'expired': false,
              'active': true,
              'expires_at': '2030-01-15T10:30:00Z',
            },
            {
              'id': 'i-unlim',
              'code': 'HUE-UNLIM00',
              'note': '',
              'max_uses': 0,
              'used_count': 10,
              'remaining_uses': null,
              'used': false,
              'expired': false,
              'active': true,
              'expires_at': null,
            },
            {
              'id': 'i-exp',
              'code': 'HUE-OLDEXP1',
              'note': '',
              'max_uses': 3,
              'used_count': 1,
              'remaining_uses': 2,
              'used': false,
              'expired': true,
              'active': false,
              'expires_at': '2020-01-01T00:00:00Z',
            },
          ],
        }),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (path == '/api/auth/invites' && options.method == 'POST') {
      final raw = options.data is Map ? Map<String, dynamic>.from(options.data as Map) : <String, dynamic>{};
      postedInvites.add(raw);
      final maxUses = raw['max_uses'] is num ? (raw['max_uses'] as num).toInt() : 1;
      final expMin = raw['expires_minutes'] is num ? (raw['expires_minutes'] as num).toInt() : null;
      final expHr = raw['expires_hours'] is num ? (raw['expires_hours'] as num).toDouble() : null;
      final expAt = (expMin != null || expHr != null)
          ? DateTime.now().toUtc().add(Duration(minutes: expMin ?? ((expHr! * 60).round()))).toIso8601String()
          : null;
      return ResponseBody.fromString(
        jsonEncode({
          'id': 'i-created-${postedInvites.length}',
          'code': (raw['code']?.toString().isNotEmpty == true) ? raw['code'] : 'HUE-AUTO1234',
          'note': raw['note'] ?? '',
          'max_uses': maxUses,
          'used_count': 0,
          'remaining_uses': maxUses == 0 ? null : maxUses,
          'used': false,
          'expired': false,
          'active': true,
          'expires_at': expAt,
        }),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (path == '/api/auth/users' && options.method == 'GET') {
      return ResponseBody.fromString(
        jsonEncode({
          'total': 3,
          'items': [
            {
              'id': 'u-admin',
              'username': 'ghitatruongle',
              'email': 'admin@example.local',
              'role': 'admin',
              'active': true,
            },
            {
              'id': 'u-worker',
              'username': 'worker01',
              'email': 'w@example.local',
              'role': 'worker',
              'active': true,
            },
            {
              'id': 'u-user',
              'username': 'plain01',
              'email': 'u@example.local',
              'role': plainRole,
              'active': true,
            },
          ],
        }),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (path == '/api/auth/admin-unlock' && options.method == 'POST') {
      adminUnlocked = true;
      return ResponseBody.fromString(
        jsonEncode({'unlocked': true}),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (path.endsWith('/role') && options.method == 'PATCH') {
      if (requireReauthOnce && !adminUnlocked) {
        return ResponseBody.fromString(
          jsonEncode({'detail': 'admin reauth required'}),
          403,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      }
      if (workerCapReached) {
        return ResponseBody.fromString(
          jsonEncode({'detail': 'worker limit reached'}),
          409,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      }
      final raw = options.data is Map ? Map<String, dynamic>.from(options.data as Map) : <String, dynamic>{};
      rolePatches.add((path, raw));
      plainRole = raw['role']?.toString() ?? 'user';
      return ResponseBody.fromString(
        jsonEncode({'id': 'u-user', 'username': 'plain01', 'role': plainRole}),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<AuthService> _authFor(String role) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthService();
  await auth.save(token: 'tok-$role', username: 'actor-$role', email: 'a@test.vn', role: role);
  return auth;
}

Widget _host(AuthService auth, _TestAdapter adapter, Widget child, {double width = 520}) {
  final server = ServerConfig();
  server.api.dio.httpClientAdapter = adapter;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: auth),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
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

  test('InviteEntry.fromJson parses legacy and multi-use/expiring fields cleanly', () {
    final legacy = InviteEntry.fromJson({
      'id': '1',
      'code': 'LEGACY01',
      'note': 'old',
      'used': true,
    });
    expect(legacy.maxUses, 1);
    expect(legacy.usedCount, 1);
    expect(legacy.remainingUses, 0);
    expect(legacy.active, isFalse);
    expect(legacy.expired, isFalse);
    expect(legacy.expiresAt, isNull);

    final unlimited = InviteEntry.fromJson({
      'id': '2',
      'code': 'UNLIM',
      'note': '',
      'max_uses': 0,
      'used_count': 7,
      'remaining_uses': null,
      'used': false,
      'expired': false,
      'active': true,
      'expires_at': '2030-05-01T12:00:00Z',
    });
    expect(unlimited.maxUses, 0);
    expect(unlimited.usedCount, 7);
    expect(unlimited.remainingUses, isNull);
    expect(unlimited.active, isTrue);
    expect(unlimited.expiresAt, isNotNull);
  });

  testWidgets('Admin InviteManagerSection renders multi-use, unlimited & expiry badges at 320px and creates custom invite', (tester) async {
    final auth = await _authFor('admin');
    final adapter = _TestAdapter();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(auth, adapter, const InviteManagerSection(), width: 320));
    await tester.pumpAndSettle();

    expect(find.text('HUE-MULTI05'), findsOneWidget);
    expect(find.text('2/5 lượt'), findsOneWidget);
    expect(find.text('10 · Không giới hạn lượt'), findsOneWidget);
    expect(find.text('Hết hạn'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tạo mã mời mới'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Mã tùy chỉnh (để trống = tự sinh)'), 'HUE-VIP2026');
    await tester.enterText(find.widgetWithText(TextField, 'Ghi chú (không bắt buộc)'), 'Đoàn khách');
    await tester.ensureVisible(find.text('10 lượt'));
    await tester.tap(find.text('10 lượt'));
    await tester.ensureVisible(find.text('2 giờ'));
    await tester.tap(find.text('2 giờ'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    expect(adapter.postedInvites.length, 1);
    expect(adapter.postedInvites.first['code'], 'HUE-VIP2026');
    expect(adapter.postedInvites.first['note'], 'Đoàn khách');
    expect(adapter.postedInvites.first['max_uses'], 10);
    expect(adapter.postedInvites.first['expires_minutes'], 120);
    expect(find.text('HUE-VIP2026'), findsOneWidget);
    expect(find.text('0/10 lượt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Worker InviteManagerSection creates unlimited + custom-hours invite without calling GET list', (tester) async {
    final auth = await _authFor('worker');
    final adapter = _TestAdapter();

    await tester.pumpWidget(_host(auth, adapter, const InviteManagerSection(workerMode: true)));
    await tester.pumpAndSettle();

    expect(adapter.inviteGetCalls, 0);

    await tester.tap(find.text('Tạo mã mời mới'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Tùy chỉnh').first);
    await tester.tap(find.text('Tùy chỉnh').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextField, 'Nhập số lượt (0 = không giới hạn, 1-10000)'));
    await tester.enterText(find.widgetWithText(TextField, 'Nhập số lượt (0 = không giới hạn, 1-10000)'), '0');

    await tester.ensureVisible(find.text('Tùy chỉnh').last);
    await tester.tap(find.text('Tùy chỉnh').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Giờ'));
    await tester.tap(find.text('Giờ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextField, 'Thời hạn tùy chỉnh'));
    await tester.enterText(find.widgetWithText(TextField, 'Thời hạn tùy chỉnh'), '4.5');

    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    expect(adapter.inviteGetCalls, 0);
    expect(adapter.postedInvites.length, 1);
    expect(adapter.postedInvites.first['max_uses'], 0);
    expect(adapter.postedInvites.first['expires_hours'], 4.5);
    expect(find.text('0 · Không giới hạn lượt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin AccountManagerSection promotes user to worker with reauth and surfaces 409 worker cap', (tester) async {
    final auth = await _authFor('admin');
    final adapter = _TestAdapter()..requireReauthOnce = true;

    await tester.pumpWidget(_host(auth, adapter, const AccountManagerSection()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Chọn làm cộng tác viên'), findsNWidgets(2));
    expect(find.byTooltip('Hạ về người dùng thường'), findsOneWidget);

    await tester.tap(find.byTooltip('Chọn làm cộng tác viên').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cấp quyền cộng tác viên cho: plain01?'), findsOneWidget);

    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    expect(find.text('Xác thực quản trị'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'AdminPass#2026');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();

    expect(adapter.adminUnlocked, isTrue);
    expect(adapter.rolePatches.length, 1);
    expect(adapter.rolePatches.first.$1, '/api/auth/users/u-user/role');
    expect(adapter.rolePatches.first.$2['role'], 'worker');
    expect(find.byTooltip('Hạ về người dùng thường'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin AccountManagerSection surfaces 409 worker limit reached cleanly', (tester) async {
    final auth = await _authFor('admin');
    final adapter = _TestAdapter()..workerCapReached = true;

    await tester.pumpWidget(_host(auth, adapter, const AccountManagerSection()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Chọn làm cộng tác viên').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    expect(find.text('Số lượng cộng tác viên đang hoạt động đã đạt giới hạn.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Worker AccountManagerSection hides role toggle buttons', (tester) async {
    final auth = await _authFor('worker');
    final adapter = _TestAdapter();

    await tester.pumpWidget(_host(auth, adapter, const AccountManagerSection()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Chọn làm cộng tác viên'), findsNothing);
    expect(find.byTooltip('Hạ về người dùng thường'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen hides AI server address from guest/user and shows for admin/worker', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://192.0.2.10:8000'});
    final server = ServerConfig();
    await server.load();
    final auth = AuthService();

    Widget buildSettings() => MultiProvider(
          providers: [
            ChangeNotifierProvider<ServerConfig>.value(value: server),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
            ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
        );

    await tester.pumpWidget(buildSettings());
    await tester.pumpAndSettle();
    expect(find.text('Máy chủ AI'), findsNothing);
    expect(find.text('http://192.0.2.10:8000'), findsNothing);

    auth.continueAsGuest();
    await tester.pumpAndSettle();
    expect(find.text('Máy chủ AI'), findsNothing);
    expect(find.text('http://192.0.2.10:8000'), findsNothing);

    await auth.save(token: 'tok-user', username: 'user01', role: 'user');
    await tester.pumpAndSettle();
    expect(find.text('Máy chủ AI'), findsNothing);
    expect(find.text('Địa chỉ máy chủ'), findsNothing);
    expect(find.text('http://192.0.2.10:8000'), findsNothing);

    await auth.save(token: 'tok-worker', username: 'worker01', role: 'worker');
    await tester.pumpAndSettle();
    expect(find.text('Máy chủ AI'), findsOneWidget);
    expect(find.text('Địa chỉ máy chủ'), findsOneWidget);
    expect(find.text('http://192.0.2.10:8000'), findsOneWidget);

    await auth.save(token: 'tok-admin', username: 'ghitatruongle', role: 'admin');
    await tester.pumpAndSettle();
    expect(find.text('Máy chủ AI'), findsOneWidget);
    expect(find.text('http://192.0.2.10:8000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
