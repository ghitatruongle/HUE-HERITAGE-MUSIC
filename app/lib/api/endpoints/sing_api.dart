import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';

import '../../models/compare_result.dart';
import '../../models/pitch_data.dart';

class SingApi {
  final Dio dio;

  SingApi(this.dio);

  Future<PitchData> analyzePitch(
    String filePath, {
    void Function(int, int)? onProgress,
  }) async {
    final bytes = await XFile(filePath).readAsBytes();
    return analyzePitchBytes(bytes, onProgress: onProgress);
  }

  Future<PitchData> analyzePitchBytes(
    Uint8List bytes, {
    void Function(int, int)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: 'learn.wav'),
    });
    final res = await dio.post(
      '/api/music/analyze-pitch',
      data: form,
      onSendProgress: onProgress,
    );
    return PitchData.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CompareResult> compare(String samplePath, String userPath) async {
    final s = await XFile(samplePath).readAsBytes();
    final u = await XFile(userPath).readAsBytes();
    return compareBytes(s, u);
  }

  Future<CompareResult> compareBytes(Uint8List sampleBytes, Uint8List userBytes) async {
    final form = FormData.fromMap({
      'sample': MultipartFile.fromBytes(sampleBytes, filename: 'sample.wav'),
      'user': MultipartFile.fromBytes(userBytes, filename: 'user.wav'),
    });
    final res = await dio.post('/api/music/compare', data: form);
    return CompareResult.fromJson(res.data as Map<String, dynamic>);
  }
}
