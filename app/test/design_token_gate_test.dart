import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Design token gate: radius + padding chỉ dùng AppRadius/AppSpacing scale', () {
    const radiusAllowed = {'0', '4', '8', '12', '14', '20'};
    const padAllowed = {'0', '4', '8', '12', '16', '20', '24', '32'};
    final radiusRe = RegExp(r'(BorderRadius|Radius)\.circular\(([\d.]+)\)');
    final padKeyRe = RegExp(r'\b(horizontal|vertical|top|bottom|left|right):\s*(\d+\.?\d*)\b');
    final padFnRe = RegExp(r'EdgeInsets\.(all|fromLTRB)\(([^)]*)\)');
    final numberRe = RegExp(r'^\d+\.?\d*$');
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in radiusRe.allMatches(src)) {
        final v = m.group(2)!;
        if (!radiusAllowed.contains(v)) {
          violations.add('${f.path}: circular($v)');
        }
      }
      for (final m in padKeyRe.allMatches(src)) {
        final v = m.group(2)!;
        if (!padAllowed.contains(v)) {
          violations.add('${f.path}: ${m.group(1)}: $v');
        }
      }
      for (final m in padFnRe.allMatches(src)) {
        for (final raw in m.group(2)!.split(',')) {
          final v = raw.trim();
          if (numberRe.hasMatch(v) && !padAllowed.contains(v)) {
            violations.add('${f.path}: EdgeInsets.${m.group(1)}($v)');
          }
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Padding/radius lệch token scale: ${violations.take(20).join(' | ')}',
    );
  });

  test('Design token gate: fontSize chỉ dùng giá trị đã whitelist', () {
    const fontSizeAllowed = {'11', '12', '13', '14', '15', '17', '18', '19', '22', '26'};
    final fontSizeRe = RegExp(r'fontSize:\s*([\d.]+)');
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in fontSizeRe.allMatches(src)) {
        final v = m.group(1)!;
        if (!fontSizeAllowed.contains(v)) {
          violations.add('${f.path}: fontSize($v)');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'FontSize lệch whitelist: ${violations.take(20).join(' | ')}',
    );
  });

  test('Design token gate: mọi IconData qua HueIcon — cấm Icon(HueIcons. trực tiếp', () {
    final iconRe = RegExp(r'(?<![A-Za-z])Icon\(HueIcons\.');
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final src = f.readAsStringSync();
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (iconRe.hasMatch(lines[i])) {
          violations.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Icon phải qua HueIcon để có semanticLabel từ map: ${violations.take(20).join(' | ')}',
    );
  });

  test('Design token gate: màu hardcode chỉ nằm whitelist (token/gradient/motif/ink có test)', () {
    const whitelistFiles = {
      'lib/core/theme/app_theme.dart',
      'lib/widgets/heritage_motif.dart',
      'lib/widgets/hue_button.dart',
      'lib/screens/home/home_screen.dart',
      'lib/screens/heritage/heritage_list_screen.dart',
      'lib/screens/creation/creation_screen.dart',
      'lib/screens/history/history_screen.dart',
      'lib/widgets/feature_header.dart',
      'lib/widgets/responsive_layout.dart',
    };
    final colorRe = RegExp(r'Color\(0x|Colors\.[a-zA-Z]+');
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final normalized = f.path.replaceAll('\\', '/');
      if (whitelistFiles.contains(normalized)) {
        continue;
      }
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final m in colorRe.allMatches(lines[i])) {
          if (m.group(0) == 'Colors.transparent') {
            continue;
          }
          violations.add('${f.path}:${i + 1} ${m.group(0)}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'Màu phải qua AppTheme/ColorScheme; whitelist: token source, gradient brand, palette motif, danger ink có test: ${violations.take(20).join(' | ')}',
    );
  });
}
