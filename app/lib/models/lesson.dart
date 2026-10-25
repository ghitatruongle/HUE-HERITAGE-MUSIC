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

class LessonSection {
  final int index;
  final double start;
  final double end;
  final double duration;
  final String lyrics;

  LessonSection({
    required this.index,
    required this.start,
    required this.end,
    required this.duration,
    required this.lyrics,
  });

  static LessonSection fromJson(Map<String, dynamic> j) => LessonSection(
        index: int.tryParse(j['index']?.toString() ?? '0') ?? 0,
        start: double.tryParse(j['start']?.toString() ?? '0') ?? 0,
        end: double.tryParse(j['end']?.toString() ?? '0') ?? 0,
        duration: double.tryParse(j['duration']?.toString() ?? '0') ?? 0,
        lyrics: j['lyrics']?.toString() ?? '',
      );
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

class ScalePractice {
  final double score;
  final String scaleName;
  final double onScaleShare;
  final List<ScaleNoteHit> notes;

  ScalePractice({
    required this.score,
    required this.scaleName,
    required this.onScaleShare,
    required this.notes,
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
    return ScalePractice(
      score: double.tryParse(j['score']?.toString() ?? '0') ?? 0,
      scaleName: j['scale_name']?.toString() ?? '',
      onScaleShare: double.tryParse(j['on_scale_share']?.toString() ?? '0') ?? 0,
      notes: notes,
    );
  }
}

class PracticeMetrics {
  final double score;
  final double pitchScore;
  final double timeScore;
  final double meanAbsCents;

  PracticeMetrics({
    required this.score,
    required this.pitchScore,
    required this.timeScore,
    required this.meanAbsCents,
  });
}

class PracticeNote {
  final double start;
  final double end;
  final double errCents;
  final String verdict;

  PracticeNote({
    required this.start,
    required this.end,
    required this.errCents,
    required this.verdict,
  });
}

class PracticeResult {
  final PracticeMetrics metrics;
  final List<double> refTimes;
  final List<double> refF0;
  final List<double> userF0;
  final List<PracticeNote> notes;
  final int sectionIndex;
  final String lessonTitle;

  PracticeResult({
    required this.metrics,
    required this.refTimes,
    required this.refF0,
    required this.userF0,
    required this.notes,
    required this.sectionIndex,
    required this.lessonTitle,
  });

  static PracticeResult fromJson(Map<String, dynamic> j) {
    final m = j['metrics'];
    double score = 0;
    double pitch = 0;
    double time = 0;
    double cents = 0;
    if (m is Map) {
      score = double.tryParse(m['score']?.toString() ?? '0') ?? 0;
      pitch = double.tryParse(m['pitch_score']?.toString() ?? '0') ?? 0;
      time = double.tryParse(m['time_score']?.toString() ?? '0') ?? 0;
      cents = double.tryParse(m['mean_abs_cents']?.toString() ?? '0') ?? 0;
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
        if (n is Map) {
          notes.add(PracticeNote(
            start: double.tryParse(n['start']?.toString() ?? '0') ?? 0,
            end: double.tryParse(n['end']?.toString() ?? '0') ?? 0,
            errCents: double.tryParse(n['err_cents']?.toString() ?? '0') ?? 0,
            verdict: n['verdict']?.toString() ?? '',
          ));
        }
      }
    }
    final section = j['section'];
    int sectionIndex = 0;
    if (section is Map) {
      sectionIndex = int.tryParse(section['index']?.toString() ?? '0') ?? 0;
    }
    return PracticeResult(
      metrics: PracticeMetrics(score: score, pitchScore: pitch, timeScore: time, meanAbsCents: cents),
      refTimes: times,
      refF0: ref,
      userF0: user,
      notes: notes,
      sectionIndex: sectionIndex,
      lessonTitle: j['lesson_title']?.toString() ?? '',
    );
  }
}
