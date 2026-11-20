import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/widgets/hue_icons.dart';
import 'package:hue_heritage_music/widgets/server_onboarding_dialog.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('C6: HueIcon inject semanticLabel từ map (dark + light)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 400);
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();

    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
            ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ],
          child: MaterialApp(
            theme: theme,
            home: const Scaffold(body: Center(child: HueIcon(HueIcons.delete, size: 24))),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Xóa'), findsOneWidget,
          reason: 'HueIcon phải gán label VI từ map ở ${theme.brightness}');
    }
    handle.dispose();
  });

  testWidgets('C6: HueIcon cho phép override label tại call site', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const Center(child: HueIcon(HueIcons.delete, semanticLabel: 'Xóa bài hát'))));
    await tester.pump();
    expect(find.bySemanticsLabel('Xóa bài hát'), findsOneWidget);
    expect(find.bySemanticsLabel('Xóa'), findsNothing);
    handle.dispose();
  });

  testWidgets('C6: Tab trong dialog onboarding chuyển focus từ field sang nút', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const ServerOnboardingDialog()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final before = FocusManager.instance.primaryFocus;
    expect(before, isNotNull, reason: 'tap vào field phải tạo focus');
    final beforeCtx = before!.context;

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final after = FocusManager.instance.primaryFocus;
    expect(after, isNotNull);
    expect(after!.context, isNot(beforeCtx), reason: 'Tab phải chuyển focus sang nút action của dialog');
  });

  test('C7: shareDownloadedFile kiểm file tồn tại trước khi share', () {
    final src = File('lib/services/file_saver.dart').readAsLinesSync();
    final existsLine = src.indexWhere((l) => l.contains('File(path).exists()'));
    final shareLine = src.indexWhere((l) => l.contains('SharePlus.instance.share'));
    expect(existsLine, greaterThanOrEqualTo(0), reason: 'thiếu guard file tồn tại');
    expect(shareLine, greaterThan(existsLine),
        reason: 'guard file tồn tại phải nằm trước lệnh share');
  });
}
