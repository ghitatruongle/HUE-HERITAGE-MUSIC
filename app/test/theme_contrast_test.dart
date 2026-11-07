import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';

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
}
