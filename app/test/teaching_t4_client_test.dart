import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/services/teaching_utils.dart';

DioException _bad422(Map<String, dynamic> body) {
  return DioException(
    requestOptions: RequestOptions(path: '/api/lessons/1/practice'),
    response: Response(
      requestOptions: RequestOptions(path: '/api/lessons/1/practice'),
      statusCode: 422,
      data: body,
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('describe map mã 422 cấu trúc ra thông điệp thân thiện', () {
    expect(
      ApiClient.describe(_bad422({'detail': {'code': 'no_voice', 'message': 'x'}})),
      'Không nhận ra giọng hát — hãy hát to, gần mic và thu đủ dài hơn.',
    );
    expect(
      ApiClient.describe(_bad422({'detail': {'code': 'too_quiet', 'message': 'x'}})),
      'Âm thanh quá nhỏ — hãy hát to và gần mic hơn.',
    );
    expect(
      ApiClient.describe(_bad422({'detail': {'code': 'too_short', 'message': 'x'}})),
      'Bản thu quá ngắn — hãy thu trọn câu hát.',
    );
    expect(
      ApiClient.describe(_bad422({'detail': {'code': 'align_failed', 'message': 'x'}})),
      'Không đối chiếu được với bản mẫu — hãy thử thu lại.',
    );
    expect(
      ApiClient.describe(_bad422({'detail': {'code': 'reference_invalid', 'message': 'x'}})),
      'Bản mẫu không rõ giọng — hãy chọn câu khác hoặc nạp lại bài học.',
    );
    expect(
      ApiClient.describe(_bad422({'detail': {'code': 'unknown_code_x', 'message': 'x'}})),
      'Máy chủ từ chối yêu cầu. Thử lại sau ít phút.',
    );
  });

  test('streak ghim theo ngày server, không theo ngày máy client', () {
    final serverNow = DateTime(2026, 11, 21, 10, 0);
    final clientClock = DateTime(2026, 11, 19, 23, 0);
    final dates = [
      DateTime(2026, 11, 20, 9, 0),
      DateTime(2026, 11, 21, 8, 0),
      DateTime(2026, 11, 18, 8, 0),
    ];
    final anchored = practiceStatsFromDates(dates, serverNow);
    expect(anchored.streakDays, 2);

    final drifted = practiceStatsFromDates(dates, clientClock);
    expect(drifted.streakDays, 1);

    final last7 = practiceStatsFromDates(dates, serverNow).last7Counts;
    expect(last7[6], 1);
    expect(last7[5], 1);
  });
}
