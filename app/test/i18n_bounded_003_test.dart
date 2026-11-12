import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _libDir = 'lib';
const Set<String> _allowedVietnameseFiles = {
  'lib/screens/creation/creation_screen.dart',
  'lib/widgets/server_onboarding_dialog.dart',
};

final RegExp _vietnamese = RegExp(r'[\u00C0-\u024F\u1EA0-\u1EF9]');

Set<String> _scanUiFiles() {
  final hits = <String>{};
  final roots = <FileSystemEntity>[
    Directory('$_libDir/screens'),
    Directory('$_libDir/widgets'),
    File('$_libDir/main.dart'),
  ];
  final files = <File>[];
  for (final root in roots) {
    if (root is File) {
      files.add(root);
    } else if (root is Directory) {
      files.addAll(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      );
    }
  }
  for (final f in files) {
    final normalized = f.path.replaceFirst('./', '');
    if (_vietnamese.hasMatch(f.readAsStringSync())) {
      hits.add(normalized);
    }
  }
  return hits;
}

void main() {
  test('i18n kin: khong string UI tieng Viet hardcode ngoai allowlist', () {
    final hits = _scanUiFiles();
    final leaked = hits.difference(_allowedVietnameseFiles);
    expect(
      leaked,
      isEmpty,
      reason: 'Vietnamese hardcoded trong UI code (phai di qua AppStrings): $leaked',
    );
    for (final allowed in _allowedVietnameseFiles) {
      expect(
        File(allowed).existsSync(),
        isTrue,
        reason: 'allowlist chi den file khong con ton tai: $allowed',
      );
    }
  });

  test('Allowlist creation chi chua API-value va tho mau - khong co label UI moi', () {
    final text = File('lib/screens/creation/creation_screen.dart').readAsStringSync();
    final lines = text.split('\n');
    final offenders = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_vietnamese.hasMatch(line)) continue;
      final isApiChoiceValue = line.contains("'Nữ'") ||
          line.contains("'Nam'") ||
          line.contains("'Không lời'") ||
          line.contains("'Chậm'") ||
          line.contains("'Vừa'") ||
          line.contains("'Nhanh'") ||
          line.contains("'Trữ tình'") ||
          line.contains("'Thiết tha'") ||
          line.contains("'Tươi vui'") ||
          line.contains("'Hào sảng'");
      final isSampleVerse = line.contains('Sông Hương') ||
          line.contains('Nắng trải cố đô') ||
          line.contains('Chiều chiều trước bến Văn Lâu');
      if (!isApiChoiceValue && !isSampleVerse) {
        offenders.add('lib/screens/creation/creation_screen.dart:${i + 1}: $line');
      }
    }
    expect(offenders, isEmpty, reason: 'Vietnamese moi khong thuoc allowlist: $offenders');
  });
}
