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
  final String modeSystem;
  final String verseStructure;
  final String rhymeGuide;
  final String lyricsWithOrnaments;
  final bool isInstrumental;
  final String audioBackingPath;
  final bool featuredInCreation;
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
    this.modeSystem = '',
    this.verseStructure = '',
    this.rhymeGuide = '',
    this.lyricsWithOrnaments = '',
    this.isInstrumental = false,
    this.audioBackingPath = '',
    this.featuredInCreation = true,
    this.bpm,
  });

  static bool _parseBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return fallback;
  }

  factory HeritageItem.fromJson(Map<String, dynamic> json) {
    return HeritageItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      genre: json['genre']?.toString() ?? '',
      composer: json['composer']?.toString() ?? '',
      performers: json['performers']?.toString() ?? '',
      artisans: json['artisans']?.toString() ?? '',
      collector: json['collector']?.toString() ?? '',
      recordedTime: json['recorded_time']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      license: json['license']?.toString() ?? '',
      lyrics: json['lyrics']?.toString() ?? '',
      instruments: json['instruments']?.toString() ?? '',
      tonal: json['tonal']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      modeSystem: json['mode_system']?.toString() ?? '',
      verseStructure: json['verse_structure']?.toString() ?? '',
      rhymeGuide: json['rhyme_guide']?.toString() ?? '',
      lyricsWithOrnaments: json['lyrics_with_ornaments']?.toString() ?? '',
      isInstrumental: _parseBool(json['is_instrumental'], fallback: false),
      audioBackingPath: json['audio_backing_path']?.toString() ?? '',
      featuredInCreation: _parseBool(json['featured_in_creation'], fallback: true),
      bpm: (json['bpm'] as num?)?.toDouble(),
      sha256: json['sha256']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  Map<String, String> metadataRows() {
    final rows = <String, String>{
      'Loại hình': type,
      'Thể loại': genre,
      'Hơi / Điệu thức': modeSystem.isNotEmpty ? modeSystem : tonal,
      'Cấu trúc thể thơ': verseStructure,
      'Nghệ nhân / Nghệ sĩ': artist,
      'Tác giả': composer,
      'Người biểu diễn': performers,
      'Nhạc cụ': instruments,
      'Thời gian thu': recordedTime,
      'Địa điểm': location,
      'Nguồn': source,
      'Quyền sử dụng': license,
      if (bpm != null) 'BPM': bpm!.toStringAsFixed(0),
    };
    rows.removeWhere((_, v) => v.isEmpty);
    return rows;
  }
}
