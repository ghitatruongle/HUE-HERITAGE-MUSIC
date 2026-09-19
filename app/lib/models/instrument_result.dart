class InstrumentSegment {
  final double start;
  final double end;
  final String instrument;
  final double confidence;

  InstrumentSegment({
    required this.start,
    required this.end,
    required this.instrument,
    required this.confidence,
  });

  factory InstrumentSegment.fromJson(Map<String, dynamic> json) {
    return InstrumentSegment(
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
      instrument: json['instrument'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class InstrumentResult {
  final String label;
  final List<InstrumentSegment> segments;

  InstrumentResult({required this.label, required this.segments});

  factory InstrumentResult.fromJson(Map<String, dynamic> json) {
    final raw = json['segments'];
    final list = <InstrumentSegment>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(InstrumentSegment.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return InstrumentResult(
      label: json['label']?.toString() ?? '',
      segments: list,
    );
  }
}
