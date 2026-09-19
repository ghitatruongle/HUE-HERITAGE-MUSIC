import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/instrument_result.dart';

class InstrumentApi {
  final Dio dio;

  InstrumentApi(this.dio);

  Future<InstrumentResult> detectByItem(String itemId) async {
    final res = await dio.post('/api/music/instruments-item/$itemId');
    final data = res.data;
    if (data is Map) {
      return InstrumentResult.fromJson(Map<String, dynamic>.from(data));
    }
    return InstrumentResult(label: 'Chưa rõ', segments: []);
  }

  Future<InstrumentResult> detectBytes(Uint8List bytes, String filename) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await dio.post('/api/music/instruments', data: form);
    final data = res.data;
    if (data is Map) {
      return InstrumentResult.fromJson(Map<String, dynamic>.from(data));
    }
    return InstrumentResult(label: 'Chưa rõ', segments: []);
  }
}
