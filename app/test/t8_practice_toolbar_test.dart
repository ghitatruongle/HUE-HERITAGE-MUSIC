import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/screens/learning/lesson_practice_view.dart';
import 'package:hue_heritage_music/screens/learning/scale_practice_card.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/result_card.dart';
import 'package:provider/provider.dart';

const String _lessonTitle = 'T8 Bai hoc Tinh Tang';

const Map<String, dynamic> _lessonJson = {
  'id': 't8-lesson',
  'title': _lessonTitle,
  'type': 'Ca Hue',
  'artist': 'Nghe nhan T8',
  'mode_system': 'Nam',
  'bpm': 60,
  'has_ornaments': false,
  'sections': 2,
};

const Map<String, dynamic> _lessonDetailJson = {
  'id': 't8-lesson',
  'title': _lessonTitle,
  'lyrics': 'Tinh tang\nO ho',
  'mode_system': 'Nam',
  'bpm': 60,
  'sections': [
    {'index': 0, 'start': 0, 'end': 4, 'duration': 4, 'lyrics': 'Tinh tang', 'has_sample': false, 'sample_url': ''},
    {'index': 1, 'start': 4, 'end': 8, 'duration': 4, 'lyrics': 'O ho', 'has_sample': false, 'sample_url': ''},
  ],
  'contour': {'times': [], 'f0': []},
};

class _T8MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/api/lessons/scales')) {
      return ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (options.path.contains('/api/lessons/my-progress')) {
      return ResponseBody.fromString('{"items":[]}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (options.path.contains('/api/lessons/t8-lesson')) {
      return ResponseBody.fromString(
        jsonEncode(_lessonDetailJson),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path.contains('/api/lessons')) {
      return ResponseBody.fromString(
        jsonEncode([_lessonJson]),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

Widget _wrap(Widget screen, {required bool dark, ServerConfig? server}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server ?? ServerConfig()),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
      ChangeNotifierProvider<SessionMedia>.value(value: SessionMedia()),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(body: screen),
    ),
  );
}

Future<void> _loadBundledFonts() async {
  final be = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    be.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$f.ttf'));
  }
  await be.load();
  final playfair = FontLoader('PlayfairDisplay')
    ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay.ttf'));
  playfair.addFont(rootBundle.load('assets/fonts/PlayfairDisplay-SemiBold.ttf'));
  playfair.addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Bold.ttf'));
  await playfair.load();
}

Future<void> _pumpLessonPage(WidgetTester tester, {required bool dark}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.reset);
  final server = ServerConfig();
  server.api.dio.httpClientAdapter = _T8MockAdapter();
  await tester.pumpWidget(_wrap(const LessonPracticeView(), dark: dark, server: server));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.tap(find.byType(DropdownButtonFormField<Lesson>));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(_lessonTitle).last);
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

ScalePractice _mockScaleResult() {
  return ScalePractice(
    score: 86,
    pitchScore: 90,
    rhythmScore: 82,
    stabilityScore: 88,
    scaleName: 'Ngu cung',
    onScaleShare: 0.92,
    transpose: 0,
    notes: [
      ScaleNoteHit(name: 'khong', share: 0.95, hit: true),
      ScaleNoteHit(name: 'bon', share: 0.4, hit: false),
    ],
    performance: [
      ScalePerformanceNote(
        name: 'khong',
        errCents: 12,
        onsetErrMs: 40,
        verdict: 'In tune',
        verdictCode: 'ok',
        hint: '',
        hintCodes: const [],
      ),
      ScalePerformanceNote(
        name: 'bon',
        errCents: -35,
        onsetErrMs: 90,
        verdict: 'Slightly off',
        verdictCode: 'minor',
        hint: '',
        hintCodes: const [],
      ),
    ],
    summaryHint: '',
    verdictCounts: const {'ok': 1, 'minor': 1},
    summaryCodes: const [],
  );
}

void main() {
  setUpAll(() async {
    await _loadBundledFonts();
  });

  testWidgets('Toolbar toan cuc: dung 2 Switch thay vi 2xN khi mo bai 2 cau', (tester) async {
    await _pumpLessonPage(tester, dark: false);
    expect(find.byType(DropdownButtonFormField<Lesson>), findsOneWidget);
    expect(find.text(_lessonTitle), findsWidgets);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Toggle auto-grade tren toolbar doi state count-in giu nguyen', (tester) async {
    await _pumpLessonPage(tester, dark: false);
    expect(find.byType(Switch), findsNWidgets(2));
    final countInBefore = tester.widget<Switch>(find.byType(Switch).at(0)).value;
    final autoGradeBefore = tester.widget<Switch>(find.byType(Switch).at(1)).value;
    expect(countInBefore, isTrue);
    expect(autoGradeBefore, isFalse);
    await tester.ensureVisible(find.byType(Switch).at(1));
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump(const Duration(milliseconds: 100));
    final autoGradeAfter = tester.widget<Switch>(find.byType(Switch).at(1)).value;
    final countInAfter = tester.widget<Switch>(find.byType(Switch).at(0)).value;
    expect(autoGradeAfter, isTrue);
    expect(countInAfter, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ScalePracticeCard ket qua mock: ResultSummaryCard + 3 ScoreBadge ca 2 theme', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.reset);
    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _T8MockAdapter();
    final scale = ScaleInfo(id: 'ngu-cung', name: 'Ngu cung', noteNames: ['khong', 'bon', 'xang', 'xu', 'cang']);
    final card = ScalePracticeCard(
      scales: [scale],
      selected: scale,
      onChanged: (_) {},
      recording: false,
      onToggleRecord: () {},
      busy: false,
      onSubmit: () {},
      recordPath: null,
      result: _mockScaleResult(),
      transpose: 0,
      onTransposeChanged: (_) {},
    );
    for (final dark in [false, true]) {
      await tester.pumpWidget(_wrap(
        SingleChildScrollView(child: card),
        dark: dark,
        server: server,
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(ResultSummaryCard), findsOneWidget);
      expect(find.byType(ScoreBadge), findsNWidgets(3));
      expect(find.byType(MetricRow), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
