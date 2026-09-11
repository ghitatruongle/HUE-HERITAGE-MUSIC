class MusicTask {
  final String id;
  final String kind;
  final String status;
  final String reason;

  MusicTask({
    required this.id,
    required this.kind,
    required this.status,
    required this.reason,
  });

  factory MusicTask.fromJson(Map<String, dynamic> json) {
    return MusicTask(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      status: json['status'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
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
