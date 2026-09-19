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
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      audioUrl: json['audio_url']?.toString() ?? '',
      info: json['info']?.toString() ?? '',
    );
  }
}

class LoraAdapter {
  final String name;
  final bool ready;

  LoraAdapter({required this.name, required this.ready});

  factory LoraAdapter.fromJson(Map<String, dynamic> json) {
    return LoraAdapter(
      name: json['name']?.toString() ?? '',
      ready: json['ready'] == true,
    );
  }
}
