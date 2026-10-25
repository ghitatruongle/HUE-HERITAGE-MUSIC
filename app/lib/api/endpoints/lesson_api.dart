import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

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

  String scaleReferenceUrl(String scaleId) {
    return '${dio.options.baseUrl}/api/lessons/scales/$scaleId/reference.wav';
  }

  Future<ScalePractice> scalePracticeBytes(String scaleId, Uint8List bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: 'scale.wav'),
    });
    final res = await dio.post('/api/lessons/scales/$scaleId/practice', data: form);
    final data = res.data;
    if (data is Map) {
      return ScalePractice.fromJson(Map<String, dynamic>.from(data));
    }
    throw DioException(requestOptions: res.requestOptions, error: 'Invalid scale practice response');
  }
}
