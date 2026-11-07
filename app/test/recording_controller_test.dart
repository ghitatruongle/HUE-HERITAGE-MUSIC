import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:hue_heritage_music/services/recording_controller.dart';

class FakeRecorder extends AudioRecorder {
  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  bool permission = true;
  bool failStart = false;
  bool failStop = false;
  bool failDispose = false;
  String? lastPath;
  final List<String> callOrder = [];

  @override
  Future<bool> hasPermission({bool request = true}) async => permission;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    if (failStart) throw StateError('start failed');
    startCount++;
    lastPath = path;
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    callOrder.add('stop');
    if (failStop) throw StateError('stop failed');
    return 'rec.wav';
  }

  @override
  Future<void> dispose() async {
    callOrder.add('dispose');
    if (failDispose) throw StateError('dispose failed');
    disposeCount++;
  }

  @override
  Future<Amplitude> getAmplitude() async {
    return Amplitude(current: -30.0, max: -30.0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), (call) async {
      if (call.method == 'create') {
        return 'mock-recorder';
      }
      return null;
    });
  });

  test('begin thành công: đặt mode + section + tăng epoch', () async {
    final fake = FakeRecorder();
    final c = RecordingController(fake);
    final e0 = c.epoch;
    final ok = await c.begin(mode: RecordingMode.section, path: 'a.wav', sectionIndex: 2);
    expect(ok, isTrue);
    expect(fake.startCount, 1);
    expect(fake.lastPath, 'a.wav');
    expect(c.isSectionRecording, isTrue);
    expect(c.activeSection, 2);
    expect(c.epoch, e0 + 1);
  });

  test('begin thiếu quyền hoặc start lỗi → false, không có trạng thái active', () async {
    final denied = RecordingController(FakeRecorder()..permission = false);
    expect(await denied.begin(mode: RecordingMode.scale, path: 's.wav'), isFalse);

    final failing = RecordingController(FakeRecorder()..failStart = true);
    expect(await failing.begin(mode: RecordingMode.section, path: 'a.wav'), isFalse);
    expect(failing.isSectionRecording, isFalse);
    expect(failing.activeSection, isNull);
  });

  test('begin tăng epoch đúng 1 lần — timer chụp epoch SAU begin phải khớp khi nổ', () async {
    final c = RecordingController(FakeRecorder());
    final before = c.epoch;
    await c.begin(mode: RecordingMode.section, path: 'a.wav', sectionIndex: 1);
    expect(c.epoch, before + 1);
    final epochForTimer = c.epoch;
    await c.stop();
    expect(c.epoch, epochForTimer + 1);
  });

  test('double-stop: recorder.stop chỉ chạy 1 lần, 2 luồng nhận chung kết quả', () async {
    final c = RecordingController(FakeRecorder());
    await c.begin(mode: RecordingMode.section, path: 'a.wav', sectionIndex: 1);
    final f1 = c.stop();
    final f2 = c.stop();
    expect(identical(f1, f2), isTrue);
    final r1 = await f1;
    final r2 = await f2;
    expect(r1.started, isTrue);
    expect(r1.path, 'rec.wav');
    expect(r1.sectionIndex, 1);
    expect(r2.path, 'rec.wav');
    expect(c.isSectionRecording, isFalse);
  });

  test('stop khi không thu → started=false, không chạm recorder.stop', () async {
    final fake = FakeRecorder();
    final c = RecordingController(fake);
    final r = await c.stop();
    expect(r.started, isFalse);
    expect(fake.stopCount, 0);
  });

  test('recorder.stop nổ giữa chừng → kết quả path=null, không văng exception', () async {
    final c = RecordingController(FakeRecorder()..failStop = true);
    await c.begin(mode: RecordingMode.section, path: 'a.wav', sectionIndex: 3);
    final r = await c.stop();
    expect(r.started, isTrue);
    expect(r.path, isNull);
    expect(c.isSectionRecording, isFalse);
    expect(c.stopping, isFalse);
  });

  test('stop khóa luồng kế tiếp cho tới khi dứt (mutex)', () async {
    final c = RecordingController(FakeRecorder());
    await c.begin(mode: RecordingMode.section, path: 'a.wav');
    final f = c.stop();
    expect(c.stopping, isTrue);
    await f;
    expect(c.stopping, isFalse);
  });

  test('stop + bắt đầu lại: epoch tăng mỗi lần chuyển trạng thái', () async {
    final c = RecordingController(FakeRecorder());
    final e0 = c.epoch;
    await c.begin(mode: RecordingMode.section, path: 'a.wav');
    final e1 = c.epoch;
    await c.stop();
    final e2 = c.epoch;
    await c.begin(mode: RecordingMode.scale, path: 's.wav');
    expect(e1, greaterThan(e0));
    expect(e2, greaterThan(e1));
    expect(c.isScaleRecording, isTrue);
    expect(c.activeSection, isNull);
  });

  test('dispose khi đang thu: stop trước rồi dispose, lỗi dispose không văng', () async {
    final fake = FakeRecorder()..failDispose = true;
    final c = RecordingController(fake);
    await c.begin(mode: RecordingMode.section, path: 'a.wav');
    await c.dispose();
    expect(fake.stopCount, 1);
    expect(fake.callOrder.first, 'stop');
    expect(c.isSectionRecording, isFalse);
  });
}
