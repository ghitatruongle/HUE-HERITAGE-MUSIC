import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/auth/login_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';

Widget _wrap(Widget screen) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<AuthService>.value(value: AuthService()),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SafeArea(child: screen)),
    ),
  );
}

void main() {
  testWidgets('C6: field đăng nhập có Semantics label cho screen reader', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsWidgets);
    final semantics = tester.getSemantics(fields.first);
    expect(semantics.label, isNotEmpty, reason: 'field đăng nhập phải có label cho screen reader');
  });

  testWidgets('C6: Tab di chuyển focus giữa các field đăng nhập (bàn phím)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    final before = FocusManager.instance.primaryFocus;
    expect(before, isNotNull, reason: 'tap vào field phải tạo focus');
    final beforeCtx = before!.context;

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final after = FocusManager.instance.primaryFocus;
    expect(after, isNotNull, reason: 'sau Tab phải còn focus');
    expect(after!.context, isNot(beforeCtx), reason: 'Tab phải chuyển focus sang node kế tiếp');
  });
}
