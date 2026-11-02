import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/heritage_item.dart';

class HeritagePage {
  final List<HeritageItem> items;
  final int total;

  HeritagePage({required this.items, required this.total});
}

class HeritageApi {
  final Dio dio;

  HeritageApi(this.dio);

  Future<HeritagePage> list({String q = '', int limit = 50, int offset = 0}) async {
    final res = await dio.get(
      '/api/heritage',
      queryParameters: {'q': q, 'limit': limit, 'offset': offset},
    );
    final data = res.data;
    if (data is! Map) return HeritagePage(items: [], total: 0);
    final rawItems = data['items'];
    final items = <HeritageItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(HeritageItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final total = data['total'];
    return HeritagePage(items: items, total: total is num ? total.toInt() : items.length);
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
