class PitchData {
  final double meanF0;
  final int frames;
  final List<double> times;
  final List<double> f0;

  PitchData({
    required this.meanF0,
    required this.frames,
    required this.times,
    required this.f0,
  });

  static List<double> _doubles(dynamic v) {
    if (v is List) {
      final out = <double>[];
      for (final e in v) {
        if (e is num) {
          out.add(e.toDouble());
        } else if (e is String) {
          final p = double.tryParse(e);
          if (p != null) out.add(p);
        }
      }
      return out;
    }
    return <double>[];
  }

  factory PitchData.fromJson(Map<String, dynamic> json) {
    return PitchData(
      meanF0: (json['mean_f0'] as num?)?.toDouble() ?? 0,
      frames: (json['frames'] as num?)?.toInt() ?? 0,
      times: _doubles(json['times']),
      f0: _doubles(json['f0']),
    );
  }
}
