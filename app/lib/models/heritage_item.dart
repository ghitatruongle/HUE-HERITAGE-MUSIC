class HeritageItem {
  final String id;
  final String title;
  final String type;
  final String artist;
  final String genre;
  final String composer;
  final String performers;
  final String artisans;
  final String collector;
  final String recordedTime;
  final String location;
  final String source;
  final String license;
  final String lyrics;
  final String instruments;
  final String tonal;
  final String description;
  final String notes;
  final double? bpm;
  final String sha256;
  final int size;
  final String createdAt;

  HeritageItem({
    required this.id,
    required this.title,
    required this.type,
    required this.artist,
    required this.sha256,
    required this.size,
    required this.createdAt,
    this.genre = '',
    this.composer = '',
    this.performers = '',
    this.artisans = '',
    this.collector = '',
    this.recordedTime = '',
    this.location = '',
    this.source = '',
    this.license = '',
    this.lyrics = '',
    this.instruments = '',
    this.tonal = '',
    this.description = '',
    this.notes = '',
    this.bpm,
  });

  factory HeritageItem.fromJson(Map<String, dynamic> json) {
    return HeritageItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
      composer: json['composer'] as String? ?? '',
      performers: json['performers'] as String? ?? '',
      artisans: json['artisans'] as String? ?? '',
      collector: json['collector'] as String? ?? '',
      recordedTime: json['recorded_time'] as String? ?? '',
      location: json['location'] as String? ?? '',
      source: json['source'] as String? ?? '',
      license: json['license'] as String? ?? '',
      lyrics: json['lyrics'] as String? ?? '',
      instruments: json['instruments'] as String? ?? '',
      tonal: json['tonal'] as String? ?? '',
      description: json['description'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      bpm: (json['bpm'] as num?)?.toDouble(),
      sha256: json['sha256'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, String> metadataRows() {
    final rows = <String, String>{
      'Loại hình': type,
      'Thể loại': genre,
      'Nghệ nhân / Nghệ sĩ': artist,
      'Tác giả': composer,
      'Người biểu diễn': performers,
      'Nhạc cụ': instruments,
      'Thời gian thu': recordedTime,
      'Địa điểm': location,
      'Nguồn': source,
      'Quyền sử dụng': license,
      'Cung bậc / Tông': tonal,
      if (bpm != null) 'BPM': bpm!.toStringAsFixed(0),
    };
    rows.removeWhere((_, v) => v.isEmpty);
    return rows;
  }
}
