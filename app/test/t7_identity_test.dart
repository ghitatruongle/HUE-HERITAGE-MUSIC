import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/analysis/analysis_screen.dart';
import 'package:hue_heritage_music/screens/transcription/transcription_screen.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/widgets/feature_header.dart';
import 'package:hue_heritage_music/widgets/hue_button.dart';
import 'package:hue_heritage_music/widgets/hue_chip.dart';
import 'package:hue_heritage_music/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AppStrings _strings = AppStrings('vi');

const List<String> _t7Files = [
  'lib/screens/analysis/analysis_screen.dart',
  'lib/screens/transcription/transcription_screen.dart',
];

Widget _wrap(
  Widget child, {
  required ServerConfig server,
  required bool dark,
  SessionMedia? media,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()),
      ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
      if (media != null) ChangeNotifierProvider<SessionMedia>.value(value: media),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

Future<ServerConfig> _mockServer() async {
  SharedPreferences.setMockInitialValues({});
  final server = ServerConfig();
  await server.saveServerUrl('http://127.0.0.1:9000');
  server.api.dio.httpClientAdapter = _T7MockAdapter();
  return server;
}

File _writeTempWav(int sampleCount) {
  final dir = Directory.systemTemp.createTempSync('t7_identity');
  final file = File('${dir.path}/take.wav')..writeAsBytesSync(_pcm16Wav(sampleCount, 8000));
  return file;
}

Uint8List _pcm16Wav(int sampleCount, int sr) {
  final data = ByteData(44 + sampleCount * 2);
  data.setUint32(0, 0x46464952, Endian.little);
  data.setUint32(4, 36 + sampleCount * 2, Endian.little);
  data.setUint32(8, 0x45564157, Endian.little);
  data.setUint32(12, 0x20746D66, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sr, Endian.little);
  data.setUint32(28, sr * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(36, 0x61746164, Endian.little);
  data.setUint32(40, sampleCount * 2, Endian.little);
  for (var i = 0; i < sampleCount; i++) {
    data.setInt16(44 + i * 2, 0, Endian.little);
  }
  return data.buffer.asUint8List();
}

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

class _FakeFilePicker extends FilePicker {
  final String path;
  final int size;
  _FakeFilePicker(this.path, this.size);

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

void main() {
  testWidgets('AnalysisScreen renders FeatureHeader, StatCards and instrument chips in both themes', (tester) async {
    _useDesktopViewport(tester);
    final wav = _writeTempWav(1600);
    addTearDown(() {
      try {
        wav.parent.deleteSync(recursive: true);
      } catch (_) {}
    });

    const connectivityChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async => <String>['wifi']);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null));
    FilePicker.platform = _FakeFilePicker(wav.path, wav.lengthSync());

    for (final dark in [false, true]) {
      final server = await _mockServer();
      await tester.pumpWidget(_wrap(const AnalysisScreen(), server: server, dark: dark));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FeatureHeader), findsOneWidget);
      expect(find.text(_strings.featAnalysisTitle), findsOneWidget);
      expect(find.text(_strings.analysisHeaderSubtitle), findsOneWidget);

      await tester.tap(find.text(_strings.analysisPickBtn));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1200)));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await tester.pump(const Duration(milliseconds: 120));

      expect(tester.takeException(), isNull);
      expect(find.byType(FeatureHeader), findsOneWidget);
      expect(find.byType(StatCard), findsNWidgets(2));
      expect(find.text('220.5 Hz'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.byType(HueChip), findsNWidgets(3));
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    }
  });

  testWidgets('TranscriptionScreen renders FeatureHeader, note chips and download buttons from mock result', (tester) async {
    _useDesktopViewport(tester);
    final media = SessionMedia()..setRecording(bytes: _pcm16Wav(800, 8000));
    final server = await _mockServer();

    await tester.pumpWidget(
      _wrap(const TranscriptionScreen(), server: server, dark: false, media: media),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FeatureHeader), findsOneWidget);
    expect(find.text(_strings.featTranscriptionTitle), findsOneWidget);
    expect(find.text(_strings.transcriptionHeaderSubtitle), findsOneWidget);

    await tester.tap(find.text(_strings.transcribeUseLast));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.enterText(find.byType(TextField), '120');
    await tester.pump();

    await tester.tap(find.text(_strings.transcribeRunBtn));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.takeException(), isNull);
    expect(find.byType(FeatureHeader), findsOneWidget);
    expect(find.byType(HueChip), findsNWidgets(8));
    expect(find.textContaining('C4'), findsOneWidget);
    expect(find.textContaining('C5'), findsOneWidget);
    expect(find.byType(HueButton), findsNWidgets(3));
    expect(find.text(_strings.transcribeMidiBtn), findsOneWidget);
    expect(find.text(_strings.transcribeXmlBtn), findsOneWidget);
  });

  testWidgets('T7 screens contain no hardcoded Vietnamese outside strings getters', (tester) async {
    final vietnamese = RegExp(r'[\u00C0-\u024F\u1EA0-\u1EF9]');
    final offenders = <String>[];
    for (final path in _t7Files) {
      final lines = File(path).readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (vietnamese.hasMatch(lines[i])) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Vietnamese must go through AppStrings getters: $offenders');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('T7 screens keep design gates: HueIcons only, no heavy weights, token fontSize and radius', () {
    const fontSizes = {'10.5', '12', '13', '13.5', '14', '15', '17', '19', '22', '26'};
    const radii = {'0', '4', '8', '12', '14', '20'};
    for (final path in _t7Files) {
      final src = File(path).readAsStringSync();
      expect(
        RegExp(r'(?<!Hue)Icons\.').allMatches(src),
        isEmpty,
        reason: '$path: raw Icons.* usage is banned, use HueIcons',
      );
      expect(
        RegExp(r'\bw800\b|\bw900\b').hasMatch(src),
        isFalse,
        reason: '$path: w800/w900 is banned',
      );
      for (final m in RegExp(r'fontSize:\s*([\d.]+)').allMatches(src)) {
        expect(fontSizes.contains(m.group(1)), isTrue, reason: '$path: fontSize ${m.group(1)}');
      }
      for (final m in RegExp(r'BorderRadius\.circular\(([\d.]+)\)').allMatches(src)) {
        expect(radii.contains(m.group(1)), isTrue, reason: '$path: radius ${m.group(1)}');
      }
    }
  });
}

class _T7MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/api/music/analyze-pitch')) {
      return _json({
        'mean_f0': 220.5,
        'frames': 42,
        'times': [0.0, 1.0, 2.0],
        'f0': [210.0, 220.0, 230.0],
      });
    }
    if (options.path.contains('/api/music/instruments')) {
      return _json({
        'label': 'mock take',
        'segments': [
          {'instrument': 'Dan Nguyet', 'start': 0.0, 'end': 4.0, 'confidence': 0.85},
          {'instrument': 'Ken Bop', 'start': 4.0, 'end': 8.0, 'confidence': 0.45},
          {'instrument': 'Trong', 'start': 8.0, 'end': 12.0, 'confidence': 0.2},
        ],
      });
    }
    if (options.path.contains('/api/music/transcribe')) {
      return _json({
        'label': 'mock take',
        'bpm': 60,
        'sha': 'abcdef1234567890',
        'notes': [
          {'midi': 60, 'start': 0.0, 'end': 0.5},
          {'midi': 62, 'start': 0.5, 'end': 1.0},
          {'midi': 64, 'start': 1.0, 'end': 1.5},
          {'midi': 65, 'start': 1.5, 'end': 2.0},
          {'midi': 67, 'start': 2.0, 'end': 2.5},
          {'midi': 69, 'start': 2.5, 'end': 3.0},
          {'midi': 71, 'start': 3.0, 'end': 3.5},
          {'midi': 72, 'start': 3.5, 'end': 4.0},
        ],
      });
    }
    return _json({});
  }

  ResponseBody _json(Map<String, dynamic> payload) {
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}
