import 'package:dio/dio.dart';
import '../core/constants/app_constants.dart';

class ApiClient {
  final Dio dio;

  ApiClient({String? baseUrl})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? AppConstants.defaultServerUrl,
          connectTimeout: AppConstants.apiTimeout,
          receiveTimeout: AppConstants.dspTimeout,
        ));

  Future<Response> health() => dio.get('/health');
}
