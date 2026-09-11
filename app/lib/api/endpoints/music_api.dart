import 'package:dio/dio.dart';

import '../../models/music_task.dart';

class MusicApi {
  final Dio dio;

  MusicApi(this.dio);

  Future<List<LoraAdapter>> models() async {
    final res = await dio.get('/api/music/models');
    final raw = res.data['adapters'];
    final list = <LoraAdapter>[];
    if (raw is List) {
      for (final e in raw) {
        list.add(LoraAdapter.fromJson(e as Map<String, dynamic>));
      }
    }
    return list;
  }

  Future<MusicTask> generate({
    required String prompt,
    int duration = 60,
    String lora = '',
  }) async {
    final res = await dio.post('/api/music/generate', queryParameters: {
      'prompt': prompt,
      'duration': duration,
      'lora': lora,
    });
    return MusicTask.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MusicTask> task(String id) async {
    final res = await dio.get('/api/music/task/$id');
    return MusicTask.fromJson(res.data as Map<String, dynamic>);
  }
}
