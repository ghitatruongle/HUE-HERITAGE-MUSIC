import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/admin/admin_screen.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/learning/learning_screen.dart';
import 'package:hue_heritage_music/screens/restoration/restoration_screen.dart';
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

Future<void> _pumpSmall(WidgetTester tester, Widget screen,
    {required bool dark}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(screen, dark: dark));
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  testWidgets('Creation 360dp 2 theme - khong overflow', (tester) async {
    await _pumpSmall(tester, const CreationScreen(), dark: true);
    expect(tester.takeException(), isNull);
    await _pumpSmall(tester, const CreationScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Restoration 360dp 2 theme - khong overflow', (tester) async {
    await _pumpSmall(tester, const RestorationScreen(), dark: true);
    expect(tester.takeException(), isNull);
    await _pumpSmall(tester, const RestorationScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Learning 360dp 2 theme - khong overflow', (tester) async {
    await _pumpSmall(tester, const LearningScreen(), dark: true);
    expect(tester.takeException(), isNull);
    await _pumpSmall(tester, const LearningScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin 360dp 2 theme - khong overflow', (tester) async {
    await _pumpSmall(tester, const AdminScreen(), dark: true);
    expect(tester.takeException(), isNull);
    await _pumpSmall(tester, const AdminScreen(), dark: false);
    expect(tester.takeException(), isNull);
  });

  test('AppStrings choice labels: vi keeps API values, en translates', () {
    const vi = AppStrings('vi');
    const en = AppStrings('en');
    expect(vi.vocalChoiceLabel('Nữ'), 'Nữ');
    expect(vi.tempoChoiceLabel('Vừa'), 'Vừa');
    expect(vi.moodChoiceLabel('Trữ tình'), 'Trữ tình');
    expect(en.vocalChoiceLabel('Nữ'), 'Female');
    expect(en.vocalChoiceLabel('Nam'), 'Male');
    expect(en.vocalChoiceLabel('Không lời'), 'Instrumental');
    expect(en.tempoChoiceLabel('Chậm'), 'Slow');
    expect(en.tempoChoiceLabel('Vừa'), 'Medium');
    expect(en.tempoChoiceLabel('Nhanh'), 'Fast');
    expect(en.moodChoiceLabel('Trữ tình'), 'Lyrical');
    expect(en.moodChoiceLabel('Thiết tha'), 'Soulful');
    expect(en.moodChoiceLabel('Tươi vui'), 'Cheerful');
    expect(en.moodChoiceLabel('Hào sảng'), 'Heroic');
  });
}
