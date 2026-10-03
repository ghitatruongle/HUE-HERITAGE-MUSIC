import 'package:dio/dio.dart';

import '../../models/heritage_item.dart';
import '../../models/music_task.dart';

class MusicApi {
  final Dio dio;

  MusicApi(this.dio);

  Future<List<LoraAdapter>> models() async {
    final res = await dio.get('/api/music/models');
    final data = res.data;
    if (data is! Map) return [];
    final raw = data['adapters'];
    final list = <LoraAdapter>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(LoraAdapter.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return list;
  }

  Future<List<HeritageItem>> getHeritageTunes() async {
    final res = await dio.get('/api/music/heritage-tunes');
    final raw = res.data;
    final list = <HeritageItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(HeritageItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return list;
  }

  Future<MusicTask> singOriginal({
    required String heritageId,
    String vocal = 'Nữ',
    String tempo = 'Vừa',
    String lora = '',
    double strength = 0.8,
    int duration = 60,
    int seed = 0,
  }) async {
    final res = await dio.post('/api/music/sing-original', queryParameters: {
      'heritage_id': heritageId,
      'vocal': vocal,
      'tempo': tempo,
      'lora': lora,
      'strength': strength,
      'duration': duration,
      'seed': seed,
    });
    final data = res.data;
    if (data is Map) {
      return MusicTask.fromJson(Map<String, dynamic>.from(data));
    }
    return MusicTask(id: '', kind: 'sing_original', status: 'error', reason: 'invalid response');
  }

  Future<MusicTask> singNewLyrics({
    required String heritageId,
    required String newLyrics,
    String vocal = 'Nữ',
    String tempo = 'Vừa',
    String mood = 'Trữ tình',
    String lora = '',
    double strength = 0.8,
    int duration = 60,
    int seed = 0,
  }) async {
    final res = await dio.post('/api/music/sing-new-lyrics', queryParameters: {
      'heritage_id': heritageId,
      'new_lyrics': newLyrics,
      'vocal': vocal,
      'tempo': tempo,
      'mood': mood,
      'lora': lora,
      'strength': strength,
      'duration': duration,
      'seed': seed,
    });
    final data = res.data;
    if (data is Map) {
      return MusicTask.fromJson(Map<String, dynamic>.from(data));
    }
    return MusicTask(id: '', kind: 'sing_new_lyrics', status: 'error', reason: 'invalid response');
  }

  Future<MusicTask> task(String id) async {
    final res = await dio.get('/api/music/task/$id');
    final data = res.data;
    if (data is Map) {
      return MusicTask.fromJson(Map<String, dynamic>.from(data));
    }
    return MusicTask(id: id, kind: '', status: 'unknown', reason: '');
  }
}
