import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:provider/provider.dart';

class _MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.contains('/api/admin/stats')) {
      return ResponseBody.fromString(
        jsonEncode({
          'users': {'total': 4, 'active': 3},
          'invites': {'total': 9, 'unused': 2},
          'storage': {
            'items_total': 30,
            'items_bytes': 1048576,
            'derived_files': 12,
            'derived_bytes': 2048,
            'generated_bytes': 4096,
          },
          'tasks': {'by_status': {'done': 5, 'error': 1}, 'by_kind': {'transcribe': 6}},
          'engine_online': true,
        }),
        200,
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

Widget _home(AuthService auth) {
  final server = ServerConfig();
  server.api.dio.httpClientAdapter = _MockAdapter();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
    ],
    child: const MaterialApp(
      home: HomeScreen(),
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
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => '/tmp/hue-nav-clamp-test-support',
    );
  });

  testWidgets('nav index is clamped when admin role drops while on admin tab', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final auth = AuthService();
    await auth.save(token: 'tok-admin-t2', username: 'ghitatruongle', email: 'a@x.com', role: 'admin');
    addTearDown(() async {
      await auth.clearToken();
    });

    await tester.pumpWidget(_home(auth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final adminIcon = find.byIcon(Icons.admin_panel_settings_outlined);
    expect(adminIcon, findsOneWidget);
    await tester.tap(adminIcon);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await auth.save(token: 'tok-user-t2', username: 'plainuser', email: 'b@x.com', role: 'user');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('nav index is clamped on logout while on admin tab', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final auth = AuthService();
    await auth.save(token: 'tok-admin-t3', username: 'ghitatruongle', email: 'a@x.com', role: 'admin');
    addTearDown(() async {
      await auth.clearToken();
    });

    await tester.pumpWidget(_home(auth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final adminIcon = find.byIcon(Icons.admin_panel_settings_outlined);
    expect(adminIcon, findsOneWidget);
    await tester.tap(adminIcon);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await auth.clearToken();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
