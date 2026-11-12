import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/admin/admin_screen.dart';
import 'package:hue_heritage_music/screens/analysis/analysis_screen.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/heritage/heritage_list_screen.dart';
import 'package:hue_heritage_music/screens/history/history_screen.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/screens/learning/learning_screen.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/screens/transcription/transcription_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:provider/provider.dart';

const List<Size> _sizes = [
  Size(320, 640),
  Size(360, 740),
  Size(600, 900),
  Size(768, 1024),
  Size(1024, 768),
  Size(1280, 800),
  Size(1600, 1000),
];

const Map<String, dynamic> _tuneJson = {
  'id': 'matrix-1',
  'title': 'Bai ca matrix',
  'type': 'Ca Hue',
  'artist': 'Nghe nhan',
  'lyrics': 'Tinh tang',
  'sha256': 'abcd',
  'size': 10,
  'created_at': '2026-11-11T00:00:00Z',
};

class _TuneMockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/api/music/models')) {
      return ResponseBody.fromString(
        '{"base":"base","base_ready":true,"mode":"test","adapters":[]}',
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path.contains('/api/music/heritage-tunes') ||
        options.path.contains('/api/heritage')) {
      return ResponseBody.fromString(
        jsonEncode([_tuneJson]),
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
  await playfair.load();
}

Future<void> _sweep(WidgetTester tester, Widget screen) async {
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final server = ServerConfig();
  server.api.dio.httpClientAdapter = _TuneMockAdapter();
  for (final dark in [false, true]) {
    for (final size in _sizes) {
      tester.view.physicalSize = size;
      final captured = <String>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        captured.add(details.toString());
        prevOnError?.call(details);
      };
      await tester.pumpWidget(_wrap(screen, dark: dark, server: server));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      FlutterError.onError = prevOnError;
      final err = tester.takeException();
      if (err != null || captured.isNotEmpty) {
        fail('overflow/render tai ${size.width}x${size.height} ${dark ? "dark" : "light"}:\n'
            'takeException=$err\n'
            'diagnostics=${captured.take(2).join("\n-----\n")}');
      }
    }
  }
}

void main() {
  setUpAll(() async {
    await _loadBundledFonts();
  });

  testWidgets('Home 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const HomeScreen());
  });

  testWidgets('Heritage (co du lieu) 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const HeritageListScreen());
  });

  testWidgets('History 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const HistoryScreen());
  });

  testWidgets('Creation (co du lieu) 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const CreationScreen());
  });

  testWidgets('Restoration (co du lieu) 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const RestorationScreen());
  });

  testWidgets('Learning 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const LearningScreen());
  });

  testWidgets('Analysis 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const AnalysisScreen());
  });

  testWidgets('Transcription 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const TranscriptionScreen());
  });

  testWidgets('Settings 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const SettingsScreen());
  });

  testWidgets('Login 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const LoginScreen());
  });

  testWidgets('Admin 7 kich thuoc x 2 theme', (tester) async {
    await _sweep(tester, const AdminScreen());
  });
}
