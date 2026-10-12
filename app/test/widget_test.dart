import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/models/compare_result.dart';
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
      MaterialApp(
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
    );

    expect(find.byType(CompareChart), findsOneWidget);
  });

  testWidgets('SheetMusicView shows piano roll and disclaimer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SheetMusicView(
            notes: [
              SheetNote(midi: 69, start: 0.0, end: 0.5),
              SheetNote(midi: 72, start: 0.5, end: 1.0),
            ],
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
    expect(find.textContaining('Bản 0.0.0 chưa hỗ trợ đặt lại mật khẩu'), findsOneWidget);
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
