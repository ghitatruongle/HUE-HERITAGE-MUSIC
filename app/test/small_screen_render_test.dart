import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/analysis/analysis_screen.dart';
import 'package:hue_heritage_music/screens/heritage/heritage_list_screen.dart';
import 'package:hue_heritage_music/screens/history/history_screen.dart';
import 'package:hue_heritage_music/screens/transcription/transcription_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';

Widget _wrap(Widget child, {bool dark = false}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
      ChangeNotifierProvider<SessionMedia>.value(value: SessionMedia()),
    ],
    child: MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _pumpSmall(WidgetTester tester, Widget screen, {required bool dark}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(screen, dark: dark));
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  testWidgets('Transcription 360dp dark - khong overflow', (tester) async {
    await _pumpSmall(tester, const TranscriptionScreen(), dark: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transcription 360dp light - khong overflow', (tester) async {
    await _pumpSmall(tester, const TranscriptionScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('History 360dp 2 theme - khong overflow', (tester) async {
    await _pumpSmall(tester, const HistoryScreen(), dark: true);
    expect(tester.takeException(), isNull);
    await _pumpSmall(tester, const HistoryScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Analysis 360dp 2 theme - khong overflow', (tester) async {
    await _pumpSmall(tester, const AnalysisScreen(), dark: true);
    expect(tester.takeException(), isNull);
    await _pumpSmall(tester, const AnalysisScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Heritage (offline) 360dp 2 theme - khong overflow', (tester) async {
    await _pumpSmall(tester, const HeritageListScreen(), dark: true);
    expect(tester.takeException(), isNull);
    await _pumpSmall(tester, const HeritageListScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });
}
