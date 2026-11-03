import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/api/endpoints/admin_endpoints.dart';
import 'package:hue_heritage_music/models/auth_user.dart';
import 'package:hue_heritage_music/services/admin_reauth.dart';
import 'package:hue_heritage_music/models/compare_result.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/models/pitch_data.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/heritage/heritage_list_screen.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/app_logo.dart';
import 'package:hue_heritage_music/widgets/common_button.dart';
import 'package:hue_heritage_music/widgets/compare_chart.dart';
import 'package:hue_heritage_music/widgets/content_max_width.dart';
import 'package:hue_heritage_music/widgets/overlay_pitch_chart.dart';
import 'package:hue_heritage_music/widgets/pitch_contour_chart.dart';
import 'package:hue_heritage_music/widgets/sheet_music_view.dart';
import 'package:provider/provider.dart';

void main() {
  test('ServerConfig starts without a server until configured', () {
    final cfg = ServerConfig();
    expect(cfg.baseUrl, '');
    expect(cfg.hasServer, isFalse);
  });

  test('ServerConfig normalizes base URL', () {
    expect(ServerConfig.normalize('http://192.0.2.10:8000/api'), 'http://192.0.2.10:8000');
    expect(ServerConfig.normalize('http://192.0.2.10:8000/'), 'http://192.0.2.10:8000');
    expect(ServerConfig.normalize('192.0.2.10:8000'), 'http://192.0.2.10:8000');
    expect(ServerConfig.normalize(''), '');
  });

  testWidgets('Settings screen never shows server configuration UI', (tester) async {
    final locale = LocaleProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('Kết nối máy chủ AI'), findsNothing);
    expect(find.textContaining('Địa chỉ máy chủ'), findsNothing);
    expect(find.textContaining('URL máy chủ'), findsNothing);
    expect(find.textContaining('Kiểm tra'), findsNothing);
  });

  testWidgets('CommonButton renders and responds to tap', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommonButton(
            label: 'Test Button',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Test Button'), findsOneWidget);
    await tester.tap(find.text('Test Button'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('PitchContourChart renders properly', (tester) async {
    final pitch = PitchData(
      meanF0: 220.0,
      frames: 3,
      times: [0.0, 0.5, 1.0],
      f0: [210.0, 220.0, 230.0],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: PitchContourChart(data: pitch),
          ),
        ),
      ),
    );

    expect(find.byType(PitchContourChart), findsOneWidget);
  });

  testWidgets('CompareChart renders properly', (tester) async {
    final comp = CompareResult(
      metrics: CompareMetrics(
        score: 85.0,
        pitchScore: 88.0,
        timeScore: 80.0,
        meanAbsCents: 15.0,
        medianCents: 12.0,
        meanOffsetMs: 50.0,
        startOffsetMs: 20.0,
        pairs: 10,
        dtwDistance: 3.2,
      ),
      times: [0.0, 0.5],
      sampleF0: [220.0, 220.0],
      warpedF0: [225.0, 225.0],
      notes: [
        CompareNote(
          midi: 60,
          name: 'C4',
          start: 0.0,
          end: 0.5,
          errCents: 5.0,
          verdict: 'Chuan',
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: CompareChart(
                times: comp.times,
                sampleF0: comp.sampleF0,
                warpedF0: comp.warpedF0,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CompareChart), findsOneWidget);
  });

  testWidgets('SheetMusicView shows piano roll and disclaimer', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SheetMusicView(
              notes: [
                SheetNote(midi: 69, start: 0.0, end: 0.5),
                SheetNote(midi: 72, start: 0.5, end: 1.0),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('kiểm duyệt'), findsOneWidget);
  });

  testWidgets('CreationScreen renders header and tabs properly', (tester) async {
    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _MockHttpAdapter();
    final history = HistoryService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<HistoryService>.value(value: history),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
        ],
        child: const MaterialApp(
          home: CreationScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Sáng tạo cùng Ca Huế'), findsOneWidget);
    expect(find.text('Hát Nguyên Bản'), findsOneWidget);
    expect(find.text('Sáng Tạo Lời Mới'), findsOneWidget);
  });

  testWidgets('HomeScreen renders only 3 core cards and excludes legacy clutter', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _MockHttpAdapter();
    final locale = LocaleProvider();
    locale.setLocale('vi');
    final theme = ThemeProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Kho di sản số'), findsWidgets);
    expect(find.text('Phục dựng (Beta)'), findsWidgets);
    expect(find.text('Học hát Ca Huế'), findsWidgets);
    expect(find.text('Audio -> Bản nhạc'), findsWidgets);
    expect(find.text('Sáng tạo cùng Ca Huế'), findsWidgets);
    expect(find.text('Lịch sử'), findsWidgets);
    expect(find.text('Thông tin dự án'), findsNothing);
  });

  testWidgets('HeritageListScreen is pure listening without FAB or learning buttons', (tester) async {
    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _MockHttpAdapter();
    final locale = LocaleProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ],
        child: const MaterialApp(
          home: Scaffold(body: HeritageListScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Luyện hát'), findsNothing);
    expect(find.text('Học hát'), findsNothing);
    expect(find.text('Nhạc cụ'), findsNothing);
  });

  testWidgets('RestorationScreen renders DSP and Cross-matching tabs', (tester) async {
    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _MockHttpAdapter();
    final locale = LocaleProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RestorationScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
  });

  testWidgets('RestorationScreen cross-compare tab opens without crashing', (tester) async {
    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _MockHttpAdapter();
    final locale = LocaleProvider();
    final history = HistoryService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ChangeNotifierProvider<HistoryService>.value(value: history),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RestorationScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Đối chiếu & Tìm tên bài'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Đối chiếu âm học & Nhận diện bài'), findsOneWidget);
    expect(find.text('Tải lên bản ghi của bạn để đối chiếu'), findsOneWidget);
  });

  test('AuthService guest mode behaves correctly without persistence', () {
    final auth = AuthService();
    auth.continueAsGuest();
    expect(auth.isGuest, isTrue);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.username, 'Khách');
    expect(auth.token, isNull);
  });

  testWidgets('ContentMaxWidth constraints large widths', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ContentMaxWidth(
              maxWidth: 800,
              child: SizedBox(width: 1200, height: 100),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ContentMaxWidth), findsOneWidget);
  });

  testWidgets('LoginScreen renders tabs and guest button', (tester) async {
    final server = ServerConfig();
    final auth = AuthService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Đăng nhập'), findsWidgets);
    expect(find.text('Trải nghiệm ngay (Chế độ Khách)'), findsOneWidget);
    expect(find.textContaining('Liên hệ quản trị viên'), findsOneWidget);
  });

  test('401 from a guarded endpoint clears the stored token', () async {
    final auth = AuthService();
    await auth.load();
    await auth.save(token: 'tok123', username: 'tester');
    expect(AuthService.currentToken, 'tok123');

    final api = ApiClient(baseUrl: 'http://127.0.0.1:8000');
    api.dio.httpClientAdapter = _UnauthorizedAdapter();
    try {
      await api.dio.get('/api/heritage');
    } catch (_) {}

    expect(auth.token, isNull);
    expect(AuthService.currentToken, isNull);
    expect(auth.isLoggedIn, isFalse);
  });

  test('401 from /auth/me keeps the token', () async {
    final auth = AuthService();
    await auth.load();
    await auth.save(token: 'tok456', username: 'tester');
    expect(auth.isLoggedIn, isTrue);

    final api = ApiClient(baseUrl: 'http://127.0.0.1:8000');
    api.dio.httpClientAdapter = _UnauthorizedAdapter();
    try {
      await api.dio.get('/api/auth/me');
    } catch (_) {}

    expect(auth.token, 'tok456');
    expect(auth.isLoggedIn, isTrue);
  });

  testWidgets('AppLogo builds with size and radius parameters', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: AppLogo(size: 44, iconSize: 24, iconColor: Colors.white)),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppLogo), findsOneWidget);
  });

  test('retry interceptor retries GET but never POST', () async {
    final adapter = _FlakyAdapter({'GET /api/x': 2});
    final client = ApiClient(baseUrl: 'http://127.0.0.1:9');
    client.dio.httpClientAdapter = adapter;
    final ok = await client.dio.get('/api/x');
    expect(ok.statusCode, 200);
    expect(adapter.calls, 3);

    final postAdapter = _FlakyAdapter({'POST /api/y': 1});
    client.dio.httpClientAdapter = postAdapter;
    try {
      await client.dio.post('/api/y');
      fail('should have thrown');
    } on DioException {
      expect(postAdapter.calls, 1);
    }
  });

  test('AuthService stores and clears role', () async {
    final auth = AuthService();
    await auth.save(token: 'tok', username: 'ghitatruongle', email: 'x@gmail.com', role: 'admin');
    expect(auth.role, 'admin');
    expect(auth.isAdmin, isTrue);

    await auth.save(token: 'tok2', username: 'someone', email: 'y@gmail.com', role: 'user');
    expect(auth.isAdmin, isFalse);

    await auth.clearToken();
    expect(auth.role, 'user');
    expect(auth.isAdmin, isFalse);
  });

  test('validateSession renews sliding token and syncs profile', () async {
    final auth = AuthService();
    await auth.save(token: 'old-token', username: 'user1', email: 'a@gmail.com', role: 'user');
    final dio = Dio(BaseOptions())
      ..httpClientAdapter = _JsonAdapter({
        'id': 'u1',
        'username': 'user1',
        'email': 'a@gmail.com',
        'role': 'admin',
        'must_change_password': true,
        'token': 'fresh-token',
      });
    await auth.validateSession('http://server:8000', dio: dio);
    expect(auth.token, 'fresh-token');
    expect(auth.role, 'admin');
    expect(auth.isAdmin, isTrue);
    expect(auth.mustChangePassword, isTrue);
    expect(auth.isLoggedIn, isTrue);
    await auth.clearToken();
  });

  test('validateSession logs out softly on 401 expired token', () async {
    final auth = AuthService();
    await auth.save(token: 'expired-token', username: 'user2', email: 'b@gmail.com');
    final dio = Dio(BaseOptions())..httpClientAdapter = _UnauthorizedAdapter();
    await auth.validateSession('http://server:8000', dio: dio);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.sessionExpiredNotice, isTrue);
    auth.consumeSessionExpiredNotice();
    expect(auth.sessionExpiredNotice, isFalse);
  });

  test('validateSession keeps session when server unreachable', () async {
    final auth = AuthService();
    await auth.save(token: 'keep-token', username: 'user3', email: 'c@gmail.com');
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 200),
      receiveTimeout: const Duration(milliseconds: 200),
    ))..httpClientAdapter = _OfflineAdapter();
    await auth.validateSession('http://server:8000', dio: dio);
    expect(auth.isLoggedIn, isTrue);
    expect(auth.token, 'keep-token');
    await auth.clearToken();
  });

  test('AdminStats parses nested server payload', () {
    final stats = AdminStats.fromJson({
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
    });
    expect(stats.usersTotal, 4);
    expect(stats.usersActive, 3);
    expect(stats.invitesUnused, 2);
    expect(stats.itemsBytes, 1048576);
    expect(stats.derivedFiles, 12);
    expect(stats.tasksByStatus['done'], 5);
    expect(stats.tasksByKind['transcribe'], 6);
    expect(stats.engineOnline, isTrue);
  });


  test('AuthUser parses must_change_password flag', () {
    final flagged = AuthUser.fromJson({'id': 'u1', 'username': 'a', 'token': 't', 'must_change_password': true});
    expect(flagged.mustChangePassword, isTrue);
    final plain = AuthUser.fromJson({'id': 'u2', 'username': 'b', 'token': 't'});
    expect(plain.mustChangePassword, isFalse);
    expect(flagged.toJson()['must_change_password'], isTrue);
  });

  testWidgets('runWithAdminReauth prompts password, unlocks, retries action', (tester) async {
    final server = ServerConfig();
    int unlockCalls = 0;
    int actionCalls = 0;
    server.api.dio.httpClientAdapter = _StatefulAdminAdapter(
      onUnlock: () => unlockCalls++,
      onAction: () => actionCalls++,
    );
    final locale = LocaleProvider()..setLocale('vi');

    late BuildContext captured;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );

    Future<Response<dynamic>> doAction() => server.api.dio.get('/api/admin/stats');
    final future = runWithAdminReauth(captured, doAction);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Xác thực quản trị'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'AdminKhoe#2026x');
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();
    final result = await future;
    expect(result.statusCode, 200);
    expect(unlockCalls, 1);
    expect(actionCalls, 2);
  });

  testWidgets('runWithAdminReauth throws AdminReauthCancelled on cancel', (tester) async {
    final server = ServerConfig();
    int actionCalls = 0;
    server.api.dio.httpClientAdapter = _StatefulAdminAdapter(
      onUnlock: () {},
      onAction: () => actionCalls++,
    );
    final locale = LocaleProvider()..setLocale('vi');

    late BuildContext captured;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );

    Future<Response<dynamic>> doAction() => server.api.dio.get('/api/admin/stats');
    final future = runWithAdminReauth(captured, doAction);
    final expectation = expectLater(future, throwsA(isA<AdminReauthCancelled>()));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    await expectation;
    expect(actionCalls, 1);
  });

  test('HistoryEntry score roundtrip', () {
    final entry = HistoryEntry(
      id: 'h1',
      kind: 'practice',
      title: 'Bài A — Câu 1',
      status: 'done',
      at: DateTime(2026, 10, 25),
      score: 87.5,
      detail: 'lesson-1',
    );
    final restored = HistoryEntry.fromJson(entry.toJson());
    expect(restored.score, 87.5);
    expect(restored.detail, 'lesson-1');
    expect(restored.kind, 'practice');

    final legacy = HistoryEntry.fromJson({'id': 'h2', 'kind': 'transcribe', 'title': 'x', 'status': 'done', 'at': '2026-10-25T00:00:00.000'});
    expect(legacy.score, isNull);
    expect(legacy.detail, '');
  });

  testWidgets('OverlayPitchChart renders two contours', (tester) async {
    final result = PracticeResult.fromJson(const {
      'metrics': {'score': 90, 'pitch_score': 92, 'time_score': 85, 'mean_abs_cents': 20},
      'sample': {'times': [0.0, 0.5, 1.0], 'f0': [220.0, 240.0, 260.0]},
      'user_warped': {'times': [0.0, 0.5, 1.0], 'f0': [225.0, 0.0, 262.0]},
      'notes': [],
      'section': {'index': 0},
      'lesson_title': 'Bai A',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OverlayPitchChart(result: result)),
      ),
    );
    expect(find.byType(OverlayPitchChart), findsOneWidget);
  });
}

class _StatefulAdminAdapter implements HttpClientAdapter {
  final void Function() onUnlock;
  final void Function() onAction;
  bool unlocked = false;

  _StatefulAdminAdapter({required this.onUnlock, required this.onAction});

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.method == 'POST' && options.path.endsWith('/api/auth/admin-unlock')) {
      final body = options.data;
      final pw = body is Map ? (body['password']?.toString() ?? '') : '';
      onUnlock();
      if (pw == 'AdminKhoe#2026x') {
        unlocked = true;
        return ResponseBody.fromString('{"unlocked": true}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      }
      return ResponseBody.fromString('{"detail": "wrong password"}', 401, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (options.method == 'GET' && options.path.endsWith('/api/admin/stats')) {
      onAction();
      if (!unlocked) {
        return ResponseBody.fromString('{"detail": "admin reauth required"}', 403, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      }
      return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

class _JsonAdapter implements HttpClientAdapter {
  final Map<String, dynamic> payload;
  _JsonAdapter(this.payload);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw DioException.connectionError(requestOptions: options, reason: 'offline in test');
  }

  @override
  void close({bool force = false}) {}
}

class _UnauthorizedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      '{"detail":"authentication required"}',
      401,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MockHttpAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.contains('/api/music/models')) {
      return ResponseBody.fromString(
        '{"base":"base","base_ready":true,"mode":"test","adapters":[]}',
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path.contains('/api/music/heritage-tunes') || options.path.contains('/api/heritage')) {
      return ResponseBody.fromString(
        '[]',
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

class _FlakyAdapter implements HttpClientAdapter {
  int calls = 0;
  final Map<String, int> failTimes;

  _FlakyAdapter(this.failTimes);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    final key = '${options.method.toUpperCase()} ${options.uri.path}';
    final remaining = failTimes[key] ?? 0;
    if (remaining > 0) {
      failTimes[key] = remaining - 1;
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'simulated connection error',
      );
    }
    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}
