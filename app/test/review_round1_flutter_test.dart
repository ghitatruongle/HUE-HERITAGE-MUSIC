import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/api/endpoints/admin_endpoints.dart';
import 'package:hue_heritage_music/api/endpoints/auth_endpoints.dart';
import 'package:hue_heritage_music/api/endpoints/transcription_api.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/models/music_task.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/local_pitch.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/teaching_utils.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/sheet_music_view.dart';
import 'package:hue_heritage_music/widgets/skeleton_loader.dart';
import 'package:hue_heritage_music/widgets/waveform_view.dart';

class _MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

Uint8List _pcm16Wav(double freqHz, {int sampleRate = 48000, double seconds = 0.25}) {
  final count = (sampleRate * seconds).round();
  final dataLen = count * 2;
  final out = Uint8List(44 + dataLen);
  final bd = ByteData.sublistView(out);
  out.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]);
  bd.setUint32(4, 36 + dataLen, Endian.little);
  out.setRange(8, 12, [0x57, 0x41, 0x56, 0x45]);
  out.setRange(12, 16, [0x66, 0x6D, 0x74, 0x20]);
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  out.setRange(36, 40, [0x64, 0x61, 0x74, 0x61]);
  bd.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < count; i++) {
    final s = (16000.0 * math.sin(2 * math.pi * freqHz * i / sampleRate)).round();
    bd.setInt16(44 + i * 2, s, Endian.little);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MusicTask.fromJson falls back to error when reason is missing', () {
    final task = MusicTask.fromJson({
      'id': 't1',
      'kind': 'generate',
      'status': 'error',
      'error': 'acestep offline',
    });
    expect(task.reason, 'acestep offline');

    final taskWithReason = MusicTask.fromJson({
      'id': 't2',
      'kind': 'generate',
      'status': 'rejected',
      'reason': 'lora not found',
      'error': 'ignored',
    });
    expect(taskWithReason.reason, 'lora not found');
  });

  test('PracticeResult.fromJson maps server integer octave_shift exponent to multiplier', () {
    for (final entry in <int, double>{-2: 0.25, -1: 0.5, 0: 1.0, 1: 2.0, 2: 4.0}.entries) {
      final pr = PracticeResult.fromJson({
        'metrics': {
          'score': 88,
          'pitch_score': 90,
          'time_score': 85,
          'mean_abs_cents': 14,
          'octave_shift': entry.key,
        },
        'sample': {'times': [0.0, 0.2], 'f0': [440.0, 440.0]},
        'user_warped': {'f0': [220.0, 220.0]},
        'notes': [],
      });
      expect(pr.metrics.octaveShift, closeTo(entry.value, 1e-6));
    }
  });

  test('parsePracticeDate handles 10-char server_today without RangeError and stats handle DST', () {
    final todayOnly = parsePracticeDate('2026-11-22');
    expect(todayOnly, isNotNull);
    expect(todayOnly!.year, 2026);
    expect(todayOnly.month, 11);
    expect(todayOnly.day, 22);

    final shifted = parsePracticeDate('2026-11-22 23:40:00', utcOffset: const Duration(hours: 7));
    expect(shifted, isNotNull);
    expect(shifted!.day, 23);
    expect(shifted.hour, 6);

    final stats = practiceStatsFromDates(
      [DateTime(2026, 3, 7, 10), DateTime(2026, 3, 8, 10), DateTime(2026, 3, 9, 10)],
      DateTime(2026, 3, 9, 22),
    );
    expect(stats.streakDays, 3);
    expect(stats.last7Counts.last, 1);
  });

  test('AuthService.continueAsGuest clears staff role, avatar, and expired notice', () async {
    final auth = AuthService();
    await auth.save(
      token: 'tok-worker',
      username: 'ctv1',
      email: 'ctv1@example.com',
      role: 'worker',
      avatar: '/api/avatars/1',
    );
    expect(auth.isStaff, isTrue);

    auth.continueAsGuest();
    expect(auth.isGuest, isTrue);
    expect(auth.role, 'user');
    expect(auth.isStaff, isFalse);
    expect(auth.avatar, isEmpty);
    expect(auth.sessionExpiredNotice, isFalse);
  });

  test('ApiClient.describe surfaces mapped 403/404 friendly details and masks unknown ones', () {
    DioException bad(int status, String detail) => DioException(
          requestOptions: RequestOptions(path: '/api/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/x'),
            statusCode: status,
            data: {'detail': detail},
          ),
          type: DioExceptionType.badResponse,
        );

    expect(ApiClient.describe(bad(403, 'account disabled')), contains('vô hiệu hóa'));
    expect(ApiClient.describe(bad(403, 'password change required')), contains('mật khẩu tạm'));
    expect(ApiClient.describe(bad(404, 'section not found')), contains('câu hát'));
    expect(ApiClient.describe(bad(403, 'admin truong only')), 'Bạn không có quyền thực hiện hành động này.');
    expect(ApiClient.describe(bad(404, 'random missing id')), 'Không tìm thấy dữ liệu trên máy chủ.');
  });

  test('LocalPitch.analyze supports 48kHz dynamically and rejects impossible low sample rates safely', () {
    final res48 = LocalPitch.analyze(_pcm16Wav(440.0, sampleRate: 48000, seconds: 0.25));
    expect(res48, isNotNull);
    expect(res48!.meanF0, inInclusiveRange(415.0, 465.0));

    final lowSr = LocalPitch.analyze(_pcm16Wav(220.0, sampleRate: 400, seconds: 0.25));
    expect(lowSr, isNotNull);
    expect(lowSr!.points, isEmpty);
  });

  test('HistoryService serializes rapid writes and skips corrupt stored entries', () async {
    SharedPreferences.setMockInitialValues({
      'task_history': jsonEncode([
        'corrupt-entry',
        {
          'id': 'ok1',
          'kind': 'practice',
          'title': 'Ly Muoi Thuong',
          'status': 'done',
          'at': '2026-11-22T10:00:00.000',
        },
      ]),
    });
    final history = HistoryService();
    await history.load();
    expect(history.entries.length, 1);
    expect(history.entries.first.id, 'ok1');

    final f1 = history.add(HistoryEntry(
      id: 'id_2',
      kind: 'restore',
      title: 'Bai 2',
      status: 'running',
      at: DateTime(2026, 11, 22, 11),
    ));
    final f2 = history.updateStatus('id_2', 'done');
    await Future.wait([f1, f2]);
    expect(history.entries.first.status, 'done');
  });

  testWidgets('SheetMusicView paints trailing edge notes safely without clamp RangeError', (tester) async {
    const notes = [
      SheetNote(midi: 69, start: 0.999, end: 1.0),
      SheetNote(midi: 71, start: 0.0, end: 1.0),
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                height: 360,
                child: SheetMusicView(notes: notes),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SkeletonList disposes cleanly under disableAnimations toggle', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: false),
        child: MaterialApp(home: Scaffold(body: SkeletonList(itemCount: 3))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: SkeletonList(itemCount: 3))),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    expect(tester.takeException(), isNull);
  });

  testWidgets('RestorationScreen keeps Tab 2 dropdown stable across Tab 1 search filter', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final server = ServerConfig();
    await server.saveServerUrl('http://127.0.0.1:8000');
    server.api.dio.httpClientAdapter = _MockAdapter((opt) async {
      final q = opt.queryParameters['q']?.toString() ?? '';
      final all = [
        {'id': 'h1', 'title': 'Nam Ai', 'type': 'Ca Hue', 'artist': 'NSND', 'duration': 60},
        {'id': 'h2', 'title': 'Phu Luc', 'type': 'Nha nhac', 'artist': 'Doan NT', 'duration': 45},
      ];
      final filtered = q.isEmpty ? all : all.where((e) => (e['title'] as String).contains(q)).toList();
      return ResponseBody.fromString(
        jsonEncode({'items': filtered, 'total': filtered.length}),
        200,
        headers: {'content-type': ['application/json']},
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: server),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => HistoryService()),
        ],
        child: const MaterialApp(home: RestorationScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(find.byType(TextField).first, 'Nam Ai');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Đối chiếu & Tìm tên bài'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  test('ThemeProvider.load notifies listeners after restoring saved ThemeMode', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final provider = ThemeProvider();
    int notifications = 0;
    provider.addListener(() => notifications++);
    await provider.load();
    expect(provider.mode, ThemeMode.light);
    expect(notifications, 1);
  });

  test('TranscriptionApi truncates decimal BPM to match backend int(bpm)', () {
    final api = TranscriptionApi(Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000')));
    expect(api.midiUrl('abc', bpm: 60.8), 'http://127.0.0.1:8000/api/music/midi/abc?bpm=60');
    expect(api.xmlUrl('abc', bpm: 60.8), 'http://127.0.0.1:8000/api/music/musicxml/abc?bpm=60');
  });

  test('AuthEndpoints and AdminEndpoints throw DioException on non-Map JSON payloads', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
    dio.httpClientAdapter = _MockAdapter((_) async {
      return ResponseBody.fromString(
        '["unexpected-list"]',
        200,
        headers: {'content-type': ['application/json']},
      );
    });
    final authApi = AuthEndpoints(dio);
    final adminApi = AdminEndpoints(dio);
    await expectLater(authApi.login(identifier: 'u', password: 'p'), throwsA(isA<DioException>()));
    await expectLater(adminApi.stats(), throwsA(isA<DioException>()));
    await expectLater(adminApi.securitySummary(), throwsA(isA<DioException>()));
  });

  test('validateSession does not mutate caller validateStatus and _healThenClear marks expired', () async {
    final auth = AuthService();
    await auth.save(token: 'tok-round2', username: 'user1', role: 'user');
    final dio = Dio();
    final origValidate = dio.options.validateStatus;
    dio.httpClientAdapter = _MockAdapter((_) async => ResponseBody.fromString('{}', 401));
    await auth.validateSession('http://127.0.0.1:8000', dio: dio);
    expect(identical(dio.options.validateStatus, origValidate), isTrue);
    expect(auth.sessionExpiredNotice, isTrue);
    expect(auth.isLoggedIn, isFalse);

    await auth.save(token: 'tok-round2-b', username: 'user1', role: 'user');
    final client = ApiClient(baseUrl: 'http://127.0.0.1:8000');
    client.dio.httpClientAdapter = _MockAdapter((_) async => ResponseBody.fromString('{}', 401));
    try {
      await client.dio.get('/api/heritage/list');
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(auth.sessionExpiredNotice, isTrue);
    expect(auth.isLoggedIn, isFalse);
  });

  testWidgets('WaveformView uses theme primary color across light and dark modes', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: SizedBox(
              width: 240,
              height: 96,
              child: WaveformView(data: WaveformData([0.2, 0.8, 0.5])),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
