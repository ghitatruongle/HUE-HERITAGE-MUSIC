class Lesson {
  final String id;
  final String title;
  final String type;
  final String artist;
  final String modeSystem;
  final double? bpm;
  final bool hasOrnaments;
  final int sections;

  Lesson({
    required this.id,
    required this.title,
    required this.type,
    required this.artist,
    required this.modeSystem,
    required this.hasOrnaments,
    required this.sections,
    this.bpm,
  });

  static Lesson fromJson(Map<String, dynamic> j) => Lesson(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        artist: j['artist']?.toString() ?? '',
        modeSystem: j['mode_system']?.toString() ?? '',
        hasOrnaments: j['has_ornaments'] == true,
        sections: int.tryParse(j['sections']?.toString() ?? '0') ?? 0,
        bpm: double.tryParse(j['bpm']?.toString() ?? ''),
      );
}

class SectionLine {
  final double start;
  final double end;

  const SectionLine(this.start, this.end);
}

class LessonSection {
  final int index;
  final double start;
  final double end;
  final double duration;
  final String lyrics;
  final bool hasSample;
  final String sampleUrl;
  final List<SectionLine> lineTimes;

  LessonSection({
    required this.index,
    required this.start,
    required this.end,
    required this.duration,
    required this.lyrics,
    this.hasSample = false,
    this.sampleUrl = '',
    this.lineTimes = const [],
  });

  static LessonSection fromJson(Map<String, dynamic> j) => LessonSection(
        index: int.tryParse(j['index']?.toString() ?? '0') ?? 0,
        start: double.tryParse(j['start']?.toString() ?? '0') ?? 0,
        end: double.tryParse(j['end']?.toString() ?? '0') ?? 0,
        duration: double.tryParse(j['duration']?.toString() ?? '0') ?? 0,
        lyrics: j['lyrics']?.toString() ?? '',
        hasSample: j['has_sample'] == true,
        sampleUrl: j['sample_url']?.toString() ?? '',
        lineTimes: _lineTimes(j['line_times']),
      );

  static List<SectionLine> _lineTimes(raw) {
    if (raw is! List) return const [];
    final out = <SectionLine>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(SectionLine(
          double.tryParse(e['start']?.toString() ?? '0') ?? 0,
          double.tryParse(e['end']?.toString() ?? '0') ?? 0,
        ));
      }
    }
    return out;
  }
}

class LessonDetail {
  final String id;
  final String title;
  final String lyrics;
  final String modeSystem;
  final double? bpm;
  final List<LessonSection> sections;
  final List<double> contourTimes;
  final List<double> contourF0;

  LessonDetail({
    required this.id,
    required this.title,
    required this.lyrics,
    required this.modeSystem,
    required this.sections,
    required this.contourTimes,
    required this.contourF0,
    this.bpm,
  });

  static LessonDetail fromJson(Map<String, dynamic> j) {
    final contour = j['contour'];
    List<double> times = [];
    List<double> f0 = [];
    if (contour is Map) {
      times = _doubleList(contour['times']);
      f0 = _doubleList(contour['f0']);
    }
    final rawSections = j['sections'];
    final sections = <LessonSection>[];
    if (rawSections is List) {
      for (final s in rawSections) {
        if (s is Map) {
          sections.add(LessonSection.fromJson(Map<String, dynamic>.from(s)));
        }
      }
    }
    return LessonDetail(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      lyrics: j['lyrics']?.toString() ?? '',
      modeSystem: j['mode_system']?.toString() ?? '',
      bpm: double.tryParse(j['bpm']?.toString() ?? ''),
      sections: sections,
      contourTimes: times,
      contourF0: f0,
    );
  }

  static List<double> _doubleList(raw) {
    if (raw is! List) return [];
    return raw.map((v) => double.tryParse(v.toString()) ?? 0.0).toList();
  }
}

class ScaleInfo {
  final String id;
  final String name;
  final List<String> noteNames;

  ScaleInfo({required this.id, required this.name, required this.noteNames});

  static ScaleInfo fromJson(Map<String, dynamic> j) => ScaleInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        noteNames: (j['note_names'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

class ScaleNoteHit {
  final String name;
  final double share;
  final bool hit;

  ScaleNoteHit({required this.name, required this.share, required this.hit});
}

class ScalePerformanceNote {
  final String name;
  final double? errCents;
  final double onsetErrMs;
  final String verdict;
  final String verdictCode;
  final String hint;
  final List<String> hintCodes;

  ScalePerformanceNote({
    required this.name,
    required this.errCents,
    required this.onsetErrMs,
    required this.verdict,
    required this.verdictCode,
    required this.hint,
    this.hintCodes = const [],
  });

  static ScalePerformanceNote fromJson(Map<String, dynamic> j) {
    final rawErr = j['err_cents'];
    return ScalePerformanceNote(
      name: j['name']?.toString() ?? '',
      errCents: rawErr == null ? null : double.tryParse(rawErr.toString()),
      onsetErrMs: double.tryParse(j['onset_err_ms']?.toString() ?? '0') ?? 0,
      verdict: j['verdict']?.toString() ?? '',
      verdictCode: j['verdict_code']?.toString() ?? '',
      hint: j['hint']?.toString() ?? '',
      hintCodes: PracticeResult._codeList(j['hint_codes']),
    );
  }
}

class ScalePractice {
  final double score;
  final double pitchScore;
  final double rhythmScore;
  final double stabilityScore;
  final String scaleName;
  final int transpose;
  final double onScaleShare;
  final List<ScaleNoteHit> notes;
  final List<ScalePerformanceNote> performance;
  final String summaryHint;
  final Map<String, int> verdictCounts;
  final List<String> summaryCodes;

  ScalePractice({
    required this.score,
    required this.scaleName,
    required this.onScaleShare,
    required this.notes,
    this.pitchScore = 0,
    this.rhythmScore = 0,
    this.stabilityScore = 0,
    this.transpose = 0,
    this.performance = const [],
    this.summaryHint = '',
    this.verdictCounts = const {},
    this.summaryCodes = const [],
  });

  static ScalePractice fromJson(Map<String, dynamic> j) {
    final raw = j['notes'];
    final notes = <ScaleNoteHit>[];
    if (raw is List) {
      for (final n in raw) {
        if (n is Map) {
          notes.add(ScaleNoteHit(
            name: n['name']?.toString() ?? '',
            share: double.tryParse(n['share']?.toString() ?? '0') ?? 0,
            hit: n['hit'] == true,
          ));
        }
      }
    }
    final rawPerf = j['performance'];
    final perf = <ScalePerformanceNote>[];
    if (rawPerf is List) {
      for (final n in rawPerf) {
        if (n is Map) {
          perf.add(ScalePerformanceNote.fromJson(Map<String, dynamic>.from(n)));
        }
      }
    }
    final counts = <String, int>{};
    final rawCounts = j['verdict_counts'];
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        final n = int.tryParse(v.toString());
        if (n != null) counts[k.toString()] = n;
      });
    }
    final summaryCodes = <String>[];
    final rawSummaryCodes = j['summary_codes'];
    if (rawSummaryCodes is List) {
      for (final c in rawSummaryCodes) {
        summaryCodes.add(c.toString());
      }
    }
    return ScalePractice(
      score: double.tryParse(j['score']?.toString() ?? '0') ?? 0,
      scaleName: j['scale_name']?.toString() ?? '',
      onScaleShare: double.tryParse(j['on_scale_share']?.toString() ?? '0') ?? 0,
      notes: notes,
      pitchScore: double.tryParse(j['pitch_score']?.toString() ?? '0') ?? 0,
      rhythmScore: double.tryParse(j['rhythm_score']?.toString() ?? '0') ?? 0,
      stabilityScore: double.tryParse(j['stability_score']?.toString() ?? '0') ?? 0,
      transpose: int.tryParse(j['transpose']?.toString() ?? '0') ?? 0,
      performance: perf,
      summaryHint: j['summary_hint']?.toString() ?? '',
      verdictCounts: counts,
      summaryCodes: summaryCodes,
    );
  }
}

class PracticeMetrics {
  final double score;
  final double pitchScore;
  final double timeScore;
  final double rhythmScore;
  final double stabilityScore;
  final double ornament;
  final double meanAbsCents;
  final double vibratoRate;
  final int matchedNotes;
  final int unmatchedNotes;
  final int missingNotes;
  final String referenceQuality;
  final String summaryHint;
  final Map<String, int> verdictCounts;
  final List<String> summaryCodes;
  final bool truncated;
  final double? uploadedSeconds;
  final double? analyzedSeconds;

  PracticeMetrics({
    required this.score,
    required this.pitchScore,
    required this.timeScore,
    required this.meanAbsCents,
    this.rhythmScore = 0,
    this.stabilityScore = 0,
    this.ornament = 0,
    this.vibratoRate = 0,
    this.matchedNotes = 0,
    this.unmatchedNotes = 0,
    this.missingNotes = 0,
    this.referenceQuality = '',
    this.summaryHint = '',
    this.verdictCounts = const {},
    this.summaryCodes = const [],
    this.truncated = false,
    this.uploadedSeconds,
    this.analyzedSeconds,
  });
}

class PracticeNote {
  final double start;
  final double end;
  final double? errCents;
  final bool octaveDiff;
  final String verdict;
  final String verdictCode;
  final String hint;
  final List<String> hintCodes;
  final double onsetErrMs;
  final double refStart;
  final double refEnd;
  final bool vibrato;

  PracticeNote({
    required this.start,
    required this.end,
    required this.errCents,
    this.octaveDiff = false,
    required this.verdict,
    this.verdictCode = '',
    this.hint = '',
    this.hintCodes = const [],
    this.onsetErrMs = 0,
    this.refStart = 0,
    this.refEnd = 0,
    this.vibrato = false,
  });

  static PracticeNote? fromServerJson(dynamic raw) {
    if (raw is! Map) return null;
    final rawErr = raw['err_cents'];
    return PracticeNote(
      start: double.tryParse(raw['start']?.toString() ?? '0') ?? 0,
      end: double.tryParse(raw['end']?.toString() ?? '0') ?? 0,
      errCents: rawErr == null ? null : double.tryParse(rawErr.toString()),
      octaveDiff: raw['octave_diff'] == true,
      verdict: raw['verdict']?.toString() ?? '',
      verdictCode: raw['verdict_code']?.toString() ?? '',
      hint: raw['hint']?.toString() ?? '',
      hintCodes: PracticeResult._codeList(raw['hint_codes']),
      onsetErrMs: double.tryParse(raw['onset_err_ms']?.toString() ?? '0') ?? 0,
      refStart: double.tryParse(raw['ref_start']?.toString() ?? '0') ?? 0,
      refEnd: double.tryParse(raw['ref_end']?.toString() ?? '0') ?? 0,
      vibrato: raw['vibrato'] == true,
    );
  }
}

class PracticeWord {
  final int line;
  final int index;
  final String text;
  final double start;
  final double end;
  final double voicedRatio;
  final double? errCents;
  final String verdictCode;
  final String verdict;

  PracticeWord({
    required this.line,
    required this.index,
    required this.text,
    required this.start,
    required this.end,
    required this.voicedRatio,
    required this.errCents,
    required this.verdictCode,
    required this.verdict,
  });

  static PracticeWord? fromServerJson(dynamic raw) {
    if (raw is! Map) return null;
    final rawErr = raw['err_cents'];
    return PracticeWord(
      line: int.tryParse(raw['line']?.toString() ?? '0') ?? 0,
      index: int.tryParse(raw['index']?.toString() ?? '0') ?? 0,
      text: raw['text']?.toString() ?? '',
      start: double.tryParse(raw['start']?.toString() ?? '0') ?? 0,
      end: double.tryParse(raw['end']?.toString() ?? '0') ?? 0,
      voicedRatio: double.tryParse(raw['voiced_ratio']?.toString() ?? '0') ?? 0,
      errCents: rawErr == null ? null : double.tryParse(rawErr.toString()),
      verdictCode: raw['verdict_code']?.toString() ?? '',
      verdict: raw['verdict']?.toString() ?? '',
    );
  }
}

class PracticeResult {
  final PracticeMetrics metrics;
  final List<double> refTimes;
  final List<double> refF0;
  final List<double> userF0;
  final List<PracticeNote> notes;
  final List<PracticeWord> words;
  final String wordsAlignment;
  final int sectionIndex;
  final String lessonTitle;
  final String userMidi;
  final String reference;

  PracticeResult({
    required this.metrics,
    required this.refTimes,
    required this.refF0,
    required this.userF0,
    required this.notes,
    this.words = const [],
    this.wordsAlignment = '',
    required this.sectionIndex,
    required this.lessonTitle,
    this.userMidi = '',
    this.reference = '',
  });

  static List<String> _codeList(raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  static PracticeResult fromJson(Map<String, dynamic> j) {    final m = j['metrics'];
    double score = 0;
    double pitch = 0;
    double time = 0;
    double cents = 0;
    double rhythm = 0;
    double stability = 0;
    double ornament = 0;
    double vibRate = 0;
    int matched = 0;
    int unmatched = 0;
    int missing = 0;
    String quality = '';
    String hint = '';
    final counts = <String, int>{};
    final summaryCodes = <String>[];
    if (m is Map) {
      score = double.tryParse(m['score']?.toString() ?? '0') ?? 0;
      pitch = double.tryParse(m['pitch_score']?.toString() ?? '0') ?? 0;
      time = double.tryParse(m['time_score']?.toString() ?? '0') ?? 0;
      cents = double.tryParse(m['mean_abs_cents']?.toString() ?? '0') ?? 0;
      rhythm = double.tryParse(m['rhythm_score']?.toString() ?? '0') ?? 0;
      stability = double.tryParse(m['stability_score']?.toString() ?? '0') ?? 0;
      ornament = double.tryParse(m['ornament']?.toString() ?? '0') ?? 0;
      vibRate = double.tryParse(m['vibrato_rate']?.toString() ?? '0') ?? 0;
      matched = int.tryParse(m['matched_notes']?.toString() ?? '0') ?? 0;
      unmatched = int.tryParse(m['unmatched_notes']?.toString() ?? '0') ?? 0;
      missing = int.tryParse(m['missing_notes']?.toString() ?? '0') ?? 0;
      quality = m['reference_quality']?.toString() ?? '';
      hint = m['summary_hint']?.toString() ?? '';
      final rawCounts = m['verdict_counts'];
      if (rawCounts is Map) {
        rawCounts.forEach((k, v) {
          final n = int.tryParse(v.toString());
          if (n != null) counts[k.toString()] = n;
        });
      }
      final rawCodes = m['summary_codes'];
      if (rawCodes is List) {
        for (final c in rawCodes) {
          summaryCodes.add(c.toString());
        }
      }
    }
    final sample = j['sample'];
    final warped = j['user_warped'];
    List<double> times = [];
    List<double> ref = [];
    List<double> user = [];
    if (sample is Map) {
      times = LessonDetail._doubleList(sample['times']);
      ref = LessonDetail._doubleList(sample['f0']);
    }
    if (warped is Map) {
      user = LessonDetail._doubleList(warped['f0']);
    }
    final rawNotes = j['notes'];
    final notes = <PracticeNote>[];
    if (rawNotes is List) {
      for (final n in rawNotes) {
        final note = PracticeNote.fromServerJson(n);
        if (note != null) notes.add(note);
      }
    }
    final rawWords = j['words'];
    final words = <PracticeWord>[];
    if (rawWords is List) {
      for (final w in rawWords) {
        final word = PracticeWord.fromServerJson(w);
        if (word != null) words.add(word);
      }
    }
    final wordsAlignment = j['words_alignment']?.toString() ?? '';
    final section = j['section'];
    int sectionIndex = 0;
    if (section is Map) {
      sectionIndex = int.tryParse(section['index']?.toString() ?? '0') ?? 0;
    }
    return PracticeResult(
      metrics: PracticeMetrics(
        score: score,
        pitchScore: pitch,
        timeScore: time,
        meanAbsCents: cents,
        rhythmScore: rhythm,
        stabilityScore: stability,
        ornament: ornament,
        vibratoRate: vibRate,
        matchedNotes: matched,
        unmatchedNotes: unmatched,
        missingNotes: missing,
        referenceQuality: quality,
        summaryHint: hint,
        verdictCounts: counts,
        summaryCodes: summaryCodes,
        truncated: m is Map && m['truncated'] == true,
        uploadedSeconds: m is Map && m['uploaded_seconds'] != null ? double.tryParse(m['uploaded_seconds'].toString()) : null,
        analyzedSeconds: m is Map && m['analyzed_seconds'] != null ? double.tryParse(m['analyzed_seconds'].toString()) : null,
      ),
      refTimes: times,
      refF0: ref,
      userF0: user,
      notes: notes,
      words: words,
      wordsAlignment: wordsAlignment,
      sectionIndex: sectionIndex,
      lessonTitle: j['lesson_title']?.toString() ?? '',
      userMidi: j['user_midi']?.toString() ?? '',
      reference: j['reference']?.toString() ?? '',
    );
  }
}

class ProgressPage {
  final List<ProgressEntry> items;
  final String serverToday;

  ProgressPage({required this.items, this.serverToday = ''});
}

class ProgressEntry {
  final String lessonId;
  final int section;
  final double score;
  final double pitchScore;
  final double rhythmScore;
  final double stabilityScore;
  final String createdAt;

  ProgressEntry({
    required this.lessonId,
    required this.section,
    required this.score,
    required this.pitchScore,
    required this.rhythmScore,
    required this.stabilityScore,
    required this.createdAt,
  });

  static ProgressEntry fromJson(Map<String, dynamic> j) => ProgressEntry(
        lessonId: j['lesson_id']?.toString() ?? '',
        section: int.tryParse(j['section']?.toString() ?? '0') ?? 0,
        score: double.tryParse(j['score']?.toString() ?? '0') ?? 0,
        pitchScore: double.tryParse(j['pitch_score']?.toString() ?? '0') ?? 0,
        rhythmScore: double.tryParse(j['rhythm_score']?.toString() ?? '0') ?? 0,
        stabilityScore: double.tryParse(j['stability_score']?.toString() ?? '0') ?? 0,
        createdAt: j['created_at']?.toString() ?? '',
      );
}
