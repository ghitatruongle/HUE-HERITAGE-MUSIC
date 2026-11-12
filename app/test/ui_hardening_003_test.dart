import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/heritage_motif.dart';
import 'package:provider/provider.dart';

const Map<String, dynamic> _tuneJson = {
  'id': 'tune-1',
  'title': 'Bai ca Kinh thanh Hue',
  'type': 'Ca Hue',
  'artist': 'Nghe nhan kiem dinh',
  'lyrics': 'Tinh tang tinh tang\nO ho a í a',
  'sha256': 'deadbeef',
  'size': 123,
  'created_at': '2026-11-11T00:00:00Z',
};

class _CreationMockAdapter implements HttpClientAdapter {
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
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    if (options.path.contains('/api/music/heritage-tunes')) {
      return ResponseBody.fromString(
        jsonEncode([_tuneJson]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  final locale = LocaleProvider()..setLocale('vi');
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: locale),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('HeritageMotif and VinylDisc render without exceptions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HeritageMotif(
                color: Colors.white,
                opacity: 0.1,
                child: SizedBox(width: 220, height: 90),
              ),
              VinylDisc(size: 80),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(HeritageMotif), findsOneWidget);
    expect(find.byType(VinylDisc), findsOneWidget);
  });

  testWidgets(
      'Creation lyrics text follows theme onSurface color in light mode',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final server = ServerConfig();
    server.api.dio.httpClientAdapter = _CreationMockAdapter();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(
              value: LocaleProvider()..setLocale('vi')),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CreationScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final expected = AppTheme.lightTheme.colorScheme.onSurface;
    const banned = Color(0xFFE2DCED);

    final selectables =
        tester.widgetList<SelectableText>(find.byType(SelectableText)).toList();
    expect(selectables, isNotEmpty);
    for (final st in selectables) {
      final color = st.style?.color;
      if (color != null) {
        expect(color, isNot(banned),
            reason: 'hardcoded light-theme lavender leaked into Creation');
      }
    }
    final lyrics =
        selectables.firstWhere((s) => (s.data ?? '').contains('Tinh tang'));
    expect(lyrics.style?.color, expected);
  });

  testWidgets('Login no-reset note uses theme-aware colors in light mode',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester
        .pumpWidget(_wrap(const LoginScreen(), brightness: Brightness.light));
    await tester.pump();
    await tester.pumpAndSettle();

    final noteFinder = find.textContaining('Liên hệ quản trị viên');
    expect(noteFinder, findsOneWidget);
    final noteText = tester.widget<Text>(noteFinder);
    expect(noteText.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
    expect(noteText.style?.color, isNot(Colors.brown));
  });

  testWidgets(
      'Login no-reset note renders in dark mode without light-amber box',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester
        .pumpWidget(_wrap(const LoginScreen(), brightness: Brightness.dark));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Liên hệ quản trị viên'), findsOneWidget);

    final noteFinder = find.textContaining('Liên hệ quản trị viên');
    final container = tester.widget<Container>(
      find.ancestor(of: noteFinder, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration as BoxDecoration;
    final bg = decoration.color!;
    expect(bg, isNot(Colors.amber.shade50));
    expect(bg.computeLuminance(), lessThan(0.35));
  });
}
