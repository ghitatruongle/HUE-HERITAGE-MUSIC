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
      return v.map((e) => (e as num).toDouble()).toList();
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
