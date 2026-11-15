import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_heritage_music/api/api_client.dart';
import 'package:hue_heritage_music/models/lesson.dart';
import 'package:hue_heritage_music/services/recording_controller.dart';
import 'package:hue_heritage_music/services/teaching_utils.dart';
import 'package:record/record.dart';

void main() {
  test('PracticeNote err_cents null → errCents null, verdict giữ nguyên', () {
    final n = PracticeNote.fromServerJson({
      'start': 0.0,
      'end': 1.0,
      'err_cents': null,
      'verdict': 'Không rõ',
      'verdict_code': 'unclear',
      'hint': '',
      'hint_codes': ['note_not_in_ref'],
    });
    expect(n, isNotNull);
    expect(n!.errCents, isNull);
    expect(n.verdictCode, 'unclear');
    expect(n.octaveDiff, isFalse);
  });

  test('PracticeNote octave_diff true + err chuẩn hóa được parse', () {
    final n = PracticeNote.fromServerJson({
      'start': 0.0,
      'end': 1.0,
      'err_cents': 12.0,
      'octave_diff': true,
      'verdict': 'Chuẩn',
      'verdict_code': 'ok',
    });
    expect(n!.octaveDiff, isTrue);
    expect(n.errCents, 12.0);
  });

  test('PracticeWord parse đầy đủ từ server words[]', () {
    final w = PracticeWord.fromServerJson({
      'line': 1,
      'index': 2,
      'text': 'hoà',
      'start': 3.2,
      'end': 3.8,
      'voiced_ratio': 0.9,
      'err_cents': -25,
      'verdict_code': 'minor',
      'verdict': 'Lệch nhẹ',
    });
    expect(w!.line, 1);
    expect(w.text, 'hoà');
    expect(w.errCents, -25.0);
    final unclear = PracticeWord.fromServerJson({'line': 0, 'index': 0, 'text': 'x', 'start': 0.0, 'end': 0.1, 'voiced_ratio': 0.0, 'err_cents': null, 'verdict_code': 'unclear', 'verdict': 'Không rõ'});
    expect(unclear!.errCents, isNull);
  });

  test('PracticeResult parse words + wordsAlignment + truncated flag', () {
    final r = PracticeResult.fromJson({
      'metrics': {
        'score': 88.0,
        'truncated': true,
        'uploaded_seconds': 40.0,
        'analyzed_seconds': 35.0,
      },
      'sample': {'times': [0.0], 'f0': [220.0]},
      'user_warped': {'f0': [220.0]},
      'notes': [],
      'words': [
        {'line': 0, 'index': 0, 'text': 'Câu', 'start': 0.0, 'end': 0.5, 'voiced_ratio': 1.0, 'err_cents': 5, 'verdict_code': 'ok', 'verdict': 'Chuẩn'},
      ],
      'words_alignment': 'line_voiced_word_proportional',
      'section': {'index': 2},
    });
    expect(r.metrics.truncated, isTrue);
    expect(r.metrics.uploadedSeconds, 40.0);
    expect(r.metrics.analyzedSeconds, 35.0);
    expect(r.words.length, 1);
    expect(r.words.first.text, 'Câu');
    expect(r.wordsAlignment, 'line_voiced_word_proportional');
    expect(r.sectionIndex, 2);
  });

  test('serverWordScores map từ PracticeWord', () {
    final words = [
      PracticeWord.fromServerJson({'line': 0, 'index': 0, 'text': 'a', 'start': 0.0, 'end': 0.4, 'voiced_ratio': 1.0, 'err_cents': null, 'verdict_code': 'unclear', 'verdict': 'Không rõ'})!,
      PracticeWord.fromServerJson({'line': 0, 'index': 1, 'text': 'b', 'start': 0.4, 'end': 0.9, 'voiced_ratio': 1.0, 'err_cents': 8, 'verdict_code': 'ok', 'verdict': 'Chuẩn'})!,
    ];
    final ws = serverWordScores(words);
    expect(ws.length, 2);
    expect(ws[0].errCents, isNull);
    expect(ws[1].word, 'b');
    expect(ws[1].errCents, 8.0);
  });

  test('ScalePerformanceNote err_cents null được parse', () {
    final p = ScalePerformanceNote.fromJson({'name': 'Do', 'err_cents': null, 'onset_err_ms': 0, 'verdict': 'Không rõ', 'verdict_code': 'unclear', 'hint': ''});
    expect(p.errCents, isNull);
  });

  test('ApiClient.errorCode đọc mã lỗi cấu trúc từ 422', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/api/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/x'),
        statusCode: 422,
        data: {'detail': {'code': 'too_quiet', 'message': 'amp low'}},
      ),
    );
    expect(ApiClient.errorCode(err), 'too_quiet');
    expect(ApiClient.errorCode(Exception('other')), isNull);
  });

  test('RecordingController.anyBusy phản chiếu trạng thái bận', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final c = RecordingController(AudioRecorder());
    addTearDown(() => c.dispose());
    expect(RecordingController.anyBusy, isFalse);
    c.arming = true;
    expect(RecordingController.anyBusy, isTrue);
    c.arming = false;
    expect(RecordingController.anyBusy, isFalse);
  });

  test('describe: detail string đã map sang tiếng Việt thân thiện', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/api/heritage'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/api/heritage'),
        statusCode: 400,
        data: {'detail': 'unsupported type'},
      ),
    );
    final msg = ApiClient.describe(err);
    expect(msg, 'Định dạng tệp không được hỗ trợ.');
    expect(msg.contains('unsupported'), isFalse);
  });

  test('describe: detail string lạ → thông báo chung, không lộ mã thô', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/api/x'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/api/x'),
        statusCode: 400,
        data: {'detail': 'some raw internal error 12345'},
      ),
    );
    final msg = ApiClient.describe(err);
    expect(msg.contains('some raw internal error'), isFalse);
    expect(msg.contains('12345'), isFalse);
  });

  test('describe: structured detail (map) → thông báo chung, không dump JSON', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/api/x'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/api/x'),
        statusCode: 422,
        data: {'detail': {'code': 'weird_new_code', 'message': 'raw english message'}},
      ),
    );
    final msg = ApiClient.describe(err);
    expect(msg.contains('weird_new_code'), isFalse);
    expect(msg.contains('raw english message'), isFalse);
    expect(msg, contains('Máy chủ'));
  });
}
