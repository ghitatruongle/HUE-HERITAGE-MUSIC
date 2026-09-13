import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/instrument_result.dart';

class InstrumentApi {
  final Dio dio;

  InstrumentApi(this.dio);

  Future<InstrumentResult> detectByItem(String itemId) async {
    final res = await dio.post('/api/music/instruments-item/$itemId');
    return InstrumentResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<InstrumentResult> detectBytes(Uint8List bytes, String filename) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await dio.post('/api/music/instruments', data: form);
    return InstrumentResult.fromJson(res.data as Map<String, dynamic>);
  }
}
