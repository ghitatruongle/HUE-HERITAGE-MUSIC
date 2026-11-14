import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/services/local_pitch.dart';

Uint8List sineWav(double freq, double seconds, {int sr = 16000}) {
  final n = (sr * seconds).toInt();
  final data = ByteData(44 + n * 2);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sr, Endian.little);
  data.setUint32(28, sr * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (0.8 * 32767 * math.sin(2 * math.pi * freq * i / sr)).toInt();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

double _meanF0(LocalPitchResult r) {
  final voiced = r.points.where((p) => p.f0 > 0).map((p) => p.f0).toList();
  expect(voiced, isNotEmpty);
  return voiced.reduce((a, b) => a + b) / voiced.length;
}

void main() {
  test('LocalPitch parabolic: sine 220Hz được đo sát (<±5Hz)', () {
    final r = LocalPitch.analyze(sineWav(220.0, 1.5))!;
    final mean = _meanF0(r);
    expect((mean - 220.0).abs() < 5.0, isTrue, reason: 'mean=$mean');
  });

  test('LocalPitch parabolic: sine 330Hz sát chuẩn (<±6Hz)', () {
    final r = LocalPitch.analyze(sineWav(330.0, 1.0))!;
    final mean = _meanF0(r);
    expect((mean - 330.0).abs() < 6.0, isTrue, reason: 'mean=$mean');
  });

  test('LocalPitch: WAV hỏng trả null', () {
    final bad = Uint8List.fromList(sineWav(220.0, 0.5).sublist(0, 30));
    expect(LocalPitch.analyze(bad), isNull);
  });

  test('AppStrings 0.0.4-preview: key mới có cho cả VI/EN', () {
    const vi = AppStrings('vi');
    const en = AppStrings('en');
    expect(vi.practiceRefPoorWarning, isNotEmpty);
    expect(en.practiceRefPoorWarning, isNotEmpty);
    expect(vi.practiceMatchedNotes(3, 1), contains('Khớp 3'));
    expect(en.practiceMatchedNotes(3, 1), contains('Matched 3'));
    expect(vi.verdictOk, 'Chuẩn');
    expect(en.verdictOk, 'In tune');
    expect(vi.practiceAutoGrade, isNotEmpty);
    expect(en.practiceAutoGrade, isNotEmpty);
    expect(vi.practiceGuideTitle, isNotEmpty);
    expect(en.practiceGuideTitle, isNotEmpty);
  });
}
