import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/screens/creation/creation_screen.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/feature_header.dart';
import 'package:hue_heritage_music/widgets/hue_button.dart';
import 'package:hue_heritage_music/widgets/hue_icons.dart';

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
        jsonEncode([
          {
            'id': 'contrast-1',
            'title': 'Hò Mái Nhì',
            'type': 'Ca Huế',
            'artist': 'Nghệ nhân',
            'lyrics': 'Tình tang',
            'sha256': 'abcd',
            'size': 10,
            'created_at': '2026-11-11T00:00:00Z',
          }
        ]),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString('{}', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

double _lin(double c) {
  c /= 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double luminance(Color c) {
  return 0.2126 * _lin(c.r * 255.0) + 0.7152 * _lin(c.g * 255.0) + 0.0722 * _lin(c.b * 255.0);
}

double contrast(Color a, Color b) {
  final l1 = luminance(a);
  final l2 = luminance(b);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void expectAA(Color fg, Color bg, double min, String label) {
  final r = contrast(fg, bg);
  expect(r >= min, isTrue, reason: '$label = ${r.toStringAsFixed(2)} (cần >= $min)');
}

void main() {
  test('Dark theme — cặp text chính đạt WCAG AA 4.5', () {
    final s = AppTheme.darkTheme.colorScheme;
    expectAA(s.onSurface, s.surface, 4.5, 'dark onSurface/surface');
    expectAA(s.onSurface, AppTheme.darkBg, 4.5, 'dark onSurface/darkBg');
    expectAA(s.onSurfaceVariant, s.surface, 4.5, 'dark onSurfaceVariant/surface');
    expectAA(s.onSurfaceVariant, s.surfaceContainerHighest, 4.5, 'dark onSurfaceVariant/containerHighest');
    expectAA(s.onSurface, s.surfaceContainerHighest, 4.5, 'dark onSurface/containerHighest');
    expectAA(s.onSecondary, s.secondary, 4.5, 'dark onSecondary/secondary');
  });

  test('Light theme — cặp text chính đạt WCAG AA 4.5', () {
    final s = AppTheme.lightTheme.colorScheme;
    expectAA(s.onSurface, s.surface, 4.5, 'light onSurface/surface');
    expectAA(s.onSurface, AppTheme.lightBg, 4.5, 'light onSurface/lightBg');
    expectAA(s.onSurfaceVariant, s.surface, 4.5, 'light onSurfaceVariant/surface');
    expectAA(s.onSurfaceVariant, s.surfaceContainerHighest, 4.5, 'light onSurfaceVariant/containerHighest');
    expectAA(s.onSurface, s.surfaceContainerHighest, 4.5, 'light onSurface/containerHighest');
    expectAA(s.onSecondary, s.secondary, 4.5, 'light onSecondary/secondary');
  });

  test('Cặp control và scheme chính (primary/tertiary/error) đạt AA ở cả 2 theme', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    expectAA(dark.onPrimary, dark.primary, 4.5, 'dark onPrimary/primary');
    expectAA(light.onPrimary, light.primary, 4.5, 'light onPrimary/primary');
    expectAA(dark.primary, dark.surface, 4.5, 'dark primary/surface');
    expectAA(dark.primary, dark.surfaceContainerHighest, 4.5, 'dark primary/containerHighest');
    expectAA(dark.tertiary, dark.surface, 4.5, 'dark tertiary/surface');
    expectAA(dark.tertiary, AppTheme.darkBg, 4.5, 'dark tertiary/darkBg');
    expectAA(dark.onTertiary, dark.tertiary, 4.5, 'dark onTertiary/tertiary');
    expectAA(light.tertiary, light.surface, 4.5, 'light tertiary/surface');
    expectAA(light.onTertiary, light.tertiary, 4.5, 'light onTertiary/tertiary');
    expectAA(dark.error, dark.surface, 4.5, 'dark error/surface');
    expectAA(dark.error, dark.surfaceContainerHighest, 4.5, 'dark error/containerHighest');
    expectAA(dark.onError, dark.error, 4.5, 'dark onError/error');
    expectAA(light.error, light.surface, 4.5, 'light error/surface');
    expectAA(light.error, light.surfaceContainerHighest, 4.5, 'light error/containerHighest');
    expectAA(light.onError, light.error, 4.5, 'light onError/error');
    expectAA(dark.onErrorContainer, dark.errorContainer, 4.5, 'dark onErrorContainer/errorContainer');
    expectAA(light.onErrorContainer, light.errorContainer, 4.5, 'light onErrorContainer/errorContainer');
  });

  test('4 màu trạng thái đạt AA 4.5 đúng cặp sáng/tối trên surface, bg và chip', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    for (final c in [AppTheme.statusSuccess, AppTheme.statusWarning, AppTheme.statusDanger, AppTheme.statusInfo]) {
      expectAA(c, light.surface, 4.5, 'light status/$c');
      expectAA(c, AppTheme.lightBg, 4.5, 'lightBg status/$c');
      expectAA(c, Color.alphaBlend(c.withAlpha(40), light.surface), 4.5, 'light chip40 status/$c');
    }
    for (final c in [AppTheme.statusSuccessDark, AppTheme.statusWarningDark, AppTheme.statusDangerDark, AppTheme.statusInfoDark]) {
      expectAA(c, dark.surface, 4.5, 'dark status/$c');
      expectAA(c, AppTheme.darkBg, 4.5, 'darkBg status/$c');
      expectAA(c, Color.alphaBlend(c.withAlpha(40), dark.surface), 4.5, 'dark chip40 status/$c');
    }
  });

  test('TextTheme body/label màu bám đúng scheme ở cả 2 theme', () {
    final dark = AppTheme.darkTheme;
    final light = AppTheme.lightTheme;
    expect(dark.textTheme.bodyMedium!.color, dark.colorScheme.onSurface);
    expect(dark.textTheme.bodySmall!.color, dark.colorScheme.onSurfaceVariant);
    expect(light.textTheme.bodyMedium!.color, light.colorScheme.onSurface);
    expect(light.textTheme.bodySmall!.color, light.colorScheme.onSurfaceVariant);
    expect(dark.textTheme.bodyMedium!.fontSize, light.textTheme.bodyMedium!.fontSize);
  });

  test('Chip verdict: chữ onSurface đọc được trên nền status alpha-40 ở cả 2 theme (AA 4.5)', () {
    final dark = AppTheme.darkTheme;
    final light = AppTheme.lightTheme;
    final pairs = [
      (dark, [AppTheme.statusSuccessDark, AppTheme.statusWarningDark, AppTheme.statusDangerDark, AppTheme.statusInfoDark]),
      (light, [AppTheme.statusSuccess, AppTheme.statusWarning, AppTheme.statusDanger, AppTheme.statusInfo]),
    ];
    for (final (theme, colors) in pairs) {
      final bg = theme.scaffoldBackgroundColor;
      for (final c in colors) {
        final chipBg = Color.alphaBlend(c.withAlpha(40), bg);
        expectAA(theme.colorScheme.onSurface, chipBg, 4.5, '${theme.brightness} verdict ${c.toARGB32()}');
      }
    }
  });

  test('ChartPalette: màu user đọc được trên nền 2 theme (ngưỡng 3.0)', () {
    expectAA(const Color(0xFF7DD3FC), AppTheme.darkTheme.scaffoldBackgroundColor, 3.0, 'dark user chart');
    expectAA(const Color(0xFF2563EB), AppTheme.lightTheme.scaffoldBackgroundColor, 3.0, 'light user chart');
    expectAA(AppTheme.imperialGold, AppTheme.darkTheme.scaffoldBackgroundColor, 3.0, 'dark reference gold');
    expectAA(AppTheme.imperialGoldInk, AppTheme.lightTheme.scaffoldBackgroundColor, 3.0, 'light reference gold');
  });

  test('Cặp container (chữ trên nền container) đạt AA 4.5 ở cả 2 theme', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    expectAA(dark.onPrimaryContainer, dark.primaryContainer, 4.5, 'dark onPrimaryContainer');
    expectAA(light.onPrimaryContainer, light.primaryContainer, 4.5, 'light onPrimaryContainer');
    expectAA(dark.onSecondaryContainer, dark.secondaryContainer, 4.5, 'dark onSecondaryContainer');
    expectAA(light.onSecondaryContainer, light.secondaryContainer, 4.5, 'light onSecondaryContainer');
    expectAA(dark.onTertiaryContainer, dark.tertiaryContainer, 3.0, 'dark onTertiaryContainer (icon)');
    expectAA(light.onTertiaryContainer, light.tertiaryContainer, 3.0, 'light onTertiaryContainer (icon)');
  });

  test('8 màu feature home đọc được trên nền blend 14% ở cả 2 theme (≥3.0)', () {
    for (var i = 0; i < AppTheme.featureAccentsLight.length; i++) {
      final light = AppTheme.featureAccentsLight[i];
      final dark = AppTheme.featureAccentsDark[i];
      final lightBlend = Color.alphaBlend(light.withValues(alpha: 0.14), AppTheme.lightTheme.scaffoldBackgroundColor);
      final darkBlend = Color.alphaBlend(dark.withValues(alpha: 0.14), AppTheme.darkTheme.scaffoldBackgroundColor);
      expectAA(light, lightBlend, 3.0, 'light feature#$i ${light.toARGB32()}');
      expectAA(dark, darkBlend, 3.0, 'dark feature#$i ${dark.toARGB32()}');
    }
  });

  test('SnackBar floating + Chip + Dialog theme tồn tại ở cả 2 theme', () {
    final dark = AppTheme.darkTheme;
    final light = AppTheme.lightTheme;
    expect(dark.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(light.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(dark.chipTheme.side, isNotNull);
    expect(light.chipTheme.side, isNotNull);
    expect(dark.dialogTheme.shape, isNotNull);
    expect(light.dialogTheme.shape, isNotNull);
    expect(dark.tabBarTheme.labelColor, isNotNull);
    expect(light.tabBarTheme.labelColor, isNotNull);
  });


  Widget shell(ThemeData theme) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text('Tiêu đề', style: theme.textTheme.titleLarge),
                    Text('Nội dung mô tả', style: theme.textTheme.bodyMedium),
                    Text('Chú thích phụ', style: theme.textTheme.bodySmall),
                    const Chip(label: Text('Nhãn chip')),
                    const LinearProgressIndicator(value: 0.5),
                  ],
                ),
              ),
            ),
            ElevatedButton(onPressed: () {}, child: const Text('Nút chính')),
            OutlinedButton(onPressed: () {}, child: const Text('Nút phụ')),
          ],
        ),
      ),
    );
  }

  testWidgets('Render smoke: Card/Chip/Text/Button không văng exception ở cả 2 theme', (tester) async {
    await tester.pumpWidget(shell(AppTheme.lightTheme));
    await tester.pump();
    expect(find.text('Tiêu đề'), findsOneWidget);
    expect(find.text('Nút chính'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(shell(AppTheme.darkTheme));
    await tester.pump();
    expect(find.text('Tiêu đề'), findsOneWidget);
    expect(find.text('Nút chính'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Thanh tiến độ card Lưu trữ đọc được ở cả 2 theme (ngưỡng UI 3.0)', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    expectAA(dark.primary, dark.surfaceContainerHighest, 3.0, 'dark primary bar/containerHighest');
    expectAA(light.primary, light.surfaceContainerHighest, 3.0, 'light primary bar/containerHighest');
    expectAA(dark.error, dark.surfaceContainerHighest, 3.0, 'dark error bar/containerHighest');
    expectAA(light.error, light.surfaceContainerHighest, 3.0, 'light error bar/containerHighest');
  });

  test('goldReadable đạt AA 4.5 trên surface/bg ở cả 2 theme', () {
    expectAA(AppTheme.imperialGoldInk, AppTheme.lightSurface, 4.5, 'goldInk/lightSurface');
    expectAA(AppTheme.imperialGoldInk, AppTheme.lightBg, 4.5, 'goldInk/lightBg');
    expectAA(AppTheme.imperialGoldInk, AppTheme.lightSurfaceVariant, 4.5, 'goldInk/lightSurfaceVariant');
    expectAA(AppTheme.imperialGold, AppTheme.darkSurface, 4.5, 'gold/darkSurface');
    expectAA(AppTheme.imperialGold, AppTheme.darkBg, 4.5, 'gold/darkBg');
    expectAA(AppTheme.imperialGold, AppTheme.darkSurfaceVariant, 4.5, 'gold/darkSurfaceVariant');
  });

  test('Chip BETA: nền goldReadable blend ở cả 2 theme đạt AA 4.5', () {
    final dark = AppTheme.darkTheme;
    final light = AppTheme.lightTheme;
    const goldDark = AppTheme.imperialGold;
    const goldLight = AppTheme.imperialGoldInk;
    for (final (theme, gold, name) in [(dark, goldDark, 'dark'), (light, goldLight, 'light')]) {
      final chipSurface = Color.alphaBlend(gold.withAlpha(51), theme.colorScheme.surface);
      final chipVar = Color.alphaBlend(gold.withAlpha(51), theme.colorScheme.surfaceContainerHighest);
      expectAA(gold, chipSurface, 4.5, '$name BETA gold/surface20');
      expectAA(gold, chipVar, 4.5, '$name BETA gold/surfaceVariant20');
      final banner = Color.alphaBlend(AppTheme.amberGold.withValues(alpha: 0.08), theme.scaffoldBackgroundColor);
      final chipBanner = Color.alphaBlend(gold.withValues(alpha: AppAlpha.selected), banner);
      expectAA(gold, chipBanner, 4.5, '$name BETA gold/banner14');
    }
  });

  test('Màu chart user (token mới) đọc được trên surface cả 2 theme (ngưỡng 3.0)', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    expectAA(AppTheme.chartUserDark, dark.surface, 3.0, 'chartUserDark/darkSurface');
    expectAA(AppTheme.chartUserLight, light.surface, 3.0, 'chartUserLight/lightSurface');
    expectAA(AppTheme.chartUserDark, dark.surfaceContainerHighest, 3.0, 'chartUserDark/darkContainerHighest');
    expectAA(AppTheme.chartUserLight, light.surfaceContainerHighest, 3.0, 'chartUserLight/lightContainerHighest');
  });

  test('amberGold chỉ hợp lệ trên nền tối (gradient/tối) — ghim ngưỡng 3.0', () {
    expectAA(AppTheme.amberGold, AppTheme.darkSurface, 3.0, 'amberGold/darkSurface');
    expectAA(AppTheme.amberGold, const Color(0xFF4A2B78), 3.0, 'amberGold/gradientMid');
  });

  test('amberGoldReadable: cặp dark/light đọc được trên surface + bg theme tương ứng (4.5)', () {
    expectAA(AppTheme.amberGold, AppTheme.darkTheme.colorScheme.surface, 4.5, 'amberGold/darkSurface');
    expectAA(AppTheme.amberGold, AppTheme.darkBg, 4.5, 'amberGold/darkBg');
    expectAA(AppTheme.amberGoldInk, AppTheme.lightTheme.colorScheme.surface, 4.5, 'amberGoldInk/lightSurface');
    expectAA(AppTheme.amberGoldInk, AppTheme.lightBg, 4.5, 'amberGoldInk/lightBg');
  });

  test('emeraldReadable: cặp dark/light đọc được trên surface + bg theme tương ứng (4.5)', () {
    expectAA(AppTheme.emeraldBright, AppTheme.darkTheme.colorScheme.surface, 4.5, 'emeraldBright/darkSurface');
    expectAA(AppTheme.emeraldBright, AppTheme.darkBg, 4.5, 'emeraldBright/darkBg');
    expectAA(AppTheme.emeraldGreen, AppTheme.lightTheme.colorScheme.surface, 4.5, 'emeraldGreen/lightSurface');
    expectAA(AppTheme.emeraldGreen, AppTheme.lightBg, 4.5, 'emeraldGreen/lightBg');
  });

  test('statusReadable: cặp sáng/tối mới đọc được trên surface, bg và chip blend (4.5)', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    for (final c in [AppTheme.statusSuccessDark, AppTheme.statusWarningDark, AppTheme.statusDangerDark, AppTheme.statusInfoDark]) {
      expectAA(c, dark.surface, 4.5, '$c/darkSurface');
      expectAA(c, AppTheme.darkBg, 4.5, '$c/darkBg');
      expectAA(c, Color.alphaBlend(c.withAlpha(40), dark.surface), 4.5, '$c/darkChip40');
    }
    final lightTileBg = Color.alphaBlend(light.surfaceContainerHighest.withValues(alpha: 0.45), AppTheme.lightBg);
    for (final c in [AppTheme.statusSuccess, AppTheme.statusWarning, AppTheme.statusDanger, AppTheme.statusInfo]) {
      expectAA(c, light.surface, 4.5, '$c/lightSurface');
      expectAA(c, AppTheme.lightBg, 4.5, '$c/lightBg');
      expectAA(c, Color.alphaBlend(c.withAlpha(40), light.surface), 4.5, '$c/lightChip40');
      expectAA(c, Color.alphaBlend(c.withValues(alpha: 0.14), lightTileBg), 4.5, '$c/lightHomeChip14');
    }
  });

  test('Chữ trắng, trắng mờ 0.88 và gradientAccentGold đọc được trên mọi stop brandGradient cả 2 theme (AA 4.5)', () {
    for (final c in [...AppTheme.brandGradientColors, ...AppTheme.brandGradientColorsLight]) {
      expectAA(Colors.white, c, 4.5, 'white/gradient stop ${c.toARGB32()}');
      expectAA(Color.alphaBlend(Colors.white.withValues(alpha: 0.88), c), c, 4.5, 'white88/gradient stop ${c.toARGB32()}');
      expectAA(AppTheme.gradientAccentGold, c, 4.5, 'gradientAccentGold/gradient stop ${c.toARGB32()}');
    }
  });

  test('AppMotion/AppAlpha/AppElevation token tồn tại với giá trị chuẩn', () {
    expect(AppMotion.fast, const Duration(milliseconds: 150));
    expect(AppMotion.base, const Duration(milliseconds: 200));
    expect(AppMotion.slow, const Duration(milliseconds: 350));
    expect(AppMotion.entrance, const Duration(milliseconds: 380));
    expect(AppMotion.staggerInterval, 0.08);
    expect(AppAlpha.hover, 0.08);
    expect(AppAlpha.selected, 0.14);
    expect(AppAlpha.overlay, 0.40);
    expect(AppAlpha.scrim, 0.54);
    expect(AppElevation.card(Brightness.dark), isNotEmpty);
    expect(AppElevation.card(Brightness.light), isNotEmpty);
  });

  test('Cặp mới đợt Worker/Avatar — role chip + avatar fallback đạt AA cả 2 theme', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final s = theme.colorScheme;
      final label = theme.brightness == Brightness.dark ? 'dark' : 'light';
      expectAA(s.onPrimaryContainer, s.primaryContainer, 4.5, '$label role chip text/primaryContainer');
      expectAA(s.onPrimaryContainer, s.primaryContainer, 3.0, '$label avatar icon onPrimaryContainer/primaryContainer');
    }
  });

  testWidgets('HueButton tất cả 4 variant + Theme buttons đạt AA 4.5 cả 2 theme', (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final tag = theme.brightness == Brightness.dark ? 'dark' : 'light';
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(tag),
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                HueButton(label: 'Chính', variant: HueButtonVariant.primary, onPressed: () {}),
                HueButton(label: 'Vàng', variant: HueButtonVariant.gold, onPressed: () {}),
                HueButton(label: 'Xoá', variant: HueButtonVariant.danger, onPressed: () {}),
                HueButton(label: 'Mờ', variant: HueButtonVariant.ghost, onPressed: () {}),
                ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
                FilledButton(onPressed: () {}, child: const Text('Filled')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filledList = tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
      final pFg = filledList[0].style!.foregroundColor!.resolve(<WidgetState>{})!;
      final pBg = filledList[0].style!.backgroundColor!.resolve(<WidgetState>{})!;
      expectAA(pFg, pBg, 4.5, '$tag HueButton primary');

      final dFg = filledList[1].style!.foregroundColor!.resolve(<WidgetState>{})!;
      final dBg = filledList[1].style!.backgroundColor!.resolve(<WidgetState>{})!;
      if (theme.brightness == Brightness.dark) {
        expect(dFg, AppTheme.darkSurface, reason: 'dark danger phải dùng ink tối');
      } else {
        expect(dFg, Colors.white, reason: 'light danger phải dùng chữ trắng');
      }
      expectAA(dFg, dBg, 4.5, '$tag HueButton danger');

      final goldBtn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final gFg = goldBtn.style!.foregroundColor!.resolve(<WidgetState>{})!;
      expectAA(gFg, theme.colorScheme.surface, 4.5, '$tag HueButton gold');

      final ghostBtn = tester.widget<TextButton>(find.byType(TextButton));
      final ghFg = ghostBtn.style!.foregroundColor!.resolve(<WidgetState>{})!;
      expectAA(ghFg, theme.colorScheme.surface, 4.5, '$tag HueButton ghost');

      final elStyle = theme.elevatedButtonTheme.style!;
      expectAA(
        elStyle.foregroundColor!.resolve(<WidgetState>{})!,
        elStyle.backgroundColor!.resolve(<WidgetState>{})!,
        4.5,
        '$tag elevatedButtonTheme',
      );
      final flStyle = theme.filledButtonTheme.style!;
      expectAA(
        flStyle.foregroundColor!.resolve(<WidgetState>{})!,
        flStyle.backgroundColor!.resolve(<WidgetState>{})!,
        4.5,
        '$tag filledButtonTheme',
      );
    }
  });

  testWidgets('FeatureHeader subtitle dùng alpha >= 0.88 đạt 4.5 trên light gradient', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: FeatureHeader(
            title: 'Tiêu đề',
            subtitle: 'Phụ đề ngắn',
            icon: HueIcons.musicNote,
          ),
        ),
      ),
    );
    final sub = tester.widget<Text>(find.text('Phụ đề ngắn'));
    final fg = sub.style!.color!;
    for (final stop in AppTheme.brandGradientColorsLight) {
      expectAA(Color.alphaBlend(fg, stop), stop, 4.5, 'FeatureHeader subtitle on ${stop.toARGB32()}');
    }
  });

  testWidgets('HomeScreen dark mode: RecentTile icon dùng primaryPurpleGlow + Hero pill đạt 4.5', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    server.api.dio.httpClientAdapter = _TuneMockAdapter();
    final history = HistoryService();
    await history.add(
      HistoryEntry(id: 'h1', kind: 'restore', title: 'Bản thu mẫu', status: 'done', at: DateTime(2026, 11, 24)),
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()..setMode(ThemeMode.dark)),
          ChangeNotifierProvider<HistoryService>.value(value: history),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const HomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final tileRow = find.ancestor(of: find.text('Bản thu mẫu'), matching: find.byType(Row)).first;
    final recentIcon = tester.widget<Icon>(find.descendant(of: tileRow, matching: find.byType(Icon)).first);
    expect(recentIcon.color, isNot(AppTheme.primaryPurple));
    expect(recentIcon.color, AppTheme.darkTheme.colorScheme.primary);

    final onlineText = const AppStrings('vi').serverOnline;
    final statusFinder = find.byWidgetPredicate(
      (w) => w is Text && w.data == onlineText && w.style?.color == AppTheme.emeraldBright,
    );
    final statusLabel = tester.widget<Text>(statusFinder);
    final pillContainer = tester.widget<Container>(
      find.ancestor(of: statusFinder, matching: find.byType(Container)).first,
    );
    final pillBg = (pillContainer.decoration as BoxDecoration).color!;
    for (final stop in [...AppTheme.brandGradientColorsLight, ...AppTheme.brandGradientColors]) {
      expectAA(statusLabel.style!.color!, Color.alphaBlend(pillBg, stop), 4.5, 'Home pill on ${stop.toARGB32()}');
    }
  });

  testWidgets('CreationScreen light mode: nút nghe bản gốc dùng goldReadable (>= 4.5) thay vì imperialGold', (tester) async {
    SharedPreferences.setMockInitialValues({'hue_server_url': 'http://127.0.0.1:8005'});
    final server = ServerConfig();
    await server.load();
    server.api.dio.httpClientAdapter = _TuneMockAdapter();
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const Scaffold(body: CreationScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    final listenText = tester.widget<Text>(find.textContaining('Nghe Bản Gốc'));
    expect(listenText.style!.color, AppTheme.imperialGoldInk);
    expect(listenText.style!.color, isNot(AppTheme.imperialGold));
    expectAA(listenText.style!.color!, AppTheme.lightTheme.colorScheme.surface, 4.5, 'Creation listen btn on lightSurface');
  });
}
