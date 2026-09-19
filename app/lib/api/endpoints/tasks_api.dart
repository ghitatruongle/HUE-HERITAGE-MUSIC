import 'package:dio/dio.dart';

class ServerTask {
  final String id;
  final String kind;
  final String status;
  final String error;
  final Map<String, dynamic> result;
  final String createdAt;
  final String? finishedAt;

  ServerTask({
    required this.id,
    required this.kind,
    required this.status,
    this.error = '',
    this.result = const {},
    this.createdAt = '',
    this.finishedAt,
  });

  factory ServerTask.fromJson(Map<String, dynamic> j) => ServerTask(
        id: j['id']?.toString() ?? '',
        kind: j['kind']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        error: j['error']?.toString() ?? '',
        result: j['result'] is Map ? Map<String, dynamic>.from(j['result'] as Map) : const {},
        createdAt: j['created_at']?.toString() ?? '',
        finishedAt: j['finished_at']?.toString(),
      );
}

class TasksApi {
  final Dio dio;

  TasksApi(this.dio);

  Future<List<ServerTask>> list({String kind = '', String status = ''}) async {
    final res = await dio.get('/api/task', queryParameters: {'kind': kind, 'status': status});
    final data = res.data;
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => ServerTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<ServerTask> get(String id) async {
    final res = await dio.get('/api/task/$id');
    final data = res.data;
    if (data is Map) {
      return ServerTask.fromJson(Map<String, dynamic>.from(data));
    }
    return ServerTask(id: id, kind: '', status: 'unknown');
  }
}
