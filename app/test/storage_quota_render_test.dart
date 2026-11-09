import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/storage_quota_card.dart';

Widget _wrap(Widget child, {required bool dark, ThemeMode mode = ThemeMode.light}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      home: Theme(data: dark ? AppTheme.darkTheme : AppTheme.lightTheme, child: Scaffold(body: child)),
    ),
  );
}

Future<void> _pumpWidth(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pump(const Duration(milliseconds: 80));
}

Widget _card(AppStrings strings, {required int used, int? quota}) {
  return SingleChildScrollView(child: StorageQuotaCard(strings: strings, usedBytes: used, quotaBytes: quota));
}

void main() {
  testWidgets('Card quota 360dp dark vi - khong overflow', (tester) async {
    await _pumpWidth(
      tester,
      _wrap(_card(const AppStrings('vi'), used: 320 * 1024 * 1024, quota: 500 * 1024 * 1024), dark: true),
      const Size(360, 740),
    );
    expect(find.text('320.0 MB / 500.0 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Card quota 320dp light en - khong overflow', (tester) async {
    await _pumpWidth(
      tester,
      _wrap(_card(const AppStrings('en'), used: 90 * 1024 * 1024, quota: 500 * 1024 * 1024), dark: false),
      const Size(320, 640),
    );
    expect(find.text('90.0 MB / 500.0 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Card gia tri lon (2TB) 360dp dark - khong overflow, clamp mau error', (tester) async {
    await _pumpWidth(
      tester,
      _wrap(_card(const AppStrings('vi'), used: 2 * 1024 * 1024 * 1024 * 1024, quota: 500 * 1024 * 1024), dark: true),
      const Size(360, 740),
    );
    expect(find.text('Trần dung lượng'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings 360dp dark (chua dang nhap) - khong overflow, khong card quota', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const SettingsScreen(), dark: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('Lưu trữ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
