import 'package:dio/dio.dart';
import '../core/constants/app_constants.dart';

class ApiError {
  final String message;

  ApiError(this.message);
}

class ApiClient {
  final Dio dio;

  ApiClient({String? baseUrl})
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? '',
          connectTimeout: AppConstants.apiTimeout,
          receiveTimeout: AppConstants.dspTimeout,
        )) {
    dio.interceptors.add(_RetryInterceptor(dio));
  }

  static String describe(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Kết nối máy chủ quá chậm hoặc quá hạn.';
        case DioExceptionType.connectionError:
          return 'Không kết nối được máy chủ. Kiểm tra mạng hoặc địa chỉ máy chủ trong Cài đặt.';
        case DioExceptionType.badResponse:
          if (code == 401) return 'Cần đăng nhập hoặc token không hợp lệ.';
          if (code == 404) return 'Không tìm thấy dữ liệu trên máy chủ.';
          if (code == 413) return 'Tệp quá lớn.';
          final detail = error.response?.data;
          if (detail is Map && detail['detail'] != null) {
            return 'Máy chủ từ chối: ${detail['detail']}';
          }
          return 'Máy chủ trả lỗi $code.';
        default:
          return 'Lỗi không xác định khi gọi API.';
      }
    }
    return 'Lỗi không xác định: $error';
  }

  Future<Response> health() => dio.get('/health');
}

class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const int _maxAttempts = 3;

  _RetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryable = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);
    final attempt = (err.requestOptions.extra['__retry'] ?? 0) as int;
    if (retryable && attempt < _maxAttempts - 1) {
      err.requestOptions.extra['__retry'] = attempt + 1;
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      try {
        final response = await _dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}
