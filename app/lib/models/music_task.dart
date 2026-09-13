class MusicTask {
  final String id;
  final String kind;
  final String status;
  final String reason;
  final String audioUrl;
  final String info;

  MusicTask({
    required this.id,
    required this.kind,
    required this.status,
    required this.reason,
    this.audioUrl = '',
    this.info = '',
  });

  factory MusicTask.fromJson(Map<String, dynamic> json) {
    return MusicTask(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      status: json['status'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      audioUrl: json['audio_url'] as String? ?? '',
      info: json['info'] as String? ?? '',
    );
  }
}

class LoraAdapter {
  final String name;
  final bool ready;

  LoraAdapter({required this.name, required this.ready});

  factory LoraAdapter.fromJson(Map<String, dynamic> json) {
    return LoraAdapter(
      name: json['name'] as String? ?? '',
      ready: json['ready'] as bool? ?? false,
    );
  }
}
