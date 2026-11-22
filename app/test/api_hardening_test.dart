import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/api/endpoints/music_api.dart';

DioException _bad(int code) {
  return DioException(
    requestOptions: RequestOptions(path: '/api/x'),
    response: Response(
      requestOptions: RequestOptions(path: '/api/x'),
      statusCode: code,
      data: {'detail': 'admin truong only'},
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('403 được map thân thiện tiếng Việt thay vì generic', () {
    final msg = ApiClient.describe(_bad(403));
    expect(msg, 'Bạn không có quyền thực hiện hành động này.');
    expect(msg.contains('403'), isFalse, reason: 'không lộ mã thô');
  });

  test('parseSseBlock: gone + payload rỗng bị bỏ qua, task thường được parse', () {
    expect(MusicApi.parseSseBlock('event: gone\ndata: {}\n\n'), isNull);
    expect(MusicApi.parseSseBlock('data: {}\n\n'), isNull);
    final task = MusicApi.parseSseBlock('data: {"id":"t1","status":"running"}\n\n');
    expect(task, isNotNull);
    expect(task!.id, 't1');
    expect(task.status, 'running');
    final done = MusicApi.parseSseBlock(
      'event: update\ndata: {"id":"t1","status":"done","audio_url":"/a.wav"}\n\n',
    );
    expect(done!.status, 'done');
    expect(done.audioUrl, '/a.wav');
  });
}
