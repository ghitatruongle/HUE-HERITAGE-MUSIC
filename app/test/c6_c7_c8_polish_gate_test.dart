import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/screens/admin/admin_screen.dart';
import 'package:hue_heritage_music/screens/analysis/analysis_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/screens/transcription/transcription_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/app_logo.dart';
import 'package:hue_heritage_music/widgets/avatar_view.dart';
import 'package:hue_heritage_music/widgets/feature_header.dart';
import 'package:hue_heritage_music/widgets/hue_button.dart';
import 'package:hue_heritage_music/widgets/hue_chip.dart';
import 'package:hue_heritage_music/widgets/hue_icons.dart';
import 'package:hue_heritage_music/widgets/overlay_pitch_chart.dart';
import 'package:hue_heritage_music/widgets/responsive_layout.dart';
import 'package:hue_heritage_music/widgets/skeleton_loader.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PolishMockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('avatar')) {
      return ResponseBody.fromBytes(
        Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0xFF]),
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
    }
    if (options.path.contains('/api/music/models')) {
      return ResponseBody.fromString(
        '{"base":"base","base_ready":true,"mode":"test","adapters":[]}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final tune = {
      'id': 'polish-1',
      'title': 'Hò Mái Nhì',
      'type': 'Ca Huế',
      'artist': 'Nghệ nhân',
      'lyrics': 'Tình tang a í a',
      'lyrics_with_ornaments': 'Tình tang (luyến) a í a',
      'sha256': 'abcd1234',
      'size': 1024,
      'created_at': '2026-11-11T00:00:00Z',
    };
    if (options.path.contains('/api/music/heritage-tunes')) {
      return ResponseBody.fromString(
        jsonEncode([tune]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path.contains('/api/heritage')) {
      return ResponseBody.fromString(
        jsonEncode({'items': [tune], 'total': 1}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

double _lin(double c) {
  c /= 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color c) {
  return 0.2126 * _lin(c.r * 255.0) +
      0.7152 * _lin(c.g * 255.0) +
      0.0722 * _lin(c.b * 255.0);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _appShell(
  Widget child, {
  required ServerConfig server,
  ThemeMode mode = ThemeMode.light,
  ThemeData? theme,
  Key? appKey,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()..setMode(mode)),
      ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
      ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
    ],
    child: MaterialApp(
      key: appKey,
      theme: theme ?? (mode == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  test('C8-1/C8-2: AppFontSize định nghĩa đủ 9 bậc chuẩn thống nhất TextTheme và không còn fontSize số cứng trong lib', () {
    expect(AppFontSize.xs, 11);
    expect(AppFontSize.sm, 12);
    expect(AppFontSize.md, 13);
    expect(AppFontSize.lg, 14);
    expect(AppFontSize.xl, 15);
    expect(AppFontSize.title, 17);
    expect(AppFontSize.heading, 19);
    expect(AppFontSize.headline, 22);
    expect(AppFontSize.display, 26);
    expect(AppTheme.lightTheme.dialogTheme.titleTextStyle?.fontSize, AppFontSize.title);
    expect(AppTheme.darkTheme.dialogTheme.titleTextStyle?.fontSize, AppFontSize.title);

    final libDir = Directory('lib').existsSync() ? Directory('lib') : Directory('app/lib');
    expect(libDir.existsSync(), isTrue);

    final rawFontRe = RegExp(r'fontSize\s*:\s*[0-9]');
    final hits = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final norm = entity.path.replaceAll('\\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (norm.endsWith('core/theme/app_theme.dart') &&
            lines[i].contains('static const double')) {
          continue;
        }
        if (rawFontRe.hasMatch(lines[i])) {
          hits.add('$norm:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty, reason: 'Phát hiện fontSize số cứng chưa chuyển sang AppFontSize: $hits');
  });

  testWidgets('C6-3: HueButton.small, HueChip tương tác và OverlayPitchChart đạt >= 48dp', (tester) async {
    final result = PracticeResult.fromJson({
      'metrics': {'score': 82, 'octave_shift': 0},
      'sample': {
        'times': [0.0, 0.5, 1.0],
        'f0': [220.0, 240.0, 260.0],
      },
      'user_warped': {
        'f0': [222.0, 244.0, 262.0],
      },
      'notes': [],
      'section': {'index': 0},
      'lesson_title': 'Hò Mái Nhì',
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(visualDensity: VisualDensity.compact),
        home: Scaffold(
          body: Column(
            children: [
              HueButton(
                label: 'Nhỏ',
                size: HueButtonSize.small,
                onPressed: () {},
              ),
              HueChip(label: 'Chọn bước', onTap: () {}),
              const HueChip(label: 'Nhãn tĩnh'),
              OverlayPitchChart(result: result),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final smallBtnSize = tester.getSize(find.byType(HueButton));
    expect(smallBtnSize.height >= 48, isTrue, reason: 'HueButton small height=${smallBtnSize.height}');
    expect(smallBtnSize.width >= 48, isTrue, reason: 'HueButton small width=${smallBtnSize.width}');

    final chipInks = find.descendant(
      of: find.byType(HueChip),
      matching: find.byType(InkWell),
    );
    expect(chipInks, findsOneWidget);
    final chipInkSize = tester.getSize(chipInks.first);
    expect(chipInkSize.height >= 48, isTrue, reason: 'Interactive HueChip height=${chipInkSize.height}');
    expect(chipInkSize.width >= 48, isTrue, reason: 'Interactive HueChip width=${chipInkSize.width}');

    final filterChip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(filterChip.materialTapTargetSize, MaterialTapTargetSize.padded);
    final filterSize = tester.getSize(find.byType(FilterChip));
    expect(filterSize.height >= 48, isTrue, reason: 'FilterChip height=${filterSize.height}');
  });

  testWidgets('C6-3 + C7-1: CreationScreen ornament toggle dùng InkWell >=48dp, mẫu >=48dp và banner gold đạt AA', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    server.api.dio.httpClientAdapter = _PolishMockAdapter();
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_appShell(const CreationScreen(), server: server));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    final bannerIcon = tester.widget<Icon>(
      find.byWidgetPredicate((w) => w is Icon && w.icon == HueIcons.autoAwesome),
    );
    expect(bannerIcon.color, AppTheme.gradientAccentGold);
    for (final stop in AppTheme.brandGradientColorsLight) {
      expect(_contrast(bannerIcon.color!, stop) >= 4.5, isTrue);
    }

    final ornamentFinder = find.text(const AppStrings('vi').creationModeOrnamented);
    expect(ornamentFinder, findsOneWidget);
    final ornamentInk = find.ancestor(of: ornamentFinder, matching: find.byType(InkWell)).first;
    final ornamentSize = tester.getSize(ornamentInk);
    expect(ornamentSize.height >= 48, isTrue, reason: 'Ornament toggle height=${ornamentSize.height}');
    expect(ornamentSize.width >= 48, isTrue, reason: 'Ornament toggle width=${ornamentSize.width}');
    await tester.tap(ornamentInk);
    await tester.pump();
    expect(find.text(const AppStrings('vi').creationModePlain), findsOneWidget);

    await tester.tap(find.text(const AppStrings('vi').creationTabNewLyrics));
    await tester.pumpAndSettle();

    final sampleFinder = find.descendant(
      of: find.byKey(const Key('wizard-steps')),
      matching: find.byType(InkWell),
    );
    expect(sampleFinder, findsWidgets);
    for (final el in sampleFinder.evaluate()) {
      final sz = tester.getSize(find.byWidget(el.widget));
      expect(sz.height >= 48, isTrue, reason: 'Creation sample InkWell height=${sz.height}');
    }
  });

  testWidgets('C6-3: ResponsiveScaffold nav tiles >=48dp và RestorationScreen nút Phục hồi >=48dp', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    server.api.dio.httpClientAdapter = _PolishMockAdapter();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _appShell(
        ResponsiveScaffold(
          destinations: const [
            NavigationDestinationItem(
              icon: HueIcons.home,
              selectedIcon: HueIcons.home,
              labelKey: 'home',
              screen: SizedBox.shrink(),
              group: NavGroup.listenLearn,
            ),
            NavigationDestinationItem(
              icon: HueIcons.healing,
              selectedIcon: HueIcons.healing,
              labelKey: 'restoration',
              screen: RestorationScreen(),
              group: NavGroup.create,
              showBetaBadge: true,
            ),
          ],
          selectedIndex: 1,
          onDestinationSelected: (_) {},
        ),
        server: server,
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    final navHomeInk = find.ancestor(
      of: find.text(const AppStrings('vi').navHome),
      matching: find.byType(InkWell),
    ).first;
    expect(tester.getSize(navHomeInk).height >= 48, isTrue);

    final restoreBtn = find.widgetWithText(OutlinedButton, const AppStrings('vi').restoreActionBtn).first;
    final restoreSize = tester.getSize(restoreBtn);
    expect(restoreSize.height >= 48, isTrue);
    expect(restoreSize.width >= 48, isTrue);
  });

  testWidgets('C7-1: AvatarView corrupt bytes rơi về fallback không lỗi, FeatureHeader và SettingsScreen đạt contrast', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    server.api.dio.httpClientAdapter = _PolishMockAdapter();
    AvatarView.clearCache();

    await tester.pumpWidget(
      _appShell(
        const Column(
          children: [
            FeatureHeader(
              title: 'Kiểm thử',
              subtitle: 'Tiêu đề phụ',
              icon: HueIcons.musicNote,
            ),
            AvatarView(
              url: '/api/auth/avatar/corrupt-bytes',
              size: 56,
            ),
          ],
        ),
        server: server,
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);

    final headerIcon = tester.widget<Icon>(
      find.descendant(of: find.byType(FeatureHeader), matching: find.byType(Icon)).first,
    );
    expect(headerIcon.color, AppTheme.gradientAccentGold);
    for (final stop in AppTheme.brandGradientColorsLight) {
      expect(_contrast(headerIcon.color!, stop) >= 4.5, isTrue);
    }

    await tester.pumpWidget(
      _appShell(
        const SettingsScreen(),
        server: server,
        mode: ThemeMode.dark,
        appKey: const ValueKey('settings-dark'),
      ),
    );
    await tester.pumpAndSettle();
    final logo = tester.widget<AppLogo>(find.byType(AppLogo));
    expect(logo.iconColor, AppTheme.darkTheme.colorScheme.primary);
    expect(_contrast(logo.iconColor!, AppTheme.darkTheme.colorScheme.surface) >= 4.5, isTrue);
  });

  testWidgets('C6-1 + C6-2: HueIcon decorative tắt label trùng và Home/Nav giữ Semantics button', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    server.api.dio.httpClientAdapter = _PolishMockAdapter();
    final history = HistoryService();
    await history.add(
      HistoryEntry(id: 'rec-1', kind: 'practice', title: 'Hò Mái Nhì', status: 'done', at: DateTime(2026, 11, 24)),
    );
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              HueIcon(HueIcons.arrowForwardIos, decorative: true),
              HueIcon(HueIcons.delete),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Tiếp theo'), findsNothing);
    expect(find.bySemanticsLabel('Xóa'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final navSem = tester.getSemantics(find.text(const AppStrings('vi').navCreation).first);
    expect(navSem.flagsCollection.isButton, isTrue);

    final recentSem = tester.getSemantics(find.text('Hò Mái Nhì').first);
    expect(recentSem.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('C6-2 (G6.4): Tab di chuyển focus đúng trong AdminScreen, RestorationScreen và CreationScreen', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    server.api.dio.httpClientAdapter = _PolishMockAdapter();
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        secureChannel,
        null,
      ),
    );
    final auth = AuthService();
    await auth.save(token: 'adm-tok', username: 'ghitatruongle', role: 'admin');

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: RestorationScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    final restBefore = FocusManager.instance.primaryFocus;
    expect(restBefore, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final restAfter = FocusManager.instance.primaryFocus;
    expect(restAfter, isNotNull);
    expect(restAfter!.context, isNot(restBefore!.context));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
        ],
        child: MaterialApp(
          key: const ValueKey('admin-focus'),
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: AdminScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    final adminFields = find.byType(TextField);
    if (adminFields.evaluate().isNotEmpty) {
      await tester.tap(adminFields.first);
      await tester.pump();
      final admBefore = FocusManager.instance.primaryFocus;
      expect(admBefore, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final admAfter = FocusManager.instance.primaryFocus;
      expect(admAfter, isNotNull);
      expect(admAfter!.context, isNot(admBefore!.context));
    }

    await tester.pumpWidget(
      _appShell(const CreationScreen(initialTabIndex: 1), server: server, appKey: const ValueKey('creation-tab2')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text(const AppStrings('vi').wizardStepLyrics));
    await tester.pump(const Duration(milliseconds: 120));
    final lyricFields = find.byType(TextField);
    if (lyricFields.evaluate().isNotEmpty) {
      await tester.tap(lyricFields.first);
      await tester.pump();
      final crBefore = FocusManager.instance.primaryFocus;
      expect(crBefore, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final crAfter = FocusManager.instance.primaryFocus;
      expect(crAfter, isNotNull);
      expect(crAfter!.context, isNot(crBefore!.context));
    }
  });

  testWidgets('C7-2: AnalysisScreen và TranscriptionScreen hiển thị SkeletonLoader khi đang tải', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    final completer = Completer<ResponseBody>();
    server.api.dio.httpClientAdapter = _PendingAdapter(completer);

    const connectivityChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async => <String>['wifi']);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null));

    final wav = _miniWavBytes();
    final media = SessionMedia()..setRecording(bytes: wav);

    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_appShell(const TranscriptionScreen(), server: server, appKey: const ValueKey('tr-skel')));
    await tester.pump();
    expect(find.byType(SkeletonLoader), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MultiProvider(
        key: const ValueKey('tr-busy-root'),
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<SessionMedia>.value(value: media),
        ],
        child: MaterialApp(
          key: const ValueKey('tr-busy'),
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: TranscriptionScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text(const AppStrings('vi').transcribeUseLast));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text(const AppStrings('vi').transcribeRunBtn));
    await tester.pump();
    expect(find.byType(SkeletonLoader), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(_appShell(const AnalysisScreen(), server: server, appKey: const ValueKey('an-idle')));
    await tester.pump();
    expect(find.byType(SkeletonLoader), findsNothing);

    if (!completer.isCompleted) {
      completer.complete(
        ResponseBody.fromString(
          '{"label":"Test","notes":[]}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _PendingAdapter implements HttpClientAdapter {
  final Completer<ResponseBody> completer;
  _PendingAdapter(this.completer);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      completer.future;

  @override
  void close({bool force = false}) {}
}

Uint8List _miniWavBytes() {
  final data = ByteData(44 + 800);
  data.setUint32(0, 0x46464952, Endian.little);
  data.setUint32(4, 36 + 800, Endian.little);
  data.setUint32(8, 0x45564157, Endian.little);
  data.setUint32(12, 0x20746D66, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(36, 0x61746164, Endian.little);
  data.setUint32(40, 800, Endian.little);
  return data.buffer.asUint8List();
}
