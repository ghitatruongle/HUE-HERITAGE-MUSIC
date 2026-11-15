import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/history/history_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/heritage_motif.dart';
import 'package:hue_heritage_music/widgets/waveform_view.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget screen, {bool dark = false}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
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

void main() {
  setUpAll(() async {
    final be = FontLoader('BeVietnamPro');
    for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      be.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$f.ttf'));
    }
    await be.load();
    final pf = FontLoader('PlayfairDisplay');
    for (final f in ['PlayfairDisplay.ttf', 'PlayfairDisplay-SemiBold.ttf', 'PlayfairDisplay-Bold.ttf']) {
      pf.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await pf.load();
  });

  testWidgets('C3: DanNguyetDisc + HeritageMotif + Waveform vẽ đúng từ 12px đến 300px, 0 exception', (tester) async {
    final sizes = [12.0, 40.0, 80.0, 160.0, 300.0];
    for (final s in sizes) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DanNguyetDisc(size: s),
                    SizedBox(
                      width: s * 3,
                      height: s,
                      child: const HeritageMotif(color: Colors.white, radius: 8),
                    ),
                    SizedBox(
                      width: s * 3,
                      height: math.max(20.0, s * 0.4),
                      child: const HeritageMotif(color: Colors.white, radius: 0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'painter size=$s vẽ lỗi');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final peaksSmall = [0.5];
    final peaksWide = List<double>.generate(500, (i) => (math.sin(i / 5.0) + 1) / 2);
    for (final peaks in [peaksSmall, peaksWide]) {
      for (final width in [40.0, 160.0, 600.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: WaveformView(data: WaveformData(peaks)),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'waveform peaks=${peaks.length} width=$width vẽ lỗi');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('C3: scroll danh sách 200 mục — frame build trung bình < 8ms', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(800, 600);
    final history = HistoryService();
    for (var i = 0; i < 200; i++) {
      history.add(
        HistoryEntry(
          id: 'e$i',
          kind: 'practice',
          title: 'Bài ca Tình Tang — Ơ hò a í a #$i',
          status: 'done',
          at: DateTime(2026, 11, 1).add(Duration(minutes: i)),
          score: 70 + (i % 30).toDouble(),
          detail: 'lesson-$i',
        ),
      );
    }
    await tester.pumpWidget(_wrap(const HistoryScreen()));
    await tester.pumpAndSettle();

    final samples = <double>[];
    final scrollable = find.descendant(
      of: find.byType(HistoryScreen),
      matching: find.byWidgetPredicate((w) => w is Scrollable),
    ).first;
    for (var i = 0; i < 12; i++) {
      final sw = Stopwatch()..start();
      await tester.drag(scrollable, const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 80));
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    }
    final sorted = samples.toList()..sort();
    final median = sorted[sorted.length ~/ 2];
    // ignore: avoid_print
    print('PERF-GATE-C3 scroll median=${median.toStringAsFixed(2)}ms avg=${(samples.reduce((a, b) => a + b) / samples.length).toStringAsFixed(2)}ms worst=${sorted.last.toStringAsFixed(2)}ms n=${samples.length}');
    expect(median, lessThan(8.0), reason: 'scroll frame median $median ms vượt gate 8ms');
  });
}
