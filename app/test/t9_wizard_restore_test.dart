import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/models/music_task.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/creation/task_result_card.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/widgets/audio_player_bar.dart';
import 'package:hue_heritage_music/widgets/hue_chip.dart';
import 'package:hue_heritage_music/widgets/result_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _itemJson(String id) => <String, dynamic>{
      'id': id,
      'title': 'Bai $id',
      'type': 'Nha nhac',
      'artist': 'Nghe nhan',
      'sha256': 'sha-$id',
      'size': 1024,
      'created_at': '2026-01-01',
    };

Map<String, dynamic> get _restoreJson => <String, dynamic>{
      'label': 'Ban phuc che',
      'sha': 'sha-restored',
      'sample_rate': 44100,
      'duration': 12.5,
      'dc_removed': 0.0123,
      'clicks_fixed': 3,
      'peak_before': 0.9,
      'peak_after': 0.95,
      'noise_floor_db': -60.0,
    };

Map<String, List<String>> get _jsonHeaders => {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };

class _T9MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.contains('/api/music/restore-item/')) {
      return ResponseBody.fromString(jsonEncode(_restoreJson), 200, headers: _jsonHeaders);
    }
    if (path.contains('/api/music/heritage-tunes')) {
      return ResponseBody.fromString(
        jsonEncode([_itemJson('t1'), _itemJson('t2')]),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/models')) {
      return ResponseBody.fromString(
        jsonEncode({'base': 'base', 'base_ready': true, 'mode': 'test', 'adapters': []}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/heritage')) {
      return ResponseBody.fromString(
        jsonEncode({'items': [_itemJson('h1'), _itemJson('h2')], 'total': 2}),
        200,
        headers: _jsonHeaders,
      );
    }
    return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
  }

  @override
  void close({bool force = false}) {}
}

void _mockAudioPlatform() {
  JustAudioPlatform.instance = _FakeJustAudio();
}

class _FakeJustAudio extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async => _FakePlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

class _FakePlayer extends AudioPlayerPlatform {
  static final Set<String> calls = {};
  static bool emitReady = false;

  _FakePlayer(super.id);

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      emitReady ? Stream.value(_readyEvent()) : const Stream.empty();

  static PlaybackEventMessage _readyEvent() => PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: const Duration(minutes: 3),
        icyMetadata: null,
        currentIndex: null,
        androidAudioSessionId: null,
      );

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    calls.add('load');
    return LoadResponse(duration: null);
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    calls.add('setVolume');
    return SetVolumeResponse();
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    calls.add('play');
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    calls.add('pause');
    return PauseResponse();
  }

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
  Future<DisposeResponse> dispose(DisposeRequest request) async => DisposeResponse();

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
      AndroidEqualizerGetParametersResponse(parameters: AndroidEqualizerParametersMessage(minDecibels: -20, maxDecibels: 20, bands: const <AndroidEqualizerBandMessage>[]));

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
          AndroidEqualizerBandSetGainRequest request) async =>
      AndroidEqualizerBandSetGainResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
          SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse();
}

Future<void> _pumpRestoration(WidgetTester tester, ThemeData theme) async {
  _mockAudioPlatform();
  final server = ServerConfig();
  server.api.dio.httpClientAdapter = _T9MockAdapter();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ServerConfig>.value(value: server),
        ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
        ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
      ],
      child: MaterialApp(
        theme: theme,
        home: const Scaffold(body: RestorationScreen()),
      ),
    ),
  );
}

Future<void> _runRestorationAndExpectMetrics(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await _pumpRestoration(tester, theme);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  expect(tester.takeException(), isNull);

  for (var i = 0; i < 10 && find.text('Bai h1').evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  }
  // ignore: avoid_print
  print('T9-REST-TEXTS ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText()).whereType<String>().take(24).join(' | ')}');
  expect(find.text('Bai h1'), findsWidgets);

  await tester.tap(find.text('Phục dựng').first);
  for (var i = 0; i < 30 && find.byType(ResultSummaryCard).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  }

  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  }

  expect(tester.takeException(), isNull);
  expect(find.byType(ResultSummaryCard), findsOneWidget);
  expect(find.byType(MetricRow), findsNWidgets(6));
  expect(find.text('Chỉ số Kỹ thuật Phục dựng DSP'), findsOneWidget);
  expect(find.text('44100 Hz'), findsOneWidget);
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  testWidgets('T9 restoration metrics card renders in dark theme workspace', (tester) async {
    await _runRestorationAndExpectMetrics(tester, AppTheme.darkTheme);
  });

  testWidgets('T9 restoration metrics card renders in light theme workspace', (tester) async {
    await _runRestorationAndExpectMetrics(tester, AppTheme.lightTheme);
  });

  testWidgets('T9 creation new-lyrics wizard navigates between 3 steps', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    _mockAudioPlatform();
    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _T9MockAdapter();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: CreationScreen(initialTabIndex: 1)),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 10 && find.byType(HueChip).evaluate().length < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    }

    expect(find.byType(HueChip), findsNWidgets(3));
    expect(find.byKey(const Key('wizard-steps')), findsOneWidget);
    expect(_wizardIndex(tester), 0);
    expect(find.text('Quay lại'), findsNothing);

    await tester.tap(find.text('Tiếp'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_wizardIndex(tester), 1);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);

    await tester.tap(find.text('Giọng & phong cách'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_wizardIndex(tester), 2);
    final ddFinder = find.byWidgetPredicate((w) => w is DropdownButtonFormField);
    await tester.ensureVisible(ddFinder.first);
    await tester.pump();
    expect(find.byType(TextField).hitTestable(), findsNothing);
    expect(ddFinder.hitTestable(), findsAtLeastNWidgets(1));
    expect(find.text('Tiếp'), findsNothing);
    expect(find.text('Quay lại'), findsOneWidget);

    await tester.tap(find.text('Quay lại'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_wizardIndex(tester), 1);

    await tester.tap(find.text('Chọn điệu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_wizardIndex(tester), 0);
    expect(find.text('Quay lại'), findsNothing);
    expect(find.text('Tiếp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T9 TaskResultCard running shows gold polling ring without fake percent', (tester) async {
    final task = MusicTask(id: 'task-1', kind: 'sing_new_lyrics', status: 'running', reason: '');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: TaskResultCard(task: task, polling: true, onCancel: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('running'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(spinner.strokeWidth, 1.6);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration! as BoxDecoration).border is Border &&
            ((w.decoration! as BoxDecoration).border! as Border).top.width == 1.4,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(AudioPlayerBar), findsNothing);
    expect(find.text('Hủy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T9 restore-upload loi thi entry lich su chuyen sang error', (tester) async {
    _mockAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final wavDir = Directory.systemTemp.createTempSync('t9_upload');
    final wavFile = File('${wavDir.path}/take.wav')..writeAsBytesSync(Uint8List(64));
    addTearDown(() {
      try {
        wavDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final history = HistoryService();
    final server = ServerConfig();
    await server.saveServerUrl('http://127.0.0.1:9000');
    server.api.dio.httpClientAdapter = _T9UploadFailAdapter();
    FilePicker.platform = _T9FakePicker(wavFile.path, wavFile.lengthSync());
    addTearDown(() {
      history.clear();
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), null);
    });
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<HistoryService>.value(value: history),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: RestorationScreen()),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 10 && find.byKey(const Key('restoration-upload')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byKey(const Key('restoration-upload')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }

    final uploadEntries = history.entries.where((e) => e.kind == 'restore-upload').toList();
    expect(uploadEntries, isNotEmpty);
    expect(uploadEntries.first.status, 'error', reason: 'entry error mới nhất phải đứng đầu (newest-first)');
    expect(tester.takeException(), isNull);
  });

}

class _T9FakePicker extends FilePicker {
  final String path;
  final int size;
  _T9FakePicker(this.path, this.size);

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
    return FilePickerResult([
      PlatformFile(name: 'take.wav', path: path, size: size),
    ]);
  }
}

class _T9UploadFailAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.contains('/api/music/restore')) {
      return ResponseBody.fromString(jsonEncode({'detail': 'dsp boom'}), 500, headers: _jsonHeaders);
    }
    if (path.contains('/api/music/heritage-tunes')) {
      return ResponseBody.fromString(
        jsonEncode([_itemJson('t1'), _itemJson('t2')]),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/music/models')) {
      return ResponseBody.fromString(
        jsonEncode({'base': 'base', 'base_ready': true, 'mode': 'test', 'adapters': []}),
        200,
        headers: _jsonHeaders,
      );
    }
    if (path.contains('/api/heritage')) {
      return ResponseBody.fromString(
        jsonEncode({'items': [_itemJson('h1'), _itemJson('h2')], 'total': 2}),
        200,
        headers: _jsonHeaders,
      );
    }
    return ResponseBody.fromString('{}', 200, headers: _jsonHeaders);
  }

  @override
  void close({bool force = false}) {}
}

int _wizardIndex(WidgetTester tester) {
  final stack = tester.widget<IndexedStack>(find.byKey(const Key('wizard-steps')));
  return stack.index ?? 0;
}
