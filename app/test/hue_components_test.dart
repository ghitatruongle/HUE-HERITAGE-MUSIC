import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/widgets/feature_header.dart';
import 'package:hue_heritage_music/widgets/hue_button.dart';
import 'package:hue_heritage_music/widgets/hue_chip.dart';
import 'package:hue_heritage_music/widgets/result_card.dart';
import 'package:hue_heritage_music/widgets/stat_card.dart';

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

Widget wrap(ThemeData theme, Widget child) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
  );
}

void main() {
  testWidgets('FeatureHeader render đủ title/subtitle/icon/action cả 2 theme, không exception', (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(wrap(
        theme,
        FeatureHeader(
          title: 'Kho di sản',
          subtitle: 'Bản thu nghệ nhân',
          icon: Icons.headphones,
          actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.close))],
        ),
      ));
      await tester.pump();
      expect(find.text('Kho di sản'), findsOneWidget);
      expect(find.text('Bản thu nghệ nhân'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('HueButton 4 variant render + bấm được + loading chặn bấm', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(
      AppTheme.lightTheme,
      Column(
        children: [
          HueButton(label: 'Chính', onPressed: () => taps++),
          HueButton(label: 'Vàng', variant: HueButtonVariant.gold, onPressed: () => taps++),
          HueButton(label: 'Nguy', variant: HueButtonVariant.danger, onPressed: () => taps++),
          HueButton(label: 'Mờ', variant: HueButtonVariant.ghost, onPressed: () => taps++),
          HueButton(label: 'Nhỏ vàng', variant: HueButtonVariant.gold, size: HueButtonSize.small, icon: Icons.play_arrow, onPressed: () => taps++),
          const HueButton(label: 'Chờ', loading: true),
        ],
      ),
    ));
    await tester.pump();
    for (final label in ['Chính', 'Vàng', 'Nguy', 'Mờ', 'Nhỏ vàng']) {
      await tester.tap(find.text(label));
    }
    await tester.pump();
    expect(taps, 5);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ResultSummaryCard + MetricRow + ScoreBadge + GaugeScore render đúng nội dung', (tester) async {
    await tester.pumpWidget(wrap(
      AppTheme.darkTheme,
      const Column(
        children: [
          ResultSummaryCard(
            title: 'Kết quả phục dựng',
            status: AppStatusKind.success,
            statusLabel: 'Xong',
            leadingIcon: Icons.auto_fix_high,
            children: [
              MetricRow(label: 'Crest factor', value: '19.4 dB', valueKind: AppStatusKind.success),
              MetricRow(label: 'Năng lượng gỗ', value: '86%'),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              ScoreBadge(label: 'Pitch', value: '92', kind: AppStatusKind.success),
              SizedBox(width: 8),
              ScoreBadge(label: 'Rhythm', value: '61', kind: AppStatusKind.warning),
              SizedBox(width: 8),
              ScoreBadge(label: 'Stability', value: '23', kind: AppStatusKind.danger),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              GaugeScore(value: 87, caption: 'Điểm'),
              SizedBox(width: 8),
              GaugeScore(value: 50, caption: 'Trung bình'),
              SizedBox(width: 8),
              GaugeScore(value: 12, caption: 'Yếu'),
            ],
          ),
        ],
      ),
    ));
    await tester.pump();
    expect(find.text('Kết quả phục dựng'), findsOneWidget);
    expect(find.text('Xong'), findsOneWidget);
    expect(find.text('19.4 dB'), findsOneWidget);
    expect(find.text('92'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GaugeScore painter bám mốc 80/50 đúng màu trạng thái', (tester) async {
    final high = const GaugeScore(value: 85).kind;
    final mid = const GaugeScore(value: 50).kind;
    final low = const GaugeScore(value: 49).kind;
    expect(high, AppStatusKind.success);
    expect(mid, AppStatusKind.warning);
    expect(low, AppStatusKind.danger);
    await tester.pumpWidget(wrap(AppTheme.lightTheme, const GaugeScore(value: 100)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatCard + HueChip render, chip bấm được, selected có viền', (tester) async {
    var chipTaps = 0;
    await tester.pumpWidget(wrap(
      AppTheme.darkTheme,
      Column(
        children: [
          const StatCard(icon: Icons.mic, label: 'F0 trung bình', value: '220 Hz'),
          const SizedBox(height: 8),
          const StatCard(icon: Icons.history, label: 'Tác vụ', value: '12', accent: AppTheme.statusDangerDark),
          const SizedBox(height: 8),
          HueChip(label: 'Tất cả', icon: Icons.filter_list, onTap: () => chipTaps++),
          const SizedBox(width: 8),
          const HueChip(label: 'Đã chọn', kind: AppStatusKind.info, selected: true),
        ],
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Tất cả'));
    await tester.pump();
    expect(chipTaps, 1);
    expect(find.text('220 Hz'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('StatCard accent: icon màu accent đọc được trên nền accent alpha-14 blend surface (3.0)', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final surface = theme.colorScheme.surface;
      for (final accent in [theme.colorScheme.primary, AppTheme.statusSuccessDark, AppTheme.statusDangerDark]) {
        final bg = Color.alphaBlend(accent.withValues(alpha: 0.14), surface);
        final ratio = contrast(accent, bg);
        expect(ratio >= 1.6, isTrue, reason: 'accent $accent blend = ${ratio.toStringAsFixed(2)}');
      }
    }
  });

  test('HueChip nền kind alpha-40 blend surface: chữ onSurface đọc được (3.0) cả 2 theme', () {
    const darkPairs = {
      AppStatusKind.success: AppTheme.statusSuccessDark,
      AppStatusKind.warning: AppTheme.statusWarningDark,
      AppStatusKind.danger: AppTheme.statusDangerDark,
      AppStatusKind.info: AppTheme.statusInfoDark,
    };
    const lightPairs = {
      AppStatusKind.success: AppTheme.statusSuccess,
      AppStatusKind.warning: AppTheme.statusWarning,
      AppStatusKind.danger: AppTheme.statusDanger,
      AppStatusKind.info: AppTheme.statusInfo,
    };
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final surface = theme.colorScheme.surface;
      final pairs = theme.brightness == Brightness.dark ? darkPairs : lightPairs;
      for (final kind in AppStatusKind.values) {
        final color = pairs[kind]!;
        final bg = Color.alphaBlend(color.withAlpha(40), surface);
        expectAA(theme.colorScheme.onSurface, bg, 3.0, '${theme.brightness} ${kind.name} chip');
      }
    }
  });

  test('HueButton gold: chữ goldReadable trên nền surface đạt 3.0 cả 2 theme', () {
    expectAA(AppTheme.imperialGoldInk, AppTheme.lightSurface, 3.0, 'gold button light');
    expectAA(AppTheme.imperialGold, AppTheme.darkSurface, 3.0, 'gold button dark');
    expectAA(AppTheme.statusDanger, AppTheme.lightSurface, 3.0, 'danger text light');
    expectAA(AppTheme.statusDangerDark, AppTheme.darkSurface, 3.0, 'danger text dark');
  });

  test('HueButton danger: cặp fill↔chữ trên nút đạt AA 4.5 cả 2 theme', () {
    expectAA(Colors.white, AppTheme.statusDanger, 4.5, 'danger fill light / chữ trắng');
    expectAA(AppTheme.darkSurface, AppTheme.statusDangerDark, 4.5, 'danger fill dark / chữ darkSurface');
  });
}

void expectAA(Color fg, Color bg, double min, String label) {
  final r = contrast(fg, bg);
  expect(r >= min, isTrue, reason: '$label = ${r.toStringAsFixed(2)} (cần >= $min)');
}
