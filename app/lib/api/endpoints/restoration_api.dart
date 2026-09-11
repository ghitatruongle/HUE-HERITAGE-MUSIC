import 'package:dio/dio.dart';

import '../../models/restore_result.dart';

class RestorationApi {
  final Dio dio;

  RestorationApi(this.dio);

  Future<RestoreResult> restoreItem(String itemId) async {
    final res = await dio.post('/api/music/restore-item/$itemId');
    return RestoreResult.fromJson(res.data as Map<String, dynamic>);
  }

  String restoredUrl(String sha) {
    return '${dio.options.baseUrl}/api/music/restored/$sha';
  }
}
