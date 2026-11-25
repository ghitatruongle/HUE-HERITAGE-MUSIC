import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/api/endpoints/lesson_api.dart';
import 'package:hue_heritage_music/api/endpoints/sing_api.dart';
import 'package:hue_heritage_music/core/constants/app_constants.dart';
import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/local_pitch.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/practice_resume.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/teaching_utils.dart';
import 'package:hue_heritage_music/widgets/compare_chart.dart';
import 'package:hue_heritage_music/widgets/overlay_pitch_chart.dart';
import 'package:hue_heritage_music/widgets/pitch_contour_chart.dart';
import 'package:hue_heritage_music/widgets/sheet_music_view.dart';
import 'package:hue_heritage_music/widgets/status_colors.dart';
import 'package:hue_heritage_music/widgets/waveform_view.dart';
import 'package:hue_heritage_music/models/pitch_data.dart';
import 'package:provider/provider.dart';

Uint8List _sinePcm16(double freqHz, int samples, {int sampleRate = 16000}) {
  final out = Uint8List(samples * 2);
  final bd = ByteData.sublistView(out);
  for (var i = 0; i < samples; i++) {
    final s = (16000.0 * math.sin(2 * math.pi * freqHz * i / sampleRate)).round();
    bd.setInt16(i * 2, s, Endian.little);
  }
  return out;
}

class _StubAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _StubAdapter(this.handler);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => '/tmp/hue-wave3-test',
    );
  });

  test('AppConstants version bumped to 0.0.5-beta2', () {
    expect(AppConstants.appVersion, '0.0.5-beta2');
  });

  test('LocalPitch live helpers detect 440Hz, label A4 and fold octaves', () {
    final pcm = _sinePcm16(440.0, 1200);
    final f0 = LocalPitch.estimateLiveF0(pcm);
    expect(f0, isNotNull);
    expect((f0! - 440.0).abs(), lessThan(8.0));
    expect(LocalPitch.noteLabel(440.0), 'A4');
    final delta = LocalPitch.foldOctaveDiffCents(220.0, 440.0);
    expect(delta, isNotNull);
    expect(delta!.abs(), lessThan(0.1));
    final silent = Uint8List(LocalPitch.frameSize * 2);
    expect(LocalPitch.estimateLiveF0(silent), 0.0);
  });

  test('PracticeWord & WordScore propagate octaveDiff cleanly', () {
    final word = PracticeWord.fromServerJson({
      'line': 0,
      'index': 1,
      'text': 'Huế',
      'start': 1.2,
      'end': 1.8,
      'voiced_ratio': 0.9,
      'err_cents': 12.5,
      'octave_diff': true,
      'verdict_code': 'ok',
      'verdict': 'Chuẩn',
    });
    expect(word, isNotNull);
    expect(word!.octaveDiff, isTrue);
    final scores = serverWordScores([word]);
    expect(scores.single.octaveDiff, isTrue);
  });

  test('UTC+7 midnight practice sync maps UTC session timestamps to local day streak', () {
    const tz = Duration(hours: 7);
    final serverNowLocal = parsePracticeDate('2026-11-22T23:30:00', utcOffset: tz);
    final sessionLocal = parsePracticeDate('2026-11-22T23:10:00', utcOffset: tz);
    expect(serverNowLocal!.day, 23);
    expect(sessionLocal!.day, 23);
    final stats = practiceStatsFromDates([sessionLocal], serverNowLocal);
    expect(stats.streakDays, 1);
    expect(stats.last7Counts.last, 1);
  });

  test('ApiClient.describe maps new auth errors and preserves fallback', () {
    DioException bad(int status, dynamic data) => DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(requestOptions: RequestOptions(path: '/api/test'), statusCode: status, data: data),
          type: DioExceptionType.badResponse,
        );

    expect(
      ApiClient.describe(bad(400, {'detail': 'password must be at least 8 characters and contain letters and digits'})),
      contains('8 ký tự'),
    );
    expect(ApiClient.describe(bad(409, {'detail': 'username already exists'})), contains('đã có người sử dụng'));
    expect(ApiClient.describe(bad(401, {'detail': 'wrong password'})), contains('Mật khẩu không đúng'));
    expect(ApiClient.describe(bad(403, {'detail': 'account disabled'})), contains('vô hiệu hóa'));
    expect(ApiClient.describe(bad(400, {'detail': 'unexpected raw traceback'})), 'Máy chủ từ chối yêu cầu. Thử lại sau ít phút.');
  });

  test('SingApi.compareItems & LessonApi.myProgress parse beta2 fields', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
    String? seenPath;
    dio.httpClientAdapter = _StubAdapter((opt) async {
      seenPath = opt.path;
      if (opt.path == '/api/music/compare-items') {
        return ResponseBody.fromString(
          jsonEncode({
            'metrics': {
              'score': 91.5,
              'pitch_score': 92.0,
              'time_score': 90.0,
              'mean_abs_cents': 18.0,
            },
            'sample': {'times': [0.0, 0.1], 'f0': [220.0, 220.0]},
            'user_warped': {'f0': [221.0, 219.0]},
          }),
          200,
          headers: {'content-type': ['application/json']},
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'items': [],
          'server_history': true,
          'server_today': '2026-11-22',
          'server_utc_now': '2026-11-22T23:40:00',
        }),
        200,
        headers: {'content-type': ['application/json']},
      );
    });

    final cmp = await SingApi(dio).compareItems(sampleItemId: 'a', userItemId: 'b');
    expect(seenPath, '/api/music/compare-items');
    expect(cmp.metrics.score, 91.5);

    final page = await LessonApi(dio).myProgress();
    expect(page.serverToday, '2026-11-22');
    expect(page.serverUtcNow, '2026-11-22T23:40:00');
  });

  testWidgets('Charts insert FlSpot.nullSpot across unvoiced zeros and support octave fold', (tester) async {
    final pr = PracticeResult(
      metrics: PracticeMetrics(score: 88, pitchScore: 90, timeScore: 85, meanAbsCents: 15, octaveShift: 2.0),
      refTimes: const [0.0, 0.1, 0.2, 0.3],
      refF0: const [440.0, 0.0, 440.0, 440.0],
      userF0: const [220.0, 0.0, 220.0, 222.0],
      notes: const [],
      sectionIndex: 0,
      lessonTitle: 'Test',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  OverlayPitchChart(result: pr),
                  const CompareChart(times: [0.0, 0.1, 0.2], sampleF0: [440.0, 0.0, 440.0], warpedF0: [220.0, 0.0, 220.0]),
                  PitchContourChart(data: PitchData(meanF0: 440, frames: 3, times: const [0.0, 0.1, 0.2], f0: const [440.0, 0.0, 440.0])),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final charts = tester.widgetList<LineChart>(find.byType(LineChart)).toList();
    expect(charts.length, 3);
    expect(charts[0].data.lineBarsData[0].spots, contains(FlSpot.nullSpot));
    expect(charts[1].data.lineBarsData[0].spots, contains(FlSpot.nullSpot));
    expect(charts[2].data.lineBarsData[0].spots, contains(FlSpot.nullSpot));

    await tester.tap(find.byType(FilterChip));
    await tester.pump();
    final afterFold = tester.widgetList<LineChart>(find.byType(LineChart)).first;
    final foldedY = afterFold.data.lineBarsData[1].spots.first.y;
    expect((foldedY - 440.0).abs(), lessThan(5.0));
  });

  testWidgets('statusColor uses theme-aware dark and light status tokens', (tester) async {
    late Color darkOk;
    late Color lightOk;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (ctx) {
            darkOk = statusColor(ctx, 'ok');
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(darkOk, AppTheme.statusSuccessDark);

    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: ThemeData.light(),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (ctx) {
            lightOk = statusColor(ctx, 'ok');
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(lightOk, AppTheme.statusSuccess);
  });

  testWidgets('LoginScreen shows Worker role badge & rejects <8 char registration password', (tester) async {
    final auth = AuthService();
    final locale = LocaleProvider();
    final server = ServerConfig();
    final history = HistoryService();

    await auth.save(token: 'tok', username: 'ctv1', role: 'worker', avatar: '');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: locale),
          ChangeNotifierProvider.value(value: server),
          ChangeNotifierProvider.value(value: history),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
    expect(find.text(const AppStrings('vi').authRoleWorker), findsOneWidget);

    await auth.clearToken();
    await tester.pumpAndSettle();
    await tester.tap(find.text(const AppStrings('vi').authTabRegister));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'newuser');
    await tester.enterText(fields.at(1), 'newuser@example.com');
    await tester.enterText(fields.at(2), 'abc123');
    await tester.enterText(fields.at(3), 'HUE-1234');
    final regBtn = find.widgetWithText(FilledButton, const AppStrings('vi').authRegisterBtn);
    await tester.ensureVisible(regBtn);
    await tester.tap(regBtn);
    await tester.pump();
    expect(find.text(const AppStrings('vi').authErrPasswordShort), findsOneWidget);
  });

  testWidgets('WaveformView and SheetMusicView rebuild CustomPaint on data update cleanly', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                WaveformView(data: WaveformData([0.2, 0.8])),
                SheetMusicView(notes: [SheetNote(midi: 60, start: 0.0, end: 0.5)]),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('CreationScreen has zero overflow at 320px width', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => ServerConfig()),
          ChangeNotifierProvider(create: (_) => HistoryService()),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const CreationScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Logout clears PracticeResume and HistoryService cleanly', (tester) async {
    final auth = AuthService();
    final history = HistoryService();
    await history.add(HistoryEntry(id: 'h1', kind: 'practice', title: 'Old', status: 'done', at: DateTime.now()));
    PracticeResume.lessonId.value = 'lesson-123';
    await auth.save(token: 'tok', username: 'user1', role: 'user');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => ServerConfig()),
          ChangeNotifierProvider.value(value: history),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    final logoutBtn = find.text(const AppStrings('vi').authLogoutBtn);
    await tester.ensureVisible(logoutBtn);
    await tester.tap(logoutBtn);
    await tester.pumpAndSettle();
    expect(PracticeResume.lessonId.value, isNull);
    expect(history.entries, isEmpty);
  });
}
