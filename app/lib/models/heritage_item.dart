class HeritageItem {
  final String id;
  final String title;
  final String type;
  final String artist;
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
  });

  factory HeritageItem.fromJson(Map<String, dynamic> json) {
    return HeritageItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
