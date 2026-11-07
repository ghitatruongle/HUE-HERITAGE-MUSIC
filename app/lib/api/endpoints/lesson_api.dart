import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../api/api_client.dart';

import '../../models/lesson.dart';

class LessonApi {
  final Dio dio;

  LessonApi(this.dio);

  Future<List<Lesson>> list() async {
    final res = await dio.get('/api/lessons');
    final raw = res.data;
    final lessons = <Lesson>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          lessons.add(Lesson.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return lessons;
  }

  Future<LessonDetail> detail(String id) async {
    final res = await dio.get('/api/lessons/$id');
    final data = res.data;
    if (data is Map) {
      return LessonDetail.fromJson(Map<String, dynamic>.from(data));
    }
    throw DioException(requestOptions: res.requestOptions, error: 'Invalid lesson response');
  }

  Future<PracticeResult> practiceBytes(String lessonId, int section, Uint8List bytes, {void Function(int, int)? onProgress}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: 'practice.wav'),
    });
    final res = await dio.post(
      '/api/lessons/$lessonId/practice',
      queryParameters: {'section': section},
      data: form,
      options: ApiClient.dspOptions,
      onSendProgress: onProgress,
    );
    final data = res.data;
    if (data is Map) {
      return PracticeResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw DioException(requestOptions: res.requestOptions, error: 'Invalid practice response');
  }

  Future<PracticeResult> practiceFile(String lessonId, int section, String path, {void Function(int, int)? onProgress}) async {
    return practiceBytes(lessonId, section, await File(path).readAsBytes(), onProgress: onProgress);
  }

  Future<List<ScaleInfo>> scales() async {
    final res = await dio.get('/api/lessons/scales');
    final raw = res.data;
    final scales = <ScaleInfo>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          scales.add(ScaleInfo.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return scales;
  }

  String scaleReferenceUrl(String scaleId, {int transpose = 0}) {
    final base = '${dio.options.baseUrl}/api/lessons/scales/$scaleId/reference.wav';
    if (transpose == 0) return base;
    return '$base?transpose=$transpose';
  }

  Future<ScalePractice> scalePracticeBytes(String scaleId, Uint8List bytes, {int transpose = 0}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: 'scale.wav'),
    });
    final res = await dio.post(
      '/api/lessons/scales/$scaleId/practice',
      queryParameters: {'transpose': transpose},
      data: form,
      options: ApiClient.dspOptions,
    );
    final data = res.data;
    if (data is Map) {
      return ScalePractice.fromJson(Map<String, dynamic>.from(data));
    }
    throw DioException(requestOptions: res.requestOptions, error: 'Invalid scale practice response');
  }

  Future<LessonDetail> uploadSample(String lessonId, int section, Uint8List bytes, String filename) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    await dio.post('/api/lessons/$lessonId/sections/$section/sample.wav', data: form, options: ApiClient.dspOptions);
    return detail(lessonId);
  }

  Future<LessonDetail> deleteSample(String lessonId, int section) async {
    await dio.delete('/api/lessons/$lessonId/sections/$section/sample.wav');
    return detail(lessonId);
  }

  String sampleUrl(String lessonId, int section) {
    return '${dio.options.baseUrl}/api/lessons/$lessonId/sections/$section/sample.wav';
  }

  Future<List<ProgressEntry>> myProgress({String lessonId = '', int limit = 100}) async {
    final res = await dio.get(
      '/api/lessons/my-progress',
      queryParameters: {'lesson_id': lessonId, 'limit': limit},
    );
    final data = res.data;
    final items = <ProgressEntry>[];
    if (data is Map && data['items'] is List) {
      for (final e in data['items'] as List) {
        if (e is Map) {
          items.add(ProgressEntry.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return items;
  }
}
