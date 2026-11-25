import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/models/music_task.dart';
import 'package:hue_heritage_music/models/pitch_data.dart';
import 'package:hue_heritage_music/screens/admin/admin_screen.dart';
import 'package:hue_heritage_music/screens/admin/security_section.dart';
import 'package:hue_heritage_music/screens/analysis/analysis_screen.dart';
import 'package:hue_heritage_music/screens/auth/account_manager_section.dart';
import 'package:hue_heritage_music/screens/auth/invite_manager_section.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/creation/task_result_card.dart';
import 'package:hue_heritage_music/screens/heritage/heritage_list_screen.dart';
import 'package:hue_heritage_music/screens/history/history_screen.dart';
import 'package:hue_heritage_music/screens/learning/learning_screen.dart';
import 'package:hue_heritage_music/screens/learning/lesson_practice_view.dart';
import 'package:hue_heritage_music/screens/learning/scale_practice_card.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
import 'package:hue_heritage_music/screens/transcription/transcription_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/compare_chart.dart';
import 'package:hue_heritage_music/widgets/empty_state.dart';
import 'package:hue_heritage_music/widgets/error_panel.dart';
import 'package:hue_heritage_music/widgets/heritage_motif.dart';
import 'package:hue_heritage_music/widgets/pitch_contour_chart.dart';
import 'package:hue_heritage_music/widgets/responsive_layout.dart';
import 'package:hue_heritage_music/widgets/result_card.dart';
import 'package:hue_heritage_music/widgets/server_onboarding_dialog.dart';
import 'package:hue_heritage_music/widgets/sheet_music_view.dart';
import 'package:hue_heritage_music/widgets/waveform_view.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, List<String>> get _jsonHeaders => {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };

Uint8List _wavBytes({double freqHz = 440, int sampleRate = 16000, double seconds = 0.25}) {
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

class _GateMockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _GateMockAdapter(this.handler);

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

class _GateJustAudio extends JustAudioPlatform {
  final Map<String, _GatePlayer> _players = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final p = _GatePlayer(request.id);
    _players[request.id] = p;
    return p;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
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

class _GatePlayer extends AudioPlayerPlatform {
  final _events = StreamController<PlaybackEventMessage>.broadcast();

  _GatePlayer(super.id);

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
          bufferedPosition: const Duration(seconds: 4),
          duration: const Duration(seconds: 4),
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        ),
      );
    }
    return LoadResponse(duration: const Duration(seconds: 4));
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

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

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) async =>
      AudioEffectSetEnabledResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse();

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
          ConcatenatingInsertAllRequest request) async =>
      ConcatenatingInsertAllResponse();

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
          ConcatenatingRemoveRangeRequest request) async =>
      ConcatenatingRemoveRangeResponse();

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(ConcatenatingMoveRequest request) async =>
      ConcatenatingMoveResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();

  @override
  Future<SetWebCrossOriginResponse> setWebCrossOrigin(SetWebCrossOriginRequest request) async =>
      SetWebCrossOriginResponse();

  @override
  Future<SetWebSinkIdResponse> setWebSinkId(SetWebSinkIdRequest request) async =>
      SetWebSinkIdResponse();

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
          AndroidEqualizerGetParametersRequest request) async =>
      AndroidEqualizerGetParametersResponse(
          parameters: AndroidEqualizerParametersMessage(
              minDecibels: -20, maxDecibels: 20, bands: const <AndroidEqualizerBandMessage>[]));

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
          AndroidEqualizerBandSetGainRequest request) async =>
      AndroidEqualizerBandSetGainResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
}

class _GatePicker extends FilePicker {
  final String path;
  final Uint8List bytes;
  Completer<void>? pickGate;
  Completer<void>? saveGate;
  int pickCalls = 0;
  int saveCalls = 0;

  _GatePicker(this.path, this.bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickCalls++;
    if (pickGate != null) {
      await pickGate!.future;
    }
    return FilePickerResult([
      PlatformFile(name: 'sample.wav', path: path, bytes: bytes, size: bytes.length),
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveCalls++;
    if (saveGate != null) {
      await saveGate!.future;
    }
    return '${Directory.systemTemp.path}/$fileName';
  }
}

double _median(List<double> sorted) {
  if (sorted.isEmpty) return 0;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

Future<double> _measureScrollMedianMs(WidgetTester tester, Finder scrollable) async {
  final samples = <double>[];
  for (var i = 0; i < 12; i++) {
    final sw = Stopwatch()..start();
    await tester.drag(scrollable, const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 16));
    sw.stop();
    samples.add(sw.elapsedMicroseconds / 1000.0);
  }
  final sorted = [...samples]..sort();
  return _median(sorted);
}

Widget _wrapProviders(
  Widget child, {
  ServerConfig? server,
  AuthService? auth,
  HistoryService? history,
  ThemeProvider? theme,
  LocaleProvider? locale,
  SessionMedia? media,
  bool disableAnimations = false,
  bool dark = false,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server ?? ServerConfig()),
      ChangeNotifierProvider<AuthService>.value(value: auth ?? AuthService()),
      ChangeNotifierProvider<HistoryService>.value(value: history ?? HistoryService()),
      ChangeNotifierProvider<ThemeProvider>.value(value: theme ?? ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: locale ?? (LocaleProvider()..setLocale('vi'))),
      ChangeNotifierProvider<SessionMedia>.value(value: media ?? SessionMedia()),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;
  late String wavPath;
  late Uint8List wavBytes;
  late String? activeRecPath;
  bool allowMicPermission = true;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    JustAudioPlatform.instance = _GateJustAudio();
    wavBytes = _wavBytes();
    tmpDir = await Directory.systemTemp.createTemp('hue_c3c4_gate_');
    wavPath = '${tmpDir.path}/sample.wav';
    await File(wavPath).writeAsBytes(wavBytes);

    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (call) async => tmpDir.path,
    );
    const connChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      connChannel,
      (call) async => <String>['wifi'],
    );
    const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      audioSessionChannel,
      (call) async {
        if (call.method == 'setActive') return true;
        return null;
      },
    );
    const recChannel = MethodChannel('com.llfbandit.record/messages');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      recChannel,
      (call) async {
        switch (call.method) {
          case 'create':
            final id = call.arguments is Map ? call.arguments['recorderId']?.toString() : null;
            if (id != null && id.isNotEmpty) {
              for (final prefix in [
                'com.llfbandit.record/events/',
                'com.llfbandit.record/eventsRecordState/',
              ]) {
                TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
                  MethodChannel('$prefix$id'),
                  (c) async => null,
                );
              }
            }
            return 'mock-rec';
          case 'hasPermission':
            return allowMicPermission;
          case 'isEncoderSupported':
            return true;
          case 'isRecording':
          case 'isPaused':
            return false;
          case 'listInputDevices':
            return <dynamic>[];
          case 'start':
            if (call.arguments is Map && call.arguments['path'] is String) {
              activeRecPath = call.arguments['path'] as String;
              File(activeRecPath!).writeAsBytesSync(wavBytes);
            }
            return null;
          case 'stop':
            return activeRecPath ?? wavPath;
          case 'getAmplitude':
            return {'current': -15.0, 'max': -15.0};
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() async {
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('C3 scroll benchmark 200 items across History, Heritage, Security with relative gate', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 200,
            itemBuilder: (_, i) => ListTile(title: Text('Base $i')),
          ),
        ),
      ),
    );
    await tester.pump();
    final baseMedian = await _measureScrollMedianMs(tester, find.byType(ListView));
    final gate = math.max(25.0, baseMedian * 12.0);

    final history = HistoryService();
    for (var i = 0; i < 200; i++) {
      await history.add(
        HistoryEntry(
          id: 'h$i',
          kind: i.isEven ? 'practice' : 'restore',
          title: 'Item $i',
          status: 'done',
          at: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          score: 85,
          detail: 'l$i',
        ),
      );
    }
    await tester.pumpWidget(_wrapProviders(const HistoryScreen(), history: history));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final histMedian = await _measureScrollMedianMs(tester, find.byType(CustomScrollView));

    final heritageServer = ServerConfig();
    await heritageServer.saveServerUrl('http://127.0.0.1:8000');
    final heritageItems = [
      for (var i = 0; i < 200; i++)
        {'id': 'id$i', 'title': 'Bai $i', 'type': 'Ca Hue', 'artist': 'NS $i', 'sha256': 's$i', 'size': 1024}
    ];
    heritageServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      return ResponseBody.fromString(
        jsonEncode({'items': heritageItems, 'total': 200}),
        200,
        headers: _jsonHeaders,
      );
    });
    await tester.pumpWidget(_wrapProviders(const HeritageListScreen(), server: heritageServer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final herMedian = await _measureScrollMedianMs(tester, find.byType(ListView));

    final secServer = ServerConfig();
    await secServer.saveServerUrl('http://127.0.0.1:8000');
    final secEvents = [
      for (var i = 0; i < 200; i++)
        {'ts': '2026-01-01T00:00:$i', 'event': 'login_success', 'level': 'info', 'fields': {'user': 'u$i'}}
    ];
    secServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('summary')) {
        return ResponseBody.fromString(
          jsonEncode({'counts': {'login_success': 200}, 'window_hours': 24}),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString(
        jsonEncode({'events': secEvents, 'total': 200, 'truncated': false}),
        200,
        headers: _jsonHeaders,
      );
    });
    await tester.pumpWidget(_wrapProviders(const SecuritySection(), server: secServer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final secMedian = await _measureScrollMedianMs(tester, find.byType(ListView));

    debugPrint(
      'PERF-GATE-C3-SCROLL base=${baseMedian.toStringAsFixed(2)}ms gate=${gate.toStringAsFixed(1)}ms '
      'history=${histMedian.toStringAsFixed(2)}ms heritage=${herMedian.toStringAsFixed(2)}ms security=${secMedian.toStringAsFixed(2)}ms',
    );
    expect(histMedian, lessThan(gate));
    expect(herMedian, lessThan(gate));
    expect(secMedian, lessThan(gate));
  });

  testWidgets('C3 painters 9-size matrix and scaling [12..300] & [40..600]', (tester) async {
    const sizes = [
      Size(320, 640),
      Size(360, 800),
      Size(390, 844),
      Size(412, 915),
      Size(740, 360),
      Size(768, 1024),
      Size(1024, 768),
      Size(1280, 800),
      Size(1600, 1000),
    ];
    final sw = Stopwatch()..start();
    for (final sz in sizes) {
      tester.view.physicalSize = sz;
      tester.view.devicePixelRatio = 1.0;
      for (final n in const [12, 40, 80, 160, 300]) {
        final notes = [for (var i = 0; i < n; i++) SheetNote(midi: 60 + (i % 12), start: i * 0.2, end: i * 0.2 + 0.15)];
        final times = [for (var i = 0; i < n; i++) i * 0.05];
        final f0 = [for (var i = 0; i < n; i++) 220.0 + (i % 40) * 3];
        final waveN = n == 40 ? 40 : (n == 160 ? 160 : 600);
        await tester.pumpWidget(
          _wrapProviders(
            ListView(
              children: [
                const SizedBox(height: 80, child: HeritageMotif(color: AppTheme.imperialGold)),
                const DanNguyetDisc(size: 80),
                const GaugeScore(value: 87),
                WaveformView(data: WaveformData([for (var i = 0; i < waveN; i++) (i % 10) / 10.0])),
                SheetMusicView(notes: notes),
                PitchContourChart(data: PitchData(times: times, f0: f0, meanF0: 250, frames: n)),
                CompareChart(times: times, sampleF0: f0, warpedF0: f0),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    }
    sw.stop();
    tester.view.reset();
    debugPrint('PERF-GATE-C3-PAINTER 9x5 matrix elapsed=${sw.elapsedMilliseconds}ms');
  });

  testWidgets('C3 reduced motion: PulsingDot stays static (0 transient callbacks)', (tester) async {
    const s = AppStrings('vi');
    await tester.pumpWidget(_wrapProviders(const LearningScreen(key: ValueKey('rm-off')), disableAnimations: false));
    await tester.pump();
    await tester.tap(find.text(s.learnRecordBtn));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(s.learnStopBtn), findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThanOrEqualTo(1));

    await tester.pumpWidget(_wrapProviders(const LearningScreen(key: ValueKey('rm-off')), disableAnimations: true));
    await tester.pumpAndSettle();
    expect(find.text(s.learnStopBtn), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('C3/C4 LessonPracticeView scale count-in: button disabled during arming and safe unmount dispose', (tester) async {
    const s = AppStrings('vi');
    final practiceServer = ServerConfig();
    await practiceServer.saveServerUrl('http://127.0.0.1:8000');
    practiceServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/lessons/scales')) {
        return ResponseBody.fromString(
          jsonEncode([
            {'id': 's1', 'name': 'Nam Ai', 'notes': ['Ho', 'Xu']}
          ]),
          200,
          headers: _jsonHeaders,
        );
      }
      if (opt.path.contains('/api/lessons')) {
        return ResponseBody.fromString(
          jsonEncode([
            {'id': 'l1', 'title': 'Bai 1', 'type': 'Ca Hue', 'artist': 'NS', 'mode_system': 'Nam', 'bpm': 60, 'has_ornaments': false, 'sections': 1}
          ]),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    });
    await tester.pumpWidget(_wrapProviders(const LessonPracticeView(), server: practiceServer));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.ensureVisible(find.text(s.practiceScaleRecord));
    await tester.tap(find.text(s.practiceScaleRecord));
    for (var i = 0; i < 20 && find.text(s.practiceCountingIn(4)).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    final countingFinder = find.text(s.practiceCountingIn(4));
    expect(countingFinder, findsOneWidget);
    await tester.tap(countingFinder, warnIfMissed: false);
    await tester.pump();
    expect(find.byType(ErrorPanel), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('C4 740x360 narrow landscape states and non-empty cached list error panel', (tester) async {
    const s = AppStrings('vi');
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final emptyServer = ServerConfig();
    await emptyServer.saveServerUrl('http://127.0.0.1:8000');
    emptyServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      return ResponseBody.fromString(jsonEncode({'items': [], 'total': 0}), 200, headers: _jsonHeaders);
    });
    await tester.pumpWidget(_wrapProviders(const HeritageListScreen(), server: emptyServer));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_wrapProviders(const RestorationScreen(), server: emptyServer));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);

    bool failHeritage = false;
    final reloadErrServer = ServerConfig();
    await reloadErrServer.saveServerUrl('http://127.0.0.1:8000');
    reloadErrServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (failHeritage) {
        return ResponseBody.fromString('{"detail":"bad"}', 400, headers: _jsonHeaders);
      }
      return ResponseBody.fromString(
        jsonEncode({
          'items': [
            {'id': 'id1', 'title': 'Nam Ai', 'type': 'Ca Hue', 'artist': 'NS', 'sha256': 's1', 'size': 1024}
          ],
          'total': 1,
        }),
        200,
        headers: _jsonHeaders,
      );
    });
    await tester.pumpWidget(_wrapProviders(const HeritageListScreen(), server: reloadErrServer));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Nam Ai'), findsWidgets);
    failHeritage = true;
    await tester.tap(find.text(s.searchBtn));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C4 busy-gate locks: Analysis pick, Restoration upload + dialog safety, Transcription save', (tester) async {
    const s = AppStrings('vi');
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final picker = _GatePicker(wavPath, wavBytes);
    FilePicker.platform = picker;
    final emptyServer = ServerConfig();
    await emptyServer.saveServerUrl('http://127.0.0.1:8000');
    emptyServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      return ResponseBody.fromString(jsonEncode({'items': [], 'total': 0}), 200, headers: _jsonHeaders);
    });

    final gate = Completer<void>();
    picker.pickGate = gate;
    await tester.pumpWidget(_wrapProviders(const AnalysisScreen(), server: emptyServer));
    await tester.pump();
    final pickBtn = find.widgetWithText(FilledButton, s.analysisPickBtn);
    await tester.tap(pickBtn);
    await tester.pump();
    await tester.tap(pickBtn);
    await tester.pump();
    expect(picker.pickCalls, 1);
    gate.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    final picker2 = _GatePicker(wavPath, wavBytes);
    FilePicker.platform = picker2;
    final gate2 = Completer<void>();
    picker2.pickGate = gate2;
    final restoreServer = ServerConfig();
    await restoreServer.saveServerUrl('http://127.0.0.1:8000');
    restoreServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/music/restore-upload')) {
        return ResponseBody.fromString(
          jsonEncode({
            'label': 'OK',
            'sha': 'abcdef123456',
            'sample_rate': 44100,
            'duration': 2.0,
            'dc_removed': 0.0,
            'clicks_fixed': 0,
            'peak_before': 0.5,
            'peak_after': 0.8,
            'noise_floor_db': -60.0,
          }),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString(jsonEncode({'items': [], 'total': 0}), 200, headers: _jsonHeaders);
    });
    await tester.pumpWidget(_wrapProviders(const RestorationScreen(), server: restoreServer));
    await tester.pump(const Duration(milliseconds: 200));
    final upBtn = find.byKey(const Key('restoration-upload'));
    await tester.tap(upBtn);
    await tester.pump();
    await tester.tap(upBtn);
    await tester.pump();
    expect(picker2.pickCalls, 1);
    gate2.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    final picker3 = _GatePicker(wavPath, wavBytes);
    FilePicker.platform = picker3;
    final txGate = Completer<void>();
    picker3.saveGate = txGate;
    final txServer = ServerConfig();
    await txServer.saveServerUrl('http://127.0.0.1:8000');
    txServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/music/transcribe')) {
        return ResponseBody.fromString(
          jsonEncode({
            'sha': 'abcdef123456',
            'bpm': 60,
            'label': 'Basic Pitch',
            'notes': [
              {'midi': 60, 'start': 0.1, 'end': 0.5, 'note': 'C4', 'hue_scale': 'Ho'}
            ],
          }),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromBytes(Uint8List.fromList([1, 2, 3]), 200);
    });
    await tester.pumpWidget(_wrapProviders(const TranscriptionScreen(), server: txServer));
    await tester.pump();
    await tester.tap(find.text(s.transcribePickBtn));
    for (var i = 0; i < 15 && find.textContaining('sample.wav').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('sample.wav'), findsOneWidget);
    await tester.ensureVisible(find.text(s.transcribeRunBtn));
    await tester.tap(find.text(s.transcribeRunBtn));
    await tester.pumpAndSettle();
    final midiBtn = find.text(s.transcribeMidiBtn);
    final xmlBtn = find.text(s.transcribeXmlBtn);
    expect(midiBtn, findsOneWidget);
    expect(xmlBtn, findsOneWidget);
    await tester.ensureVisible(midiBtn);
    await tester.tap(midiBtn);
    await tester.pump();
    await tester.tap(xmlBtn, warnIfMissed: false);
    await tester.pump();
    expect(picker3.saveCalls, 1);
    txGate.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('C4 Admin Dashboard/Learning/Crash shared states + double-tap locks + Onboarding double-submit', (tester) async {
    const s = AppStrings('vi');
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int revokeCalls = 0;
    final revokeGate = Completer<void>();
    final loginServer = ServerConfig();
    await loginServer.saveServerUrl('http://127.0.0.1:8000');
    loginServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/auth/revoke-all')) {
        revokeCalls++;
        await revokeGate.future;
        return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
      }
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    });
    final loginAuth = AuthService();
    await loginAuth.save(token: 'tok', username: 'user1', role: 'user');
    await tester.pumpWidget(_wrapProviders(const LoginScreen(), server: loginServer, auth: loginAuth));
    await tester.pump();
    final logoutEveryBtn = find.widgetWithText(OutlinedButton, s.logoutEverywhereBtn);
    await tester.ensureVisible(logoutEveryBtn);
    await tester.tap(logoutEveryBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.commonOk));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(logoutEveryBtn, warnIfMissed: false);
    await tester.pump();
    expect(revokeCalls, 1);
    revokeGate.complete();
    await tester.pumpAndSettle();

    final adminServer = ServerConfig();
    await adminServer.saveServerUrl('http://127.0.0.1:8000');
    adminServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/admin/stats') || opt.path.contains('/api/admin/crash-reports')) {
        return ResponseBody.fromString('{"detail":"err"}', 400, headers: _jsonHeaders);
      }
      if (opt.path.contains('/api/lessons')) {
        return ResponseBody.fromString('[]', 200, headers: _jsonHeaders);
      }
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    });
    final adminAuth = AuthService();
    await adminAuth.save(token: 'adm', username: 'ghitatruongle', role: 'admin');
    await tester.pumpWidget(_wrapProviders(const AdminScreen(), server: adminServer, auth: adminAuth));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ErrorPanel), findsOneWidget);

    await tester.tap(find.text(s.adminTabLearning));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);

    await tester.tap(find.text(s.adminTabCrash));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_wrapProviders(const ServerOnboardingDialog()));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'http://127.0.0.1:8000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('C3 CreationScreen tab switch avoids excess full rebuilds and TaskResultCard disables Cancel when cancelling', (tester) async {
    const s = AppStrings('vi');
    int cancelCalls = 0;
    final creationServer = ServerConfig();
    await creationServer.saveServerUrl('http://127.0.0.1:8000');
    creationServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/music/heritage-tunes')) {
        return ResponseBody.fromString(
          jsonEncode([
            {'id': 't1', 'title': 'Nam Ai', 'type': 'Ca Hue', 'artist': 'NS', 'sha256': 's1', 'size': 1024}
          ]),
          200,
          headers: _jsonHeaders,
        );
      }
      if (opt.path.contains('/api/music/models')) {
        return ResponseBody.fromString(
          jsonEncode({'base': 'b', 'base_ready': true, 'mode': 'm', 'adapters': []}),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    });
    await tester.pumpWidget(_wrapProviders(const CreationScreen(), server: creationServer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(s.creationTabNewLyrics));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wizard-steps')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _wrapProviders(
        TaskResultCard(
          task: MusicTask(id: 't1', kind: 'sing', status: 'running', audioUrl: '', reason: ''),
          polling: true,
          cancelling: true,
          onCancel: (_) => cancelCalls++,
        ),
        server: creationServer,
      ),
    );
    await tester.tap(find.text(s.cancelBtn), warnIfMissed: false);
    await tester.pump();
    expect(cancelCalls, 0);

    bool failAccounts = false;
    final accServer = ServerConfig();
    await accServer.saveServerUrl('http://127.0.0.1:8000');
    accServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (failAccounts) {
        return ResponseBody.fromString('{"detail":"err"}', 400, headers: _jsonHeaders);
      }
      if (opt.path.contains('/api/auth/users')) {
        return ResponseBody.fromString(
          jsonEncode({
            'items': [
              {'id': 'u1', 'username': 'user1', 'email': 'u@example.com', 'role': 'user', 'active': true}
            ],
            'total': 1,
          }),
          200,
          headers: _jsonHeaders,
        );
      }
      if (opt.path.contains('/api/auth/invites')) {
        return ResponseBody.fromString(
          jsonEncode({
            'items': [
              {'id': 'i1', 'code': 'HUE-1111', 'used': false, 'note': ''}
            ],
            'total': 1,
          }),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    });
    final mgrAuth = AuthService();
    await mgrAuth.save(token: 'adm', username: 'ghitatruongle', role: 'admin');
    await tester.pumpWidget(_wrapProviders(const AccountManagerSection(), server: accServer, auth: mgrAuth));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('user1'), findsOneWidget);
    failAccounts = true;
    await tester.tap(find.byTooltip(s.adminRefresh));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ErrorPanel), findsOneWidget);

    failAccounts = false;
    await tester.pumpWidget(_wrapProviders(const InviteManagerSection(), server: accServer, auth: mgrAuth));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('HUE-1111'), findsOneWidget);
    failAccounts = true;
    await tester.tap(find.byTooltip(s.adminRefresh));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C3-4 ResponsiveScaffold sidebar and TabMotion obey disableAnimations', (tester) async {
    const s = AppStrings('vi');
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget buildShell(int selectedIndex, bool disableAnimations) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(disableAnimations: disableAnimations),
              child: ResponsiveScaffold(
                selectedIndex: selectedIndex,
                onDestinationSelected: (_) {},
                destinations: const [
                  NavigationDestinationItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home,
                    labelKey: 'home',
                    screen: Center(child: Text('Tab0')),
                  ),
                  NavigationDestinationItem(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    labelKey: 'settings',
                    screen: Center(child: Text('Tab1')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildShell(0, true));
    await tester.pump();
    final collapsedAnim = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
    expect(collapsedAnim.duration, Duration.zero);

    await tester.tap(find.byTooltip(s.collapseSidebar));
    await tester.pump();
    expect(find.byTooltip(s.expandSidebar), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(buildShell(1, true));
    await tester.pump();
    expect(find.text('Tab1'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(buildShell(1, false));
    await tester.pump();
    final normalAnim = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
    expect(normalAnim.duration, AppMotion.base);
  });

  test('C4-4 ApiClient.describe hides raw non-Dio exceptions and localizes cleanly', () {
    final unknownMsg = ApiClient.describe(StateError('raw http://192.168.1.99:8000/secret Traceback line 42'));
    expect(unknownMsg, 'Lỗi không xác định khi gọi API.');
    expect(unknownMsg.contains('raw'), isFalse);
    expect(unknownMsg.contains('192.168'), isFalse);
    expect(unknownMsg.contains('Traceback'), isFalse);

    final formatMsg = ApiClient.describe(const FormatException('Unexpected token < in JSON'));
    expect(formatMsg, 'Dữ liệu phản hồi không đúng định dạng.');
    expect(formatMsg.contains('Unexpected'), isFalse);

    final timeoutMsg = ApiClient.describe(TimeoutException('timed out after 30s'));
    expect(timeoutMsg, 'Kết nối máy chủ quá chậm hoặc quá hạn.');
    expect(timeoutMsg.contains('timed out'), isFalse);
  });

  testWidgets('C4-5 TranscriptionScreen ErrorPanel exposes Retry on API failure and omits on validation error', (tester) async {
    const s = AppStrings('vi');
    final picker = _GatePicker(wavPath, wavBytes);
    final origPicker = FilePicker.platform;
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = origPicker);

    int transcribeCalls = 0;
    final server = ServerConfig();
    await server.saveServerUrl('http://127.0.0.1:8000');
    server.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/music/transcribe')) {
        transcribeCalls++;
        if (transcribeCalls == 1) {
          return ResponseBody.fromString('{"detail":"fail"}', 500, headers: _jsonHeaders);
        }
        return ResponseBody.fromString(
          jsonEncode({
            'label': 'Basic Pitch',
            'bpm': 60,
            'sha': 'abcdef123456',
            'notes': [
              {'midi': 60, 'start': 0.0, 'end': 0.5}
            ],
          }),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    });

    await tester.pumpWidget(_wrapProviders(const TranscriptionScreen(), server: server));
    await tester.pump();

    await tester.ensureVisible(find.text(s.transcribeRunBtn));
    await tester.tap(find.text(s.transcribeRunBtn));
    await tester.pump();
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(find.text(s.transcribePickFile), findsOneWidget);
    expect(find.byTooltip(s.learnRetry), findsNothing);

    await tester.ensureVisible(find.text(s.transcribePickBtn));
    await tester.tap(find.text(s.transcribePickBtn));
    for (var i = 0; i < 10 && find.textContaining('sample.wav').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.byType(ErrorPanel), findsNothing);

    await tester.ensureVisible(find.text(s.transcribeRunBtn));
    await tester.tap(find.text(s.transcribeRunBtn));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(transcribeCalls, 1);
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(find.byTooltip(s.learnRetry), findsOneWidget);

    await tester.ensureVisible(find.byTooltip(s.learnRetry));
    await tester.tap(find.byTooltip(s.learnRetry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(transcribeCalls, 2);
    expect(find.byType(ErrorPanel), findsNothing);
    expect(find.byType(SheetMusicView), findsOneWidget);
  });

  testWidgets('C4-6 ScalePracticeCard renders inline ErrorPanel with Retry inside card and clears on change', (tester) async {
    const s = AppStrings('vi');
    int retried = 0;
    final scale = ScaleInfo(id: 's1', name: 'Nam Ai', noteNames: const ['Ho', 'Xu']);
    await tester.pumpWidget(
      _wrapProviders(
        SingleChildScrollView(
          child: ScalePracticeCard(
            scales: [scale],
            selected: scale,
            onChanged: (_) {},
            recording: false,
            onToggleRecord: () {},
            busy: false,
            onSubmit: () {},
            recordPath: wavPath,
            result: null,
            transpose: 0,
            onTransposeChanged: (_) {},
            errorMessage: 'Loi thu thang am',
            onRetryError: () => retried++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(of: find.byType(ScalePracticeCard), matching: find.byType(ErrorPanel)),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byTooltip(s.learnRetry));
    await tester.tap(find.byTooltip(s.learnRetry));
    await tester.pump();
    expect(retried, 1);

    final practiceServer = ServerConfig();
    await practiceServer.saveServerUrl('http://127.0.0.1:8000');
    practiceServer.api.dio.httpClientAdapter = _GateMockAdapter((opt) async {
      if (opt.path.contains('/api/lessons/scales')) {
        return ResponseBody.fromString(
          jsonEncode([
            {'id': 's1', 'name': 'Nam Ai', 'notes': ['Ho', 'Xu']},
            {'id': 's2', 'name': 'Nam Xuan', 'notes': ['Ho', 'Su']},
          ]),
          200,
          headers: _jsonHeaders,
        );
      }
      if (opt.path.contains('/api/lessons')) {
        return ResponseBody.fromString(
          jsonEncode([
            {'id': 'l1', 'title': 'Bai 1', 'type': 'Ca Hue', 'artist': 'NS', 'mode_system': 'Nam', 'bpm': 60, 'has_ornaments': false, 'sections': 1}
          ]),
          200,
          headers: _jsonHeaders,
        );
      }
      return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
    });

    allowMicPermission = false;
    try {
      await tester.pumpWidget(_wrapProviders(const LessonPracticeView(), server: practiceServer));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.ensureVisible(find.text(s.practiceScaleRecord));
      await tester.tap(find.text(s.practiceScaleRecord));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.descendant(of: find.byType(ScalePracticeCard), matching: find.text(s.practiceMicDenied)),
        findsOneWidget,
      );
      expect(find.byType(ErrorPanel), findsOneWidget);

      await tester.ensureVisible(find.text('Nam Ai').first);
      await tester.tap(find.text('Nam Ai').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Nam Xuan').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ErrorPanel), findsNothing);
    } finally {
      allowMicPermission = true;
    }
  });
}
