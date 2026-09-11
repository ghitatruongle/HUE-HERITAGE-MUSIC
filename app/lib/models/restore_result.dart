class RestoreResult {
  final String label;
  final String sha;
  final int sampleRate;
  final double duration;
  final double dcRemoved;
  final int clicksFixed;
  final double peakBefore;
  final double peakAfter;
  final double noiseFloorDb;

  RestoreResult({
    required this.label,
    required this.sha,
    required this.sampleRate,
    required this.duration,
    required this.dcRemoved,
    required this.clicksFixed,
    required this.peakBefore,
    required this.peakAfter,
    required this.noiseFloorDb,
  });

  factory RestoreResult.fromJson(Map<String, dynamic> json) {
    return RestoreResult(
      label: json['label'] as String? ?? '',
      sha: json['sha'] as String? ?? '',
      sampleRate: (json['sample_rate'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      dcRemoved: (json['dc_removed'] as num?)?.toDouble() ?? 0,
      clicksFixed: (json['clicks_fixed'] as num?)?.toInt() ?? 0,
      peakBefore: (json['peak_before'] as num?)?.toDouble() ?? 0,
      peakAfter: (json['peak_after'] as num?)?.toDouble() ?? 0,
      noiseFloorDb: (json['noise_floor_db'] as num?)?.toDouble() ?? 0,
    );
  }
}
