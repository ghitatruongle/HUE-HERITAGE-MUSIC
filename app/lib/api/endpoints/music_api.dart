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
    double strength = 0.8,
    int seed = 0,
    String lyrics = '',
    String genre = '',
    String instruments = '',
    String tempo = '',
    String mood = '',
    String vocal = '',
  }) async {
    final res = await dio.post('/api/music/generate', queryParameters: {
      'prompt': prompt,
      'duration': duration,
      'lora': lora,
      'strength': strength,
      'seed': seed,
      'lyrics': lyrics,
      'genre': genre,
      'instruments': instruments,
      'tempo': tempo,
      'mood': mood,
      'vocal': vocal,
    });
    return MusicTask.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MusicTask> cover({
    required String heritageId,
    required String style,
    int duration = 60,
    String lora = '',
    double strength = 0.8,
    String tempo = '',
    String mood = '',
    String vocal = '',
  }) async {
    final res = await dio.post('/api/music/cover', queryParameters: {
      'heritage_id': heritageId,
      'style': style,
      'duration': duration,
      'lora': lora,
      'strength': strength,
      'tempo': tempo,
      'mood': mood,
      'vocal': vocal,
    });
    return MusicTask.fromJson(res.data as Map<String, dynamic>);
  }

  Future<MusicTask> task(String id) async {
    final res = await dio.get('/api/music/task/$id');
    return MusicTask.fromJson(res.data as Map<String, dynamic>);
  }
}
