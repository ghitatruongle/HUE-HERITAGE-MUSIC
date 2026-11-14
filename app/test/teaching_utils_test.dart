import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/core/localization/app_strings.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/services/teaching_utils.dart';

void main() {
  const vi = AppStrings('vi');
  const en = AppStrings('en');

  group('currentLineIndex', () {
    test('uses real line windows with offset', () {
      final lines = [
        const SectionLine(10.0, 13.5),
        const SectionLine(13.5, 16.0),
        const SectionLine(16.0, 19.0),
      ];
      expect(
        currentLineIndex(lineTimes: lines, lineCount: 3, duration: 9, elapsed: 3.0, offset: 10.0),
        0,
      );
      expect(
        currentLineIndex(lineTimes: lines, lineCount: 3, duration: 9, elapsed: 4.0, offset: 10.0),
        1,
      );
      expect(
        currentLineIndex(lineTimes: lines, lineCount: 3, duration: 9, elapsed: 8.9, offset: 10.0),
        2,
      );
    });

    test('falls back to equal time when lineTimes missing', () {
      expect(
        currentLineIndex(lineTimes: const [], lineCount: 2, duration: 10, elapsed: 3),
        0,
      );
      expect(
        currentLineIndex(lineTimes: const [], lineCount: 2, duration: 10, elapsed: 7),
        1,
      );
    });

    test('clamps before first and after last window', () {
      final lines = [const SectionLine(2.0, 4.0), const SectionLine(4.0, 6.0)];
      expect(
        currentLineIndex(lineTimes: lines, lineCount: 2, duration: 8, elapsed: 0, offset: 0),
        0,
      );
      expect(
        currentLineIndex(lineTimes: lines, lineCount: 2, duration: 8, elapsed: 99, offset: 0),
        1,
      );
    });
  });

  group('wordScores', () {
    test('maps notes to word windows and keeps worst verdict', () {
      final section = LessonSection(
        index: 0,
        start: 10.0,
        end: 16.0,
        duration: 6.0,
        lyrics: 'một hai ba',
        lineTimes: [const SectionLine(10.0, 13.0), const SectionLine(13.0, 16.0)],
      );
      final notes = [
        PracticeNote(start: 0.5, end: 1.0, errCents: 10, verdict: 'Chuẩn', verdictCode: 'ok'),
        PracticeNote(start: 2.0, end: 2.5, errCents: -80, verdict: 'Lệch', verdictCode: 'off'),
      ];
      final words = wordScores(section, notes);
      expect(words.length, 3);
      expect(words[0].word, 'một');
      expect(words[0].verdictCode, 'ok');
      expect(words[1].word, 'hai');
      expect(words[1].verdictCode, 'off');
      expect(words[2].word, 'ba');
      expect(words[2].verdictCode, '');
    });

    test('empty lyrics or notes yields nothing', () {
      final section = LessonSection(index: 0, start: 0, end: 5, duration: 5, lyrics: '');
      expect(wordScores(section, [PracticeNote(start: 0, end: 1, errCents: 0, verdict: 'x')]), isEmpty);
      final section2 = LessonSection(index: 0, start: 0, end: 5, duration: 5, lyrics: 'abc');
      expect(wordScores(section2, const []), isEmpty);
    });
  });

  group('practiceStatsFromDates', () {
    final now = DateTime(2026, 11, 14, 12);
    test('counts consecutive days including today', () {
      final dates = [DateTime(2026, 11, 12), DateTime(2026, 11, 13), DateTime(2026, 11, 14, 9)];
      final s = practiceStatsFromDates(dates, now);
      expect(s.streakDays, 3);
      expect(s.totalPractices, 3);
      expect(s.last7Counts, [0, 0, 0, 0, 1, 1, 1]);
    });

    test('streak survives when today has no practice yet', () {
      final dates = [DateTime(2026, 11, 12), DateTime(2026, 11, 13)];
      final s = practiceStatsFromDates(dates, now);
      expect(s.streakDays, 2);
    });

    test('gap breaks the streak', () {
      final dates = [DateTime(2026, 11, 10), DateTime(2026, 11, 13)];
      final s = practiceStatsFromDates(dates, now);
      expect(s.streakDays, 1);
    });
  });

  group('hint translation', () {
    test('noteHintText composes localized text from codes', () {
      final viText = noteHintText(['pitch_high', 'onset_late'], 96.4, 150.0, false, '', vi);
      expect(viText, contains('Cao hơn 96 cents'));
      expect(viText, contains('Vào trễ 150 ms'));
      final enText = noteHintText(['pitch_low', 'hold_longer'], -60.0, 0.0, false, '', en);
      expect(enText, contains('Too low by 60 cents'));
      expect(enText, contains('Hold the note longer'));
    });

    test('noteHintText falls back to server text when no codes', () {
      expect(noteHintText(const [], 0, 0, false, 'Gợi ý gốc', vi), 'Gợi ý gốc');
    });

    test('summaryHintText composes counts localized', () {
      final viText = summaryHintText(
        verdictCounts: {'ok': 5, 'minor': 2, 'off': 1, 'unclear': 0},
        summaryCodes: ['ok_count', 'minor_count', 'missing_count'],
        missingNotes: 3,
        fallback: '',
        strings: vi,
      );
      expect(viText, '5 nốt chuẩn, 2 nốt lệch nhẹ, thiếu 3 nốt so với mẫu');
      final enText = summaryHintText(
        verdictCounts: {'ok': 5},
        summaryCodes: ['ref_poor', 'ok_count'],
        missingNotes: 0,
        fallback: '',
        strings: en,
      );
      expect(enText, contains('Master sample unclear'));
      expect(enText, contains('5 notes in tune'));
    });

    test('summaryHintText falls back when codes empty', () {
      expect(
        summaryHintText(
          verdictCounts: const {},
          summaryCodes: const [],
          missingNotes: 0,
          fallback: 'hint gốc',
          strings: en,
        ),
        'hint gốc',
      );
    });
  });

  group('parsePracticeDate', () {
    test('parses sqlite datetime with space separator', () {
      final d = parsePracticeDate('2026-11-14 09:30:00.123');
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 11);
      expect(d.day, 14);
    });

    test('utc server stamp shifted to local day by offset', () {
      final d = parsePracticeDate('2026-11-13 18:30:00', utcOffset: const Duration(hours: 7));
      expect(d!.year, 2026);
      expect(d.month, 11);
      expect(d.day, 14);
      expect(d.hour, 1);
      expect(d.minute, 30);
    });

    test('negative offset shifts back a day', () {
      final d = parsePracticeDate('2026-11-14 02:00:00', utcOffset: const Duration(hours: -5));
      expect(d!.day, 13);
      expect(d.hour, 21);
    });

    test('returns null for garbage', () {
      expect(parsePracticeDate(''), isNull);
      expect(parsePracticeDate('không phải ngày'), isNull);
    });
  });
}
