import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('C3: giá trị count-in chỉ được set khi mounted sau await', () {
    final src = File('lib/screens/learning/lesson_practice_view.dart').readAsLinesSync();
    final unguarded = <int>[];
    for (var i = 0; i < src.length; i++) {
      final line = src[i];
      if (line.contains('_countInLeft.value = 0') && !line.contains('if (mounted)')) {
        unguarded.add(i + 1);
      }
    }
    expect(unguarded, isEmpty,
        reason: 'set _countInLeft sau await phải có mounted-guard tại dòng: $unguarded');
  });

  test('C3: _countInLeft có dispose tương ứng trong State này', () {
    final src = File('lib/screens/learning/lesson_practice_view.dart').readAsLinesSync();
    expect(src.any((l) => l.contains('_countInLeft.dispose()')), isTrue);
  });
}
