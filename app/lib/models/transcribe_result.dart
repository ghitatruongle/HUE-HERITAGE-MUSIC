class TransNote {
  final int midi;
  final String name;
  final double start;
  final double end;

  TransNote({
    required this.midi,
    required this.name,
    required this.start,
    required this.end,
  });

  static const _names = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static String noteName(int midi) {
    final m = midi < 0 ? 0 : (midi > 127 ? 127 : midi);
    return '${_names[m % 12]}${m ~/ 12 - 1}';
  }

  factory TransNote.fromJson(Map<String, dynamic> json) {
    final m = (json['midi'] as num?)?.toInt() ?? 60;
    return TransNote(
      midi: m,
      name: noteName(m),
      start: (json['start'] as num?)?.toDouble() ?? 0,
      end: (json['end'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TranscribeResult {
  final String label;
  final double bpm;
  final String sha;
  final List<TransNote> notes;

  TranscribeResult({
    required this.label,
    required this.bpm,
    required this.sha,
    required this.notes,
  });

  factory TranscribeResult.fromJson(Map<String, dynamic> json) {
    final raw = json['notes'];
    final list = <TransNote>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(TransNote.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return TranscribeResult(
      label: json['label']?.toString() ?? '',
      bpm: (json['bpm'] as num?)?.toDouble() ?? 60,
      sha: json['sha']?.toString() ?? '',
      notes: list,
    );
  }
}
