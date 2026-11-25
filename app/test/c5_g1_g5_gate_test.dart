import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/main.dart';
import 'package:hue_heritage_music/screens/admin/admin_screen.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/heritage/heritage_list_screen.dart';
import 'package:hue_heritage_music/screens/history/history_screen.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/screens/learning/lesson_practice_view.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/practice_resume.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/audio_player_bar.dart';
import 'package:hue_heritage_music/widgets/hue_icons.dart';
import 'package:hue_heritage_music/widgets/server_onboarding_dialog.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, List<String>> get _jsonHeaders => {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };

class _NavMockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions opt) handler;

  _NavMockAdapter(this.handler);

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

class _NavJustAudio extends JustAudioPlatform {
  final Map<String, _NavAudioPlayer> _players = {};
  int initCount = 0;
  int disposeCount = 0;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    initCount++;
    final p = _NavAudioPlayer(request.id);
    _players[request.id] = p;
    return p;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    disposeCount++;
    await _players.remove(request.id)?.dispose(DisposeRequest());
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    for (final p in _players.values.toList()) {
      await p.dispose(DisposeRequest());
    }
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

class _NavAudioPlayer extends AudioPlayerPlatform {
  final _events = StreamController<PlaybackEventMessage>.broadcast();
  bool isPlaying = false;

  _NavAudioPlayer(super.id);

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    if (!_events.isClosed) {
      _events.add(
        PlaybackEventMessage(
          processingState: ProcessingStateMessage.ready,
          updateTime: DateTime.now(),
          updatePosition: Duration.zero,
          bufferedPosition: const Duration(seconds: 8),
          duration: const Duration(seconds: 8),
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        ),
      );
    }
    return LoadResponse(duration: const Duration(seconds: 8));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    isPlaying = true;
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    isPlaying = false;
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    if (!_events.isClosed) {
      await _events.close();
    }
    return DisposeResponse();
  }
}

Future<ServerConfig> _serverWithNavMocks({bool Function()? shouldFailLessons}) async {
  SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8000'});
  final server = ServerConfig();
  await server.load();
  server.api.dio.httpClientAdapter = _NavMockAdapter((opt) async {
    if (opt.path.contains('/api/auth/login')) {
      final body = opt.data is Map ? opt.data as Map : const {};
      final id = body['identifier']?.toString() ?? 'user1';
      final role = id == 'ghitatruongle' ? 'admin' : (id == 'worker1' ? 'worker' : 'user');
      return ResponseBody.fromString(
        jsonEncode({
          'token': 'tok-$id',
          'username': id,
          'email': '$id@example.com',
          'role': role,
          'must_change_password': false,
          'avatar': '',
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/auth/me')) {
      return ResponseBody.fromString(
        jsonEncode({'username': 'u', 'email': 'u@example.com', 'role': 'user'}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/admin/stats')) {
      return ResponseBody.fromString(
        jsonEncode({
          'users': {'total': 2, 'active': 2},
          'invites': {'total': 1, 'unused': 1},
          'storage': {
            'items_total': 1,
            'items_bytes': 1024,
            'derived_files': 0,
            'derived_bytes': 0,
            'generated_bytes': 0,
          },
          'tasks': {'by_status': {}, 'by_kind': {}},
          'engine_online': true,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/admin/security/summary')) {
      return ResponseBody.fromString(jsonEncode({'counts': {}, 'window_hours': 24}), 200, headers: _jsonHeaders);
    }
    if (opt.path.contains('/api/admin/security')) {
      return ResponseBody.fromString(jsonEncode({'events': [], 'total': 0, 'truncated': false}), 200, headers: _jsonHeaders);
    }
    if (opt.path.contains('/api/auth/users') || opt.path.contains('/api/auth/invites')) {
      return ResponseBody.fromString(jsonEncode({'items': [], 'total': 0}), 200, headers: _jsonHeaders);
    }
    if (opt.path.contains('/api/music/models')) {
      return ResponseBody.fromString(
        jsonEncode({'base': 'b', 'base_ready': true, 'mode': 'm', 'adapters': []}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/music/heritage-tunes')) {
      return ResponseBody.fromString(
        jsonEncode([
          {'id': 't1', 'title': 'Nam Ai', 'type': 'Ca Hue', 'artist': 'NS', 'sha256': 's1', 'size': 1024}
        ]),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/heritage')) {
      return ResponseBody.fromString(
        jsonEncode({
          'items': [
            {'id': 't1', 'title': 'Nam Ai', 'type': 'Ca Hue', 'artist': 'NS', 'sha256': 's1', 'size': 1024}
          ],
          'total': 1,
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/music/play-url')) {
      return ResponseBody.fromString(
        jsonEncode({'url': 'http://127.0.0.1:8000/signed.wav'}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/lessons/scales')) {
      return ResponseBody.fromString(
        jsonEncode([
          {'id': 's1', 'name': 'Nam Ai', 'note_names': ['Ho', 'Xu']}
        ]),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/lessons/progress')) {
      return ResponseBody.fromString(jsonEncode({'items': []}), 200, headers: _jsonHeaders);
    }
    if (opt.path.contains('/api/lessons/l1')) {
      return ResponseBody.fromString(
        jsonEncode({
          'id': 'l1',
          'title': 'Bai Hoc 1',
          'type': 'Ca Hue',
          'artist': 'NS',
          'mode_system': 'Nam',
          'bpm': 60,
          'has_ornaments': false,
          'sections': [
            {'index': 0, 'start': 0.0, 'duration': 4.0, 'lyrics': 'Ho o', 'has_sample': false, 'sample_url': ''}
          ],
        }),
        200,
        headers: _jsonHeaders,
      );
    }
    if (opt.path.contains('/api/lessons')) {
      if (shouldFailLessons != null && shouldFailLessons()) {
        return ResponseBody.fromString(
          jsonEncode({'detail': 'offline'}),
          500,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString(
        jsonEncode([
          {'id': 'l1', 'title': 'Bai Hoc 1', 'type': 'Ca Hue', 'artist': 'NS', 'mode_system': 'Nam', 'bpm': 60, 'has_ornaments': false, 'sections': 1}
        ]),
        200,
        headers: _jsonHeaders,
      );
    }
    return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
  });
  return server;
}

Widget _wrapHome({
  required ServerConfig server,
  required AuthService auth,
  HistoryService? history,
  SessionMedia? sessionMedia,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<HistoryService>.value(value: history ?? HistoryService()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: auth),
      ChangeNotifierProvider<SessionMedia>.value(value: sessionMedia ?? SessionMedia()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const OfflineBanner(child: HomeScreen()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NavJustAudio fakeAudio;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    fakeAudio = _NavJustAudio();
    JustAudioPlatform.instance = fakeAudio;

    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (call) async => '/tmp/hue-c5-gate',
    );
    const connChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      connChannel,
      (call) async => <String>['wifi'],
    );
    const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      audioSessionChannel,
      (call) async => call.method == 'setActive' ? true : null,
    );
  });

  testWidgets('C5 G1: boot directly to HomeScreen guest, push LoginScreen unlocks role, C5-1 worker<->admin role switch updates tabs, C5-2 resets navIndex cleanly', (tester) async {
    const s = AppStrings('vi');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);

    final server = await _serverWithNavMocks();
    final auth = AuthService();

    await tester.pumpWidget(
      HueHeritageApp(
        config: server,
        theme: ThemeProvider(),
        history: HistoryService(),
        locale: LocaleProvider()..setLocale('vi'),
        auth: auth,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byIcon(HueIcons.adminPanel), findsNothing);

    await tester.tap(find.byTooltip(s.authTooltipGuest));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginScreen), findsOneWidget);

    final loginFields = find.descendant(of: find.byType(LoginScreen), matching: find.byType(TextField));
    await tester.enterText(loginFields.at(0), 'worker1');
    await tester.enterText(loginFields.at(1), 'Secret123');
    final loginBtn = find.descendant(
      of: find.byType(LoginScreen),
      matching: find.widgetWithText(FilledButton, s.authLoginBtn),
    );
    await tester.ensureVisible(loginBtn);
    await tester.pump();
    await tester.tap(loginBtn);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(auth.isLoggedIn, isTrue, reason: 'texts=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList()}');
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byIcon(HueIcons.adminPanel), findsOneWidget);

    await tester.tap(find.byIcon(HueIcons.adminPanel));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminScreen), findsOneWidget);
    expect(find.text(s.adminTabSecurity), findsNothing);
    expect(find.text(s.adminTabCrash), findsNothing);

    await auth.save(token: 'tok-adm', username: 'ghitatruongle', role: 'admin');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminScreen), findsOneWidget);
    expect(find.text(s.adminTabSecurity), findsOneWidget);
    expect(find.text(s.adminTabCrash), findsOneWidget);

    await tester.ensureVisible(find.text(s.adminTabCrash));
    await tester.pump();
    await tester.tap(find.text(s.adminTabCrash));
    await tester.pump(const Duration(milliseconds: 300));

    await auth.save(token: 'tok-wrk2', username: 'worker1', role: 'worker');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminScreen), findsOneWidget);
    expect(find.text(s.adminTabSecurity), findsNothing);
    expect(find.text(s.adminTabCrash), findsNothing);

    await auth.save(token: 'tok-usr', username: 'user1', role: 'user');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminScreen), findsNothing);
    expect(find.text(s.quickAccessTitle), findsOneWidget);

    await auth.save(token: 'tok-adm2', username: 'ghitatruongle', role: 'admin');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AdminScreen), findsNothing);
    expect(find.text(s.quickAccessTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5 G1/C5-2: session boundary resets visited tab cache on logout and preserves Auth tab when logging out on Auth tab', (tester) async {
    const s = AppStrings('vi');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);

    final server = await _serverWithNavMocks();
    final auth = AuthService();
    await auth.save(token: 'tok-u1', username: 'user1', role: 'user', mustChangePassword: true);

    await tester.pumpWidget(_wrapHome(server: server, auth: auth));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(s.mustChangeTitle), findsWidgets);
    await tester.tap(find.text(s.mustChangeLater));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(HueIcons.libraryMusic).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.descendant(of: find.byType(HeritageListScreen), matching: find.byType(TextField)),
      'User1Query',
    );
    await tester.pump();

    await tester.tap(find.byIcon(HueIcons.accountCircle).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text(s.authLogoutBtn));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginScreen), findsOneWidget);

    await auth.save(token: 'tok-u2', username: 'user2', role: 'user', mustChangePassword: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(s.mustChangeTitle), findsWidgets);
    await tester.tap(find.text(s.mustChangeLater));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(HueIcons.libraryMusic).first);
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('User1Query'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5 G2: back from mobile More bottom sheet and Settings dialog keeps underlying screen intact', (tester) async {
    const s = AppStrings('vi');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    final server = await _serverWithNavMocks();
    final auth = AuthService();
    await auth.save(token: 'tok-worker', username: 'worker1', role: 'worker');

    await tester.pumpWidget(_wrapHome(server: server, auth: auth));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(HueIcons.gridView));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text(s.settingsTitle),
      150,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)),
    );
    expect(find.text(s.settingsTitle), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(s.quickAccessTitle), findsOneWidget);

    await tester.tap(find.byIcon(HueIcons.gridView));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(
      find.text(s.settingsTitle),
      150,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)),
    );
    await tester.tap(find.text(s.settingsTitle).last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(s.serverChangeAction),
      150,
      scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)),
    );
    await tester.ensureVisible(find.text(s.serverChangeAction));
    await tester.pump();
    await tester.tap(find.text(s.serverChangeAction));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ServerOnboardingDialog), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ServerOnboardingDialog), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(s.quickAccessTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5 G3: all 5 tab state-types (text, option/filter, scroll, subtab, AudioPlayerBar playback) stay intact across tab switches', (tester) async {
    const s = AppStrings('vi');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);

    final server = await _serverWithNavMocks();
    final auth = AuthService();
    final history = HistoryService();
    for (var i = 0; i < 40; i++) {
      await history.add(
        HistoryEntry(
          id: 'h$i',
          kind: i.isEven ? 'practice' : 'restore',
          title: 'Muc $i',
          status: 'done',
          at: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
    }

    await tester.pumpWidget(_wrapHome(server: server, auth: auth, history: history));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(HueIcons.libraryMusic).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final playerFinder = find.descendant(of: find.byType(HeritageListScreen), matching: find.byType(AudioPlayerBar));
    expect(playerFinder, findsOneWidget);
    final playerStateBefore = tester.state(playerFinder);
    final disposesBefore = fakeAudio.disposeCount;

    await tester.tap(find.byIcon(HueIcons.autoAwesome).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(s.creationTabNewLyrics));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(s.wizardStepLyrics));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.descendant(of: find.byType(CreationScreen), matching: find.byType(TextField)),
      'Cau ho Song Huong',
    );
    await tester.pump();

    await tester.tap(find.byIcon(HueIcons.history).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('${s.historyFilterPractice} (20)'));
    await tester.pump();
    final histScroll = find.descendant(of: find.byType(HistoryScreen), matching: find.byType(CustomScrollView));
    await tester.drag(histScroll, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 100));
    final scrollableState = tester.state<ScrollableState>(
      find.descendant(of: find.byType(HistoryScreen), matching: find.byType(Scrollable)),
    );
    final savedOffset = scrollableState.position.pixels;
    expect(savedOffset, greaterThan(100));

    await tester.tap(find.byIcon(HueIcons.home).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(HueIcons.autoAwesome).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cau ho Song Huong'), findsOneWidget);
    expect(find.byKey(const Key('wizard-steps')), findsOneWidget);

    await tester.tap(find.byIcon(HueIcons.libraryMusic).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(identical(tester.state(playerFinder), playerStateBefore), isTrue);
    expect(fakeAudio.disposeCount, disposesBefore);

    await tester.tap(find.byIcon(HueIcons.history).first);
    await tester.pump(const Duration(milliseconds: 300));
    final restoredOffset = tester.state<ScrollableState>(
      find.descendant(of: find.byType(HistoryScreen), matching: find.byType(Scrollable)),
    ).position.pixels;
    expect(restoredOffset, closeTo(savedOffset, 1.0));
    await tester.drag(
      find.descendant(of: find.byType(HistoryScreen), matching: find.byType(CustomScrollView)),
      const Offset(0, 700),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final restoredFilter = tester.widget<FilterChip>(
      find.ancestor(of: find.text('${s.historyFilterPractice} (20)'), matching: find.byType(FilterChip)),
    );
    expect(restoredFilter.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5-3: LessonPracticeView history hides lesson link on scale entries, opens real lesson entries, and resumes pending lesson on cold load', (tester) async {
    const s = AppStrings('vi');
    final server = await _serverWithNavMocks();
    final history = HistoryService();
    await history.add(
      HistoryEntry(
        id: 'hs1',
        kind: 'practice',
        title: 'Luyen thang am: Nam Ai',
        status: 'done',
        at: DateTime(2026, 1, 1),
        score: 88,
        detail: 'scale:s1',
      ),
    );
    await history.add(
      HistoryEntry(
        id: 'hl1',
        kind: 'practice',
        title: 'Bai Hoc 1 - Cau 1',
        status: 'done',
        at: DateTime(2026, 1, 1),
        score: 91,
        detail: 'l1',
      ),
    );

    PracticeResume.lessonId.value = 'l1';
    addTearDown(PracticeResume.clear);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HistoryService>.value(value: history),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: LessonPracticeView()),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Ho o'), findsOneWidget);
    expect(find.text(s.practiceLessonGone), findsNothing);
    expect(find.text('Luyen thang am: Nam Ai'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5-4: resizing across 960px desktop<->mobile breakpoint preserves mounted tab state and AudioPlayerBar without dispose', (tester) async {
    const s = AppStrings('vi');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);

    final server = await _serverWithNavMocks();
    final auth = AuthService();

    await tester.pumpWidget(_wrapHome(server: server, auth: auth));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(HueIcons.libraryMusic).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    final playerFinder = find.descendant(of: find.byType(HeritageListScreen), matching: find.byType(AudioPlayerBar));
    expect(playerFinder, findsOneWidget);
    final playerStateBefore = tester.state(playerFinder);
    final disposesBefore = fakeAudio.disposeCount;

    await tester.tap(find.byIcon(HueIcons.autoAwesome).first);
    await tester.pump(const Duration(milliseconds: 300));
    final creationStateBefore = tester.state(find.byType(CreationScreen));
    await tester.tap(find.text(s.creationTabNewLyrics));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(s.wizardStepLyrics));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.descendant(of: find.byType(CreationScreen), matching: find.byType(TextField)),
      'Cau ho Song Huong',
    );
    await tester.pump();

    tester.view.physicalSize = const Size(320, 640);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(identical(tester.state(find.byType(CreationScreen)), creationStateBefore), isTrue);
    expect(fakeAudio.disposeCount, disposesBefore);
    await tester.drag(
      find.descendant(of: find.byType(CreationScreen), matching: find.byType(ListView)),
      const Offset(0, -180),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cau ho Song Huong'), findsOneWidget);
    expect(find.byKey(const Key('wizard-steps')), findsOneWidget);

    tester.view.physicalSize = const Size(1024, 768);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NavigationBar), findsNothing);
    expect(identical(tester.state(find.byType(CreationScreen)), creationStateBefore), isTrue);
    expect(find.text('Cau ho Song Huong'), findsOneWidget);

    await tester.tap(find.byIcon(HueIcons.libraryMusic).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(identical(tester.state(playerFinder), playerStateBefore), isTrue);
    expect(fakeAudio.disposeCount, disposesBefore);

    tester.view.physicalSize = const Size(880, 700);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(of: find.byType(HeritageListScreen), matching: find.byType(ListTile)).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5-2: session boundary on active content tab resets current tab and clears SessionMedia and PracticeResume safely', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);

    final server = await _serverWithNavMocks();
    final auth = AuthService();
    final sessionMedia = SessionMedia();
    await auth.save(token: 'tok-u1', username: 'user1', role: 'user');

    await tester.pumpWidget(_wrapHome(server: server, auth: auth, sessionMedia: sessionMedia));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(HueIcons.libraryMusic).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.descendant(of: find.byType(HeritageListScreen), matching: find.byType(TextField)),
      'ActiveTabQuery',
    );
    await tester.pump();
    expect(find.text('ActiveTabQuery'), findsOneWidget);

    sessionMedia.setRecording(path: '/tmp/u1_rec.wav');
    PracticeResume.lessonId.value = 'l1';
    addTearDown(PracticeResume.clear);

    await auth.clearToken();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(sessionMedia.recordingPath, isNull);
    expect(PracticeResume.lessonId.value, isNull);
    expect(find.text('ActiveTabQuery'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5-3: LessonPracticeView ignores scale resume ID and retries load on pending lesson after initial failure', (tester) async {
    const s = AppStrings('vi');
    var failLessons = true;
    final server = await _serverWithNavMocks(shouldFailLessons: () => failLessons);
    addTearDown(PracticeResume.clear);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: LessonPracticeView()),
        ),
      ),
    );
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Ho o'), findsNothing);

    PracticeResume.lessonId.value = 'scale:s1';
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(PracticeResume.lessonId.value, isNull);
    expect(find.text(s.practiceLessonGone), findsNothing);
    expect(find.text('Ho o'), findsNothing);

    failLessons = false;
    PracticeResume.lessonId.value = 'l1';
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Ho o'), findsOneWidget);
    expect(find.text(s.practiceLessonGone), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
