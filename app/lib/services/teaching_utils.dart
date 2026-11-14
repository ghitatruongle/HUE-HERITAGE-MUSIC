import '../core/localization/app_strings.dart';
import '../models/lesson.dart';

class WordScore {
  final String word;
  final double start;
  final double end;
  final String verdictCode;
  final double errCents;
  final double onsetErrMs;

  const WordScore({
    required this.word,
    required this.start,
    required this.end,
    required this.verdictCode,
    required this.errCents,
    required this.onsetErrMs,
  });
}

class PracticeStats {
  final int streakDays;
  final int totalPractices;
  final List<int> last7Counts;

  const PracticeStats({
    required this.streakDays,
    required this.totalPractices,
    required this.last7Counts,
  });
}

int _verdictRank(String code) {
  switch (code) {
    case 'off':
    case 'octave':
      return 3;
    case 'minor':
      return 2;
    case 'ok':
      return 1;
    case 'unclear':
      return 0;
    default:
      return -1;
  }
}

int currentLineIndex({
  required List<SectionLine> lineTimes,
  required int lineCount,
  required double duration,
  required double elapsed,
  double offset = 0,
}) {
  if (lineCount <= 0) return 0;
  if (lineTimes.length == lineCount) {
    if (elapsed < lineTimes.first.start - offset) return 0;
    for (var i = 0; i < lineTimes.length; i++) {
      if (elapsed >= lineTimes[i].start - offset && elapsed < lineTimes[i].end - offset) return i;
    }
    return lineCount - 1;
  }
  final lineDur = duration / lineCount;
  if (lineDur <= 0) return 0;
  return (elapsed / lineDur).floor().clamp(0, lineCount - 1);
}

List<WordScore> wordScores(LessonSection section, List<PracticeNote> notes) {
  final lines = section.lyrics.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty || notes.isEmpty) return const [];
  final out = <WordScore>[];
  for (var li = 0; li < lines.length; li++) {
    double a;
    double b;
    if (section.lineTimes.length == lines.length) {
      a = section.lineTimes[li].start - section.start;
      b = section.lineTimes[li].end - section.start;
    } else {
      final d = section.duration / lines.length;
      a = li * d;
      b = (li + 1) * d;
    }
    if (b <= a) continue;
    final tokens = lines[li].trim().split(RegExp(r'\s+'));
    final span = b - a;
    var pos = a;
    for (var ti = 0; ti < tokens.length; ti++) {
      final we = ti == tokens.length - 1 ? b : pos + span / tokens.length;
      PracticeNote? worst;
      for (final nt in notes) {
        final mid = (nt.start + nt.end) / 2;
        if (mid >= pos && mid < we) {
          if (worst == null || _verdictRank(nt.verdictCode) > _verdictRank(worst.verdictCode)) {
            worst = nt;
          }
        }
      }
      out.add(WordScore(
        word: tokens[ti],
        start: pos,
        end: we,
        verdictCode: worst?.verdictCode ?? '',
        errCents: worst?.errCents ?? 0,
        onsetErrMs: worst?.onsetErrMs ?? 0,
      ));
      pos = we;
    }
  }
  return out;
}

String noteHintText(List<String> hintCodes, double errCents, double onsetErrMs, bool vibrato, String fallback, AppStrings strings) {
  if (hintCodes.isEmpty) return fallback;
  final parts = <String>[];
  for (final c in hintCodes) {
    switch (c) {
      case 'pitch_high':
        parts.add(strings.practiceHintPitchHigh(errCents.abs().round()));
        break;
      case 'pitch_low':
        parts.add(strings.practiceHintPitchLow(errCents.abs().round()));
        break;
      case 'pitch_slightly_high':
        parts.add(strings.practiceHintPitchSlightlyHigh(errCents.abs().round()));
        break;
      case 'pitch_slightly_low':
        parts.add(strings.practiceHintPitchSlightlyLow(errCents.abs().round()));
        break;
      case 'onset_late':
        parts.add(strings.practiceHintOnsetLate(onsetErrMs.round()));
        break;
      case 'onset_early':
        parts.add(strings.practiceHintOnsetEarly(onsetErrMs.abs().round()));
        break;
      case 'hold_longer':
        parts.add(strings.practiceHintHoldLonger);
        break;
      case 'vibrato_good':
        parts.add(strings.practiceHintVibratoGood);
        break;
      case 'unclear_voice':
        parts.add(strings.practiceHintUnclearVoice);
        break;
      case 'ref_unclear_here':
        parts.add(strings.practiceHintRefUnclearHere);
        break;
      case 'note_not_in_ref':
        parts.add(strings.practiceHintNoteNotInRef);
        break;
      default:
        break;
    }
  }
  if (parts.isEmpty && fallback.isNotEmpty) return fallback;
  return parts.join('; ');
}

String summaryHintText({
  required Map<String, int> verdictCounts,
  required List<String> summaryCodes,
  required int missingNotes,
  required String fallback,
  required AppStrings strings,
}) {
  if (summaryCodes.isEmpty) return fallback;
  final parts = <String>[];
  for (final code in summaryCodes) {
    switch (code) {
      case 'ref_poor':
        parts.add(strings.practiceHintSummaryRefPoor);
        break;
      case 'ok_count':
        parts.add(strings.practiceHintCountOk(verdictCounts['ok'] ?? 0));
        break;
      case 'minor_count':
        parts.add(strings.practiceHintCountMinor(verdictCounts['minor'] ?? 0));
        break;
      case 'off_count':
        parts.add(strings.practiceHintCountOff(verdictCounts['off'] ?? 0));
        break;
      case 'unclear_count':
        parts.add(strings.practiceHintCountUnclear(verdictCounts['unclear'] ?? 0));
        break;
      case 'missing_count':
        parts.add(strings.practiceHintCountMissing(missingNotes));
        break;
      default:
        break;
    }
  }
  if (parts.isEmpty && fallback.isNotEmpty) return fallback;
  return parts.join(', ');
}

DateTime? parsePracticeDate(String raw, {Duration? utcOffset}) {
  if (raw.isEmpty) return null;
  var s = raw.trim();
  if (s.length >= 10 && s[10] == ' ') {
    s = '${s.substring(0, 10)}T${s.substring(11)}';
  }
  final dt = DateTime.tryParse(s);
  if (dt != null) {
    return utcOffset == null ? dt : dt.add(utcOffset);
  }
  if (raw.length >= 10) {
    final d = DateTime.tryParse(raw.substring(0, 10));
    if (d == null) return null;
    return utcOffset == null ? d : d.add(utcOffset);
  }
  return null;
}

PracticeStats practiceStatsFromDates(List<DateTime> dates, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final days = dates.map((d) => DateTime(d.year, d.month, d.day)).toSet();
  var streak = 0;
  var cursor = today;
  if (!days.contains(cursor)) {
    cursor = today.subtract(const Duration(days: 1));
  }
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  final last7 = List<int>.filled(7, 0);
  for (final d in dates) {
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff >= 0 && diff < 7) {
      last7[6 - diff]++;
    }
  }
  return PracticeStats(streakDays: streak, totalPractices: dates.length, last7Counts: last7);
}
