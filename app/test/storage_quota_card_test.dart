import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/widgets/storage_quota_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('StorageQuotaCard formatBytes', () {
    test('formats byte tiers', () {
      expect(StorageQuotaCard.formatBytes(500), '500 B');
      expect(StorageQuotaCard.formatBytes(2048), '2.0 KB');
      expect(StorageQuotaCard.formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(StorageQuotaCard.formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
    });
  });

  testWidgets('shows unlimited when quota is null (admin)', (tester) async {
    const strings = AppStrings('vi');
    await tester.pumpWidget(_wrap(const StorageQuotaCard(
      strings: strings,
      usedBytes: 123 * 1024 * 1024,
    )));
    await tester.pump();
    expect(find.text('Lưu trữ'), findsOneWidget);
    expect(find.text('123.0 MB'), findsOneWidget);
    expect(find.text('Không giới hạn'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows used / quota with progress bar for normal user', (tester) async {
    const strings = AppStrings('vi');
    await tester.pumpWidget(_wrap(const StorageQuotaCard(
      strings: strings,
      usedBytes: 100 * 1024 * 1024,
      quotaBytes: 500 * 1024 * 1024,
    )));
    await tester.pump();
    expect(find.text('100.0 MB / 500.0 MB'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.2, 0.001));
  });

  testWidgets('progress clamps at 1.0 when over quota', (tester) async {
    const strings = AppStrings('en');
    await tester.pumpWidget(_wrap(const StorageQuotaCard(
      strings: strings,
      usedBytes: 600 * 1024 * 1024,
      quotaBytes: 500 * 1024 * 1024,
    )));
    await tester.pump();
    expect(find.text('Quota'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 1.0);
  });

  testWidgets('english labels render', (tester) async {
    const strings = AppStrings('en');
    await tester.pumpWidget(_wrap(const StorageQuotaCard(
      strings: strings,
      usedBytes: 1024,
    )));
    await tester.pump();
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
  });

  testWidgets('quotaBytes zero also renders unlimited', (tester) async {
    const strings = AppStrings('vi');
    await tester.pumpWidget(_wrap(const StorageQuotaCard(
      strings: strings,
      usedBytes: 2048,
      quotaBytes: 0,
    )));
    await tester.pump();
    expect(find.text('Không giới hạn'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
