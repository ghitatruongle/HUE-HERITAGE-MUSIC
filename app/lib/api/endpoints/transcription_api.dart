import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';

import '../../models/transcribe_result.dart';

class TranscriptionApi {
  final Dio dio;

  TranscriptionApi(this.dio);

  Future<TranscribeResult> transcribe(
    String filePath, {
    double bpm = 60,
    String engine = 'basic_pitch',
    void Function(int, int)? onProgress,
  }) async {
    final bytes = await XFile(filePath).readAsBytes();
    return transcribeBytes(bytes, bpm: bpm, engine: engine, onProgress: onProgress);
  }

  Future<TranscribeResult> transcribeBytes(
    Uint8List bytes, {
    double bpm = 60,
    String engine = 'basic_pitch',
    void Function(int, int)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'bpm': bpm.toString(),
      'engine': engine,
      'file': MultipartFile.fromBytes(bytes, filename: 'transcribe.wav'),
    });
    final res = await dio.post(
      '/api/music/transcribe',
      data: form,
      onSendProgress: onProgress,
    );
    return TranscribeResult.fromJson(res.data as Map<String, dynamic>);
  }

  String midiUrl(String sha, {double bpm = 60}) {
    return '${dio.options.baseUrl}/api/music/midi/$sha?bpm=${bpm.round()}';
  }

  String xmlUrl(String sha, {double bpm = 60}) {
    return '${dio.options.baseUrl}/api/music/musicxml/$sha?bpm=${bpm.round()}';
  }

  Future<String> download(String url, String savePath) async {
    await dio.download(url, savePath);
    return savePath;
  }
}
