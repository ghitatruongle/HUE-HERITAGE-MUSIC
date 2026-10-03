import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/heritage_item.dart';

class HeritageApi {
  final Dio dio;

  HeritageApi(this.dio);

  Future<List<HeritageItem>> list({String q = ''}) async {
    final res = await dio.get('/api/heritage', queryParameters: {'q': q});
    final data = res.data;
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => HeritageItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
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
}
