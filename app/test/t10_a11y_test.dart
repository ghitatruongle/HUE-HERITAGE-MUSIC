import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/screens/history/history_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/hue_button.dart';
import 'package:hue_heritage_music/widgets/hue_icons.dart';
import 'package:hue_heritage_music/widgets/responsive_layout.dart';

Widget _wrap(ThemeData theme, Widget child, {double scale = 2.0}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
      ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
    ],
    child: MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    ),
  );
}

Widget _wrapFull(ThemeData theme, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
      ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
    ],
    child: MaterialApp(theme: theme, home: child),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
  });

  testWidgets('T10: Login ở text scale 200% không vỡ, form render đủ 2 theme', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(500, 900);
    addTearDown(tester.view.reset);
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(_wrap(theme, const LoginScreen()));
      await tester.pump();
      expect(find.byType(TextField), findsWidgets);
    }
  });

  testWidgets('T10: Login đổi tab đăng ký được ở scale chuẩn (IndexedStack)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(500, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(AppTheme.lightTheme, const LoginScreen(), scale: 1.0));
    await tester.pump();
    await tester.tap(find.textContaining('Đăng ký'));
    await tester.pump();
    expect(find.byType(TextField), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T10: History FeatureHeader ở text scale 200% render sạch 2 theme', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.reset);
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(_wrap(theme, const HistoryScreen()));
      await tester.pump();
      expect(find.text('Lịch sử tác vụ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('T10: HueButton nhỏ vẫn đủ vùng chạm 44dp, nút thường 48dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HueButton(label: 'Nhỏ', variant: HueButtonVariant.gold, size: HueButtonSize.small, onPressed: () {}),
              HueButton(label: 'Thường', variant: HueButtonVariant.primary, onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final smallSize = tester.getSize(find.widgetWithText(HueButton, 'Nhỏ'));
    final normalSize = tester.getSize(find.widgetWithText(HueButton, 'Thường'));
    expect(smallSize.height, greaterThanOrEqualTo(44));
    expect(normalSize.height, greaterThanOrEqualTo(48));
  });

  testWidgets('T10: Rail thu gọn đủ vùng chạm 48dp cho mọi ô điều hướng', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    const destinations = [
      NavigationDestinationItem(icon: HueIcons.home, selectedIcon: HueIcons.home, labelKey: 'home', screen: SizedBox.shrink()),
      NavigationDestinationItem(icon: HueIcons.history, selectedIcon: HueIcons.history, labelKey: 'history', screen: SizedBox.shrink()),
      NavigationDestinationItem(icon: HueIcons.settings, selectedIcon: HueIcons.settings, labelKey: 'settings', screen: SizedBox.shrink()),
    ];
    await tester.pumpWidget(
      _wrapFull(
        AppTheme.lightTheme,
        ResponsiveScaffold(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(IconButton), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    final navInkwells = find.descendant(of: find.byType(ListView), matching: find.byType(InkWell));
    expect(navInkwells, findsNWidgets(destinations.length));
    for (final element in navInkwells.evaluate().toList()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.height, greaterThanOrEqualTo(48), reason: 'Ô rail thu gọn thiếu vùng chạm: $size');
      expect(size.width, greaterThanOrEqualTo(48), reason: 'Ô rail thu gọn thiếu vùng chạm: $size');
    }
  });
}
