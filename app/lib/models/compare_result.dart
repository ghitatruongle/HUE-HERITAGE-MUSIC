class CompareMetrics {
  final double meanAbsCents;
  final double medianCents;
  final double meanOffsetMs;
  final double startOffsetMs;
  final int pairs;
  final double dtwDistance;
  final double pitchScore;
  final double timeScore;
  final double score;

  CompareMetrics({
    required this.meanAbsCents,
    required this.medianCents,
    required this.meanOffsetMs,
    required this.startOffsetMs,
    required this.pairs,
    required this.dtwDistance,
    required this.pitchScore,
    required this.timeScore,
    required this.score,
  });

  factory CompareMetrics.fromJson(Map<String, dynamic> json) {
    return CompareMetrics(
      meanAbsCents: (json['mean_abs_cents'] as num?)?.toDouble() ?? 0,
      medianCents: (json['median_cents'] as num?)?.toDouble() ?? 0,
      meanOffsetMs: (json['mean_offset_ms'] as num?)?.toDouble() ?? 0,
      startOffsetMs: (json['start_offset_ms'] as num?)?.toDouble() ?? 0,
      pairs: (json['pairs'] as num?)?.toInt() ?? 0,
      dtwDistance: (json['dtw_distance'] as num?)?.toDouble() ?? 0,
      pitchScore: (json['pitch_score'] as num?)?.toDouble() ?? 0,
      timeScore: (json['time_score'] as num?)?.toDouble() ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CompareNote {
  final int midi;
  final String name;
  final double start;
  final double end;
  final double errCents;
  final String verdict;

  CompareNote({
    required this.midi,
    required this.name,
    required this.start,
    required this.end,
    required this.errCents,
    required this.verdict,
  });

  factory CompareNote.fromJson(Map<String, dynamic> json) {
    final m = (json['midi'] as num?)?.toInt() ?? 60;
    return CompareNote(
      midi: m,
      name: '${['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'][m % 12]}${m ~/ 12 - 1}',
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
      errCents: (json['err_cents'] as num?)?.toDouble() ?? 0,
      verdict: json['verdict'] as String? ?? '',
    );
  }
}

class CompareResult {
  final CompareMetrics metrics;
  final List<double> times;
  final List<double> sampleF0;
  final List<double> warpedF0;
  final List<CompareNote> notes;

  CompareResult({
    required this.metrics,
    required this.times,
    required this.sampleF0,
    required this.warpedF0,
    required this.notes,
  });

  static List<double> _doubles(dynamic v) {
    if (v is List) {
      return v.map((e) => (e as num).toDouble()).toList();
    }
    return <double>[];
  }

  factory CompareResult.fromJson(Map<String, dynamic> json) {
    final m = json['metrics'] as Map<String, dynamic>? ?? {};
    final s = json['sample'] as Map<String, dynamic>? ?? {};
    final w = json['user_warped'] as Map<String, dynamic>? ?? {};
    final raw = json['notes'];
    final list = <CompareNote>[];
    if (raw is List) {
      for (final e in raw) {
        list.add(CompareNote.fromJson(e as Map<String, dynamic>));
      }
    }
    return CompareResult(
      metrics: CompareMetrics.fromJson(m),
      times: _doubles(s['times']),
      sampleF0: _doubles(s['f0']),
      warpedF0: _doubles(w['f0']),
      notes: list,
    );
  }
}
