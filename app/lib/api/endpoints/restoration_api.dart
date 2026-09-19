import 'package:dio/dio.dart';

import '../../models/restore_result.dart';

class RestorationApi {
  final Dio dio;

  RestorationApi(this.dio);

  Future<RestoreResult> restoreItem(String itemId) async {
    final res = await dio.post('/api/music/restore-item/$itemId');
    final data = res.data;
    if (data is Map) {
      return RestoreResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw DioException(requestOptions: res.requestOptions, error: 'Invalid response from server');
  }

  Future<RestoreResult> restoreUpload({required List<int> bytes, required String filename}) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await dio.post('/api/music/restore', data: formData);
    final data = res.data;
    if (data is Map) {
      return RestoreResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw DioException(requestOptions: res.requestOptions, error: 'Invalid response from server');
  }

  String restoredUrl(String sha) {
    return '${dio.options.baseUrl}/api/music/restored/$sha';
  }
}
