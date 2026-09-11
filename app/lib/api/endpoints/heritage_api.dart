import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/heritage_item.dart';

class HeritageApi {
  final Dio dio;

  HeritageApi(this.dio);

  Future<List<HeritageItem>> list({String q = ''}) async {
    final res = await dio.get('/api/heritage', queryParameters: {'q': q});
    final data = res.data as List;
    return data.map((e) => HeritageItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<HeritageItem> upload({
    required String filePath,
    required String title,
    String type = '',
    String artist = '',
  }) async {
    final name = filePath.split('/').last.split('\\').last;
    final form = FormData.fromMap({
      'title': title,
      'type': type,
      'artist': artist,
      'file': await MultipartFile.fromFile(filePath, filename: name),
    });
    final res = await dio.post('/api/heritage/upload', data: form);
    return HeritageItem.fromJson(res.data as Map<String, dynamic>);
  }

  String audioUrl(String id) {
    return '${dio.options.baseUrl}/api/heritage/$id/audio';
  }

  Future<Uint8List> audioBytes(String id) async {
    final res = await dio.get<List<int>>(
      audioUrl(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? <int>[]);
  }

  Future<String> downloadAudio(String id, String savePath) async {
    await dio.download(audioUrl(id), savePath);
    return savePath;
  }
}
