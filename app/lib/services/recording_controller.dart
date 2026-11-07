import 'dart:async';

import 'package:record/record.dart';

enum RecordingMode { section, scale }

class RecordingStopResult {
  final RecordingMode mode;
  final int sectionIndex;
  final String? path;
  final bool started;

  const RecordingStopResult({
    required this.mode,
    required this.sectionIndex,
    required this.path,
    required this.started,
  });
}

class RecordingController {
  RecordingController(this._recorder);

  final AudioRecorder _recorder;
  int epoch = 0;
  bool arming = false;
  RecordingMode? _active;
  int _activeSection = -1;
  Future<RecordingStopResult>? _stopLock;

  bool get isSectionRecording => _active == RecordingMode.section;
  bool get isScaleRecording => _active == RecordingMode.scale;
  int? get activeSection => isSectionRecording ? _activeSection : null;
  bool get stopping => _stopLock != null;

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<double> currentAmplitude() async {
    try {
      return (await _recorder.getAmplitude()).current;
    } catch (_) {
      return -60;
    }
  }

  Future<bool> begin({
    required RecordingMode mode,
    required String path,
    int sectionIndex = -1,
  }) async {
    if (!(await hasPermission())) {
      return false;
    }
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
        path: path,
      );
    } catch (_) {
      return false;
    }
    epoch++;
    _active = mode;
    _activeSection = sectionIndex;
    return true;
  }

  Future<RecordingStopResult> stop() {
    final existing = _stopLock;
    if (existing != null) {
      return existing;
    }
    final done = Completer<RecordingStopResult>();
    _stopLock = done.future;
    epoch++;
    arming = false;
    final mode = _active ?? RecordingMode.section;
    final section = _activeSection;
    final wasActive = _active != null;
    _active = null;
    _activeSection = -1;
    unawaited(Future<void>(() async {
      String? p;
      if (wasActive) {
        try {
          p = await _recorder.stop();
        } catch (_) {
          p = null;
        }
      }
      _stopLock = null;
      done.complete(RecordingStopResult(
        mode: mode,
        sectionIndex: section,
        path: p,
        started: wasActive,
      ));
    }));
    return done.future;
  }

  Future<void> dispose() async {
    if (_active != null) {
      try {
        await _recorder.stop();
      } catch (_) {}
      _active = null;
    }
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
