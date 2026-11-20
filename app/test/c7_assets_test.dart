import 'dart:io';

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

  test('C7: cặp logo nguồn ≥1024x1024, assets/images chỉ có đúng 2 file ảnh chuẩn', () {
    final dir = Directory('assets/images');
    expect(dir.existsSync(), isTrue, reason: 'Thiếu thư mục assets/images');
    const imageExt = ['.png', '.jpg', '.jpeg', '.webp', '.gif'];
    final images = dir
        .listSync()
        .whereType<File>()
        .where((f) => imageExt.any((e) => f.path.toLowerCase().endsWith(e)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(
      images.map((f) => f.uri.pathSegments.last).toList(),
      ['app_logo.jpg', 'app_logo.png'],
      reason: 'Logo chính thức chỉ gồm 2 file chuẩn (AGENTS.md quy tắc 3)',
    );

    final png = images.firstWhere((f) => f.path.endsWith('.png')).readAsBytesSync();
    expect(png.length, greaterThan(24));
    expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], reason: 'app_logo.png không phải PNG');
    int be32(List<int> b, int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final pngW = be32(png, 16);
    final pngH = be32(png, 20);
    expect(pngW, greaterThanOrEqualTo(1024), reason: 'app_logo.png rộng $pngW px');
    expect(pngH, greaterThanOrEqualTo(1024), reason: 'app_logo.png cao $pngH px');

    final jpg = images.firstWhere((f) => f.path.endsWith('.jpg')).readAsBytesSync();
    expect(jpg.length, greaterThan(4));
    expect(jpg[0], 0xFF);
    expect(jpg[1], 0xD8, reason: 'app_logo.jpg không phải JPEG');
    var w = 0;
    var h = 0;
    var i = 2;
    while (i + 9 < jpg.length) {
      if (jpg[i] != 0xFF || jpg[i + 1] == 0xFF) {
        i++;
        continue;
      }
      final marker = jpg[i + 1];
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
        i += 2;
        continue;
      }
      final len = (jpg[i + 2] << 8) | jpg[i + 3];
      final isSof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isSof) {
        h = (jpg[i + 5] << 8) | jpg[i + 6];
        w = (jpg[i + 7] << 8) | jpg[i + 8];
        break;
      }
      i += 2 + len;
    }
    expect(w, greaterThanOrEqualTo(1024), reason: 'app_logo.jpg rộng $w px');
    expect(h, greaterThanOrEqualTo(1024), reason: 'app_logo.jpg cao $h px');
  });
}
