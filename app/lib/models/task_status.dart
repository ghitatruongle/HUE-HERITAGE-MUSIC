class TaskStatus {
  final String id;
  final String kind;
  final String status;

  TaskStatus({
    required this.id,
    required this.kind,
    required this.status,
  });

  factory TaskStatus.fromJson(Map<String, dynamic> json) {
    return TaskStatus(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }
}
