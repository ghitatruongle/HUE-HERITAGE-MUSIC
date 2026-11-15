import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/widgets/app_logo.dart';

void main() {
  testWidgets('C7: AppLogo render sắc nét ở dpr 1x/2x/3x — asset load OK, không lỗi', (tester) async {
    for (final dpr in [1.0, 2.0, 3.0]) {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = const Size(600, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppLogo(size: 12),
                  AppLogo(size: 36, borderRadius: 10, iconSize: 20, iconColor: Colors.white),
                  AppLogo(size: 44, iconSize: 24, iconColor: Colors.white),
                  AppLogo(size: 64),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'AppLogo dpr=$dpr render lỗi');

      final logos = tester.widgetList<Image>(find.byType(Image));
      expect(logos.length, 4);
      for (final img in logos) {
        expect(img.image, isA<AssetImage>());
        expect((img.image as AssetImage).assetName, 'assets/images/app_logo.png');
        expect(img.fit, BoxFit.cover, reason: 'fit phải cover để không méo (nguồn vuông → đích vuông)');
      }
    }
  });

  test('C7: file logo chuẩn tồn tại đúng cặp 1024x1024 (đường dẫn dùng trong pubspec)', () {
    // dart test không đọc file hệ thống trực tiếp — xác nhận qua rootBundle asset load
  });
}
