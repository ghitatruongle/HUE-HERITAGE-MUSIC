import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/widgets/hue_button.dart';

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

  test('Cặp control (nút/pill) đạt ngưỡng UI 3.0 ở cả 2 theme', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    expectAA(dark.onPrimary, dark.primary, 3.0, 'dark onPrimary/primary');
    expectAA(light.onPrimary, light.primary, 3.0, 'light onPrimary/primary');
    expectAA(dark.onErrorContainer, dark.errorContainer, 3.0, 'dark onErrorContainer/errorContainer');
    expectAA(light.onErrorContainer, light.errorContainer, 3.0, 'light onErrorContainer/errorContainer');
  });

  test('4 màu trạng thái đọc được trên surface ở cả 2 theme (ngưỡng 3.0)', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    for (final c in [AppTheme.statusSuccess, AppTheme.statusWarning, AppTheme.statusDanger, AppTheme.statusInfo]) {
      expectAA(c, dark.surface, 3.0, 'dark status/$c');
      expectAA(c, light.surface, 3.0, 'light status/$c');
      expectAA(c, AppTheme.darkBg, 3.0, 'darkBg status/$c');
      expectAA(c, AppTheme.lightBg, 3.0, 'lightBg status/$c');
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

  test('Chip verdict: chữ onSurface đọc được trên nền status alpha-40 ở cả 2 theme', () {
    final dark = AppTheme.darkTheme;
    final light = AppTheme.lightTheme;
    for (final theme in [dark, light]) {
      final bg = theme.scaffoldBackgroundColor;
      for (final c in [AppTheme.statusSuccess, AppTheme.statusWarning, AppTheme.statusDanger, AppTheme.statusInfo]) {
        final chipBg = Color.alphaBlend(c.withAlpha(40), bg);
        expectAA(theme.colorScheme.onSurface, chipBg, 3.0, '${theme.brightness} verdict ${c.toARGB32()}');
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

  test('Chip BETA: nền goldReadable alpha-20 blend surface, chữ goldReadable đạt 3.0 ở cả 2 theme', () {
    final dark = AppTheme.darkTheme;
    final light = AppTheme.lightTheme;
    const goldDark = AppTheme.imperialGold;
    const goldLight = AppTheme.imperialGoldInk;
    for (final (theme, gold, name) in [(dark, goldDark, 'dark'), (light, goldLight, 'light')]) {
      final chipBg = Color.alphaBlend(gold.withAlpha(51), theme.colorScheme.surface);
      expectAA(gold, chipBg, 3.0, '$name BETA gold/blend');
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

  test('amberGoldReadable: cặp dark/light đọc được trên surface + bg theme tương ứng (3.0)', () {
    expectAA(AppTheme.amberGold, AppTheme.darkTheme.colorScheme.surface, 3.0, 'amberGold/darkSurface');
    expectAA(AppTheme.amberGold, AppTheme.darkBg, 3.0, 'amberGold/darkBg');
    expectAA(AppTheme.amberGoldInk, AppTheme.lightTheme.colorScheme.surface, 3.0, 'amberGoldInk/lightSurface');
    expectAA(AppTheme.amberGoldInk, AppTheme.lightBg, 3.0, 'amberGoldInk/lightBg');
  });

  test('emeraldReadable: cặp dark/light đọc được trên surface + bg theme tương ứng (3.0)', () {
    expectAA(AppTheme.emeraldBright, AppTheme.darkTheme.colorScheme.surface, 3.0, 'emeraldBright/darkSurface');
    expectAA(AppTheme.emeraldBright, AppTheme.darkBg, 3.0, 'emeraldBright/darkBg');
    expectAA(AppTheme.emeraldGreen, AppTheme.lightTheme.colorScheme.surface, 3.0, 'emeraldGreen/lightSurface');
    expectAA(AppTheme.emeraldGreen, AppTheme.lightBg, 3.0, 'emeraldGreen/lightBg');
  });

  test('statusReadable: cặp sáng/tối mới đọc được trên surface + bg theme tương ứng (3.0)', () {
    final dark = AppTheme.darkTheme.colorScheme;
    final light = AppTheme.lightTheme.colorScheme;
    expectAA(AppTheme.statusSuccessDark, dark.surface, 3.0, 'statusSuccessDark/darkSurface');
    expectAA(AppTheme.statusWarningDark, dark.surface, 3.0, 'statusWarningDark/darkSurface');
    expectAA(AppTheme.statusDangerDark, dark.surface, 3.0, 'statusDangerDark/darkSurface');
    expectAA(AppTheme.statusInfoDark, dark.surface, 3.0, 'statusInfoDark/darkSurface');
    expectAA(AppTheme.statusSuccess, light.surface, 3.0, 'statusSuccess/lightSurface');
    expectAA(AppTheme.statusWarning, light.surface, 3.0, 'statusWarning/lightSurface');
    expectAA(AppTheme.statusDanger, light.surface, 3.0, 'statusDanger/lightSurface');
    expectAA(AppTheme.statusInfo, light.surface, 3.0, 'statusInfo/lightSurface');
  });

  test('Chữ trắng đọc được trên mọi stop của brandGradient cả 2 theme (AA 4.5)', () {
    for (final c in AppTheme.brandGradientColors) {
      expectAA(Colors.white, c, 4.5, 'white/dark gradient stop ${c.toARGB32()}');
    }
    for (final c in AppTheme.brandGradientColorsLight) {
      expectAA(Colors.white, c, 4.5, 'white/light gradient stop ${c.toARGB32()}');
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

  testWidgets('HueButton danger — dark: ink sáng trên nền danger đạt 4.5', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: HueButton(label: 'Xoá', variant: HueButtonVariant.danger, onPressed: () {}),
        ),
      ),
    );
    final filled = tester.widget<FilledButton>(find.byType(FilledButton));
    final fg = filled.style!.foregroundColor!.resolve(<WidgetState>{})!;
    final bg = filled.style!.backgroundColor!.resolve(<WidgetState>{})!;
    expect(fg, AppTheme.darkSurface, reason: 'dark danger phải dùng ink tối');
    expectAA(fg, bg, 4.5, 'dark danger foreground/background');
  });

  testWidgets('HueButton danger — light: chữ trắng trên nền danger đạt 4.5', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: HueButton(label: 'Xoá', variant: HueButtonVariant.danger, onPressed: () {}),
        ),
      ),
    );
    final filled = tester.widget<FilledButton>(find.byType(FilledButton));
    final fg = filled.style!.foregroundColor!.resolve(<WidgetState>{})!;
    final bg = filled.style!.backgroundColor!.resolve(<WidgetState>{})!;
    expect(fg, Colors.white, reason: 'light danger phải dùng chữ trắng');
    expectAA(fg, bg, 4.5, 'light danger foreground/background');
  });
}
