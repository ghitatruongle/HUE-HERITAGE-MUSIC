import 'dart:async';

import 'package:dio/dio.dart';
import '../core/constants/app_constants.dart';
import '../services/auth_service.dart';

class ApiError {
  final String message;

  ApiError(this.message);
}

class ApiClient {
  final Dio dio;
  final String baseHost;

  static Options get dspOptions => Options(receiveTimeout: AppConstants.dspTimeout, sendTimeout: AppConstants.dspTimeout);

  ApiClient({String? baseUrl})
      : baseHost = _hostOf(baseUrl ?? ''),
        dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? '',
          connectTimeout: AppConstants.apiTimeout,
          receiveTimeout: AppConstants.apiTimeout,
          sendTimeout: AppConstants.uploadTimeout,
        )) {
    dio.interceptors.add(_AuthInterceptor(baseHost, dio));
    dio.interceptors.add(_RetryInterceptor(dio));
  }

  static String _hostOf(String url) {
    if (url.isEmpty) return '';
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic> requireMap(dynamic data, RequestOptions requestOptions) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw DioException(requestOptions: requestOptions, error: 'Invalid response from server');
  }

  static String? errorCode(Object error) {
    if (error is DioException) {
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] is Map) {
        final code = (detail['detail'] as Map)['code'];
        if (code != null) return code.toString();
      }
    }
    return null;
  }

  static const Map<String, String> _friendlyCodeDetails = {
    'no_voice': 'Không nhận ra giọng hát — hãy hát to, gần mic và thu đủ dài hơn.',
    'too_quiet': 'Âm thanh quá nhỏ — hãy hát to và gần mic hơn.',
    'too_short': 'Bản thu quá ngắn — hãy thu trọn câu hát.',
    'align_failed': 'Không đối chiếu được với bản mẫu — hãy thử thu lại.',
    'reference_invalid': 'Bản mẫu không rõ giọng — hãy chọn câu khác hoặc nạp lại bài học.',
  };

  static const Map<String, String> _friendlyDetails = {
    'wav decode failed': 'Tệp âm thanh không đọc được — hãy dùng tệp WAV chuẩn.',
    'empty pitch contour (silence or unvoiced audio)': 'Không nhận ra giọng hát — hãy hát to và gần mic hơn.',
    'empty contour': 'Không nhận được âm thanh để phân tích.',
    'empty file': 'Tệp rỗng — hãy chọn lại tệp.',
    'unsupported type': 'Định dạng tệp không được hỗ trợ.',
    'file content does not match its extension': 'Nội dung tệp không khớp phần mở rộng — hãy kiểm tra lại tệp.',
    'bad bpm': 'Nhịp BPM không hợp lệ.',
    'too many requests': 'Quá nhiều yêu cầu cùng lúc — chờ ít phút rồi thử lại.',
    'section not found': 'Không tìm thấy câu hát trong bài học — hãy nạp lại bài học.',
    'lesson not found': 'Không tìm thấy bài học — hãy nạp lại danh sách.',
    'password must be at least 8 characters and contain letters and digits':
        'Mật khẩu phải từ 8 ký tự trở lên và gồm cả chữ cái lẫn chữ số.',
    'admin password must be at least 12 characters and contain letters and digits':
        'Mật khẩu quản trị phải từ 12 ký tự trở lên và gồm cả chữ cái lẫn chữ số.',
    'username already exists': 'Tên tài khoản này đã có người sử dụng.',
    'email already registered': 'Địa chỉ email này đã được đăng ký.',
    'username or email already exists': 'Tên tài khoản hoặc email đã tồn tại.',
    'invalid invitation code': 'Mã mời không hợp lệ, đã hết lượt hoặc đã hết hạn.',
    'invalid email address': 'Địa chỉ email không hợp lệ.',
    'username must be 3-32 characters': 'Tên tài khoản phải dài từ 3 đến 32 ký tự.',
    'username may only contain letters, digits, dot, underscore, hyphen':
        'Tên tài khoản chỉ được chứa chữ, số, dấu chấm, gạch dưới và gạch ngang.',
    'username is reserved': 'Tên tài khoản này thuộc danh sách hệ thống, không thể đăng ký.',
    'username conflicts with the admin truong account': 'Tên tài khoản trùng với tài khoản quản trị trưởng.',
    'username impersonates the admin truong account': 'Tên tài khoản không được giả danh quản trị trưởng.',
    'wrong password': 'Mật khẩu không đúng.',
    'wrong credentials': 'Tên đăng nhập hoặc mật khẩu không đúng.',
    'account disabled': 'Tài khoản đã bị vô hiệu hóa — liên hệ quản trị viên.',
    'worker limit reached': 'Số lượng cộng tác viên đang hoạt động đã đạt giới hạn.',
    'max_uses must be 0 or 1-10000': 'Số lượt sử dụng phải bằng 0 (không giới hạn) hoặc từ 1 đến 10000.',
    'invalid invite expiration': 'Thời hạn mã mời không hợp lệ.',
    'cannot change admin truong role': 'Không thể thay đổi vai trò của quản trị trưởng.',
    'role must be user or worker': 'Vai trò chỉ có thể là người dùng hoặc cộng tác viên.',
    'password change required': 'Tài khoản đang dùng mật khẩu tạm — cần đổi mật khẩu trước khi thao tác.',
    'admin reauth required': 'Cần mở khóa lại quyền quản trị bằng mật khẩu trước khi thực hiện thao tác này.',
    'too many compare requests': 'Đang đối chiếu âm thanh khác — vui lòng chờ giây lát.',
  };

  static String describe(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Kết nối máy chủ quá chậm hoặc quá hạn.';
        case DioExceptionType.connectionError:
          return 'Không kết nối được máy chủ AI. Kiểm tra kết nối mạng của bạn.';
        case DioExceptionType.badResponse:
          final detail = error.response?.data;
          if (code == 401) {
            if (detail is Map && detail['detail'] is String) {
              final raw401 = (detail['detail'] as String).trim();
              if (raw401 == 'wrong password' || raw401 == 'wrong credentials') {
                return _friendlyDetails[raw401]!;
              }
            }
            return 'Cần đăng nhập hoặc token không hợp lệ.';
          }
          if (detail is Map && detail['detail'] is String) {
            final raw = (detail['detail'] as String).trim();
            final friendly = _friendlyDetails[raw];
            if (friendly != null) return friendly;
          }
          if (code == 403) return 'Bạn không có quyền thực hiện hành động này.';
          if (code == 404) return 'Không tìm thấy dữ liệu trên máy chủ.';
          if (code == 413) return 'Tệp quá lớn.';
          if (detail is Map && detail['detail'] is Map) {
            final inner = detail['detail'] as Map;
            final codeKey = inner['code']?.toString();
            final friendlyCode = codeKey != null ? _friendlyCodeDetails[codeKey] : null;
            if (friendlyCode != null) return friendlyCode;
            final message = inner['message']?.toString();
            if (message != null && message.isNotEmpty && message != codeKey) {
              return 'Máy chủ từ chối yêu cầu. Thử lại sau ít phút.';
            }
            return 'Máy chủ từ chối yêu cầu. Thử lại sau ít phút.';
          }
          if (detail is Map && detail['detail'] is String) {
            return 'Máy chủ từ chối yêu cầu. Thử lại sau ít phút.';
          }
          return 'Máy chủ trả lỗi $code.';
        default:
          return 'Lỗi không xác định khi gọi API.';
      }
    }
    if (error is TimeoutException) {
      return 'Kết nối máy chủ quá chậm hoặc quá hạn.';
    }
    if (error is FormatException) {
      return 'Dữ liệu phản hồi không đúng định dạng.';
    }
    return 'Lỗi không xác định khi gọi API.';
  }
}

class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const int _maxAttempts = 3;

  _RetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final method = err.requestOptions.method.toUpperCase();
    final idempotent = method == 'GET' || method == 'HEAD';
    final retryable = idempotent &&
        (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.receiveTimeout ||
            (err.response?.statusCode != null && err.response!.statusCode! >= 500));
    final attempt = (err.requestOptions.extra['__retry'] ?? 0) as int;
    if (retryable && attempt < _maxAttempts - 1) {
      err.requestOptions.extra['__retry'] = attempt + 1;
      err.requestOptions.headers.remove('Authorization');
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      try {
        final response = await _dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (e) {
        if (e is DioException) {
          return handler.next(e);
        }
        return handler.next(DioException(requestOptions: err.requestOptions, error: e));
      }
    }
    handler.next(err);
  }
}

class _AuthInterceptor extends Interceptor {
  final String _baseHost;
  final Dio _dio;
  bool _healing = false;

  _AuthInterceptor(this._baseHost, this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = AuthService.currentToken;
    if (token != null && token.isNotEmpty && !options.headers.containsKey('Authorization')) {
      final host = options.uri.host;
      if (_baseHost.isEmpty || host.isEmpty || host == _baseHost) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final path = err.requestOptions.uri.path;
    final isAuthAttempt = path.contains('/auth/');
    if (err.response?.statusCode == 401 && !isAuthAttempt) {
      final host = err.requestOptions.uri.host;
      if (_baseHost.isNotEmpty && host == _baseHost) {
        _healThenClear(err.requestOptions);
      }
    }
    handler.next(err);
  }

  void _healThenClear(RequestOptions requestOptions) async {
    final auth = AuthService.instance;
    if (auth == null || _healing) {
      return;
    }
    _healing = true;
    try {
      final client = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      client.options.validateStatus = (code) => code != null && code < 500;
      client.httpClientAdapter = _dio.httpClientAdapter;
      final token = AuthService.currentToken ?? '';
      final res = await client.get(
        '${requestOptions.uri.origin}/api/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if ((res.statusCode == 401 || res.statusCode == 403) && AuthService.currentToken == token) {
        await auth.clearToken(expired: true);
      }
    } catch (_) {
    } finally {
      _healing = false;
    }
  }
}
