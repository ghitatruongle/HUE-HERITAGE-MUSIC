import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/lesson_api.dart';
import '../../models/lesson.dart';
import 'scale_practice_card.dart';
import '../../services/app_lifecycle_service.dart';
import '../../services/download_helper.dart';
import '../../services/file_saver.dart';
import '../../services/local_pitch.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../services/history_service.dart';
import '../../services/recording_controller.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';
import '../../widgets/chart_palette.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/overlay_pitch_chart.dart';
import '../../widgets/skeleton_loader.dart';

class LessonPracticeView extends StatefulWidget {
  const LessonPracticeView({super.key});

  @override
  State<LessonPracticeView> createState() => _LessonPracticeViewState();
}

class _TakeRec {
  final Uint8List bytes;
  final int no;
  const _TakeRec(this.bytes, this.no);
}

class _LessonPracticeViewState extends State<LessonPracticeView> {
  final RecordingController _rec = RecordingController(AudioRecorder());
  final AudioPlayer _samplePlayer = AudioPlayer();
  final AudioPlayer _metronomePlayer = AudioPlayer();
  Future<void> _metroChain = Future.value();
  String? _lastTempBeepPath;
  late AppLifecycleHooks _lifecycleHooks;
  List<Lesson> _lessons = [];
  Lesson? _selected;
  LessonDetail? _detail;
  bool _loadingLessons = false;
  bool _loadingDetail = false;
  String? _error;
  bool _countIn = true;
  late AppStrings strings;

  final Map<int, String> _recordPaths = {};
  int? _practicingSection;
  final Map<int, PracticeResult> _results = {};
  final Map<int, bool> _looping = {};
  final Map<int, List<_TakeRec>> _takes = {};
  final Map<int, int> _selectedTake = {};
  Future<void>? _stopUiLock;

  double _speed = 1.0;
  int _playGen = 0;
  String? _signedRefUrl;
  final Map<int, String> _signedSampleUrls = {};
  final Map<int, bool> _playingSample = {};

  Timer? _vuTimer;
  Timer? _autoStopTimer;
  Timer? _scaleAutoStop;
  final ValueNotifier<double> _vuLevel = ValueNotifier<double>(-60);
  final ValueNotifier<double> _recElapsed = ValueNotifier<double>(0);
  final ValueNotifier<double?> _uploadProgress = ValueNotifier<double?>(null);
  DateTime? _recStartAt;
  bool _autoGrade = false;
  bool _heardVoice = false;
  DateTime? _lastVoiceAt;
  int _takeCounter = 0;
  LocalPitchResult? _takePreview;

  List<ProgressEntry> _serverProgress = [];
  bool _serverProgressAvailable = false;

  List<ScaleInfo> _scales = [];
  ScaleInfo? _selectedScale;
  String? _scalePath;
  bool _scaleBusy = false;
  ScalePractice? _scaleResult;
  int _scaleTranspose = 0;
  StreamSubscription? _sampleSub;

  @override
  void initState() {
    super.initState();
    _loadLessons();
    _sampleSub = _samplePlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() => _looping.clear());
      }
    });
    _lifecycleHooks = AppLifecycleHooks(
      onPause: () {
        unawaited(_stopEverything());
      },
    );
    AppLifecycleService.instance.register(_lifecycleHooks);
  }

  @override
  void dispose() {
    AppLifecycleService.instance.unregister(_lifecycleHooks);
    _vuTimer?.cancel();
    _autoStopTimer?.cancel();
    _scaleAutoStop?.cancel();
    _sampleSub?.cancel();
    _vuLevel.dispose();
    _recElapsed.dispose();
    _uploadProgress.dispose();
    _rec.dispose();
    if (!kIsWeb) {
      for (final p in _recordPaths.values) {
        unawaited(Future(() async {
          try {
            await File(p).delete();
          } catch (_) {}
        }));
      }
    }
    final staleBeep = _lastTempBeepPath;
    final metroDrain = _metroChain.catchError((_) {});
    _metroChain = Future.value();
    metroDrain.whenComplete(() {
      try {
        _metronomePlayer.dispose();
      } catch (_) {}
      if (staleBeep != null) {
        () async {
          try {
            final f = File(staleBeep);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (_) {}
        }();
      }
    });
    _samplePlayer.dispose();
    super.dispose();
  }

  Future<AudioSource> _bytesSource(Uint8List bytes) async {
    if (kIsWeb) {
      return AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav'));
    }
    final file = File('${Directory.systemTemp.path}/hue_beep_${identityHashCode(this)}_${DateTime.now().millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(bytes);
    final previous = _lastTempBeepPath;
    _lastTempBeepPath = file.path;
    if (previous != null && previous != file.path) {
      try {
        final prevFile = File(previous);
        if (await prevFile.exists()) {
          await prevFile.delete();
        }
      } catch (_) {}
    }
    return AudioSource.uri(Uri.file(file.path));
  }

  Future<void> _loadLessons() async {
    setState(() {
      _loadingLessons = true;
      _error = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = LessonApi(dio);
      final lessons = await api.list();
      final scales = await api.scales();
      if (!mounted) return;
      setState(() {
        _lessons = lessons;
        _scales = scales;
        _selectedScale = scales.isNotEmpty ? scales.first : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _loadingLessons = false);
    }
  }

  Future<void> _stopEverything() async {
    _playGen++;
    await _stopActiveRecording();
    if (!mounted) return;
    try {
      await _metronomePlayer.stop();
    } catch (_) {}
    try {
      await _samplePlayer.stop();
    } catch (_) {}
    if (!mounted) return;
    _vuLevel.value = -60;
    _recStartAt = null;
    _recElapsed.value = 0;
    _looping.clear();
    _playingSample.clear();
    if (mounted) setState(() {});
  }

  Future<void> _stopActiveRecording() {
    final existing = _stopUiLock;
    if (existing != null) {
      return existing;
    }
    final done = Completer<void>();
    _stopUiLock = done.future;
    _vuTimer?.cancel();
    _autoStopTimer?.cancel();
    _scaleAutoStop?.cancel();
    _rec.stop().then((result) async {
      try {
        String? p = result.path;
        Uint8List? takeBytes;
        LocalPitchResult? preview;
        if (result.started && result.mode == RecordingMode.section && p != null) {
          if (kIsWeb) {
            try {
              takeBytes = await XFile(p).readAsBytes();
            } catch (_) {}
          } else {
            try {
              takeBytes = await File(p).readAsBytes();
            } catch (_) {}
          }
          if (takeBytes != null && !kIsWeb) {
            try {
              preview = await compute(LocalPitch.analyze, takeBytes);
            } catch (_) {}
          }
        }
        if (!mounted) {
          return;
        }
        setState(() {
        _vuLevel.value = -60;
        _recStartAt = null;
        _recElapsed.value = 0;
        if (result.started && result.mode == RecordingMode.section) {
          if (p != null) {
            final stale = _recordPaths[result.sectionIndex];
            _recordPaths[result.sectionIndex] = p;
            if (stale != null && stale != p && takeBytes != null && !kIsWeb) {
              unawaited(Future(() async {
                try {
                  await File(stale).delete();
                } catch (_) {}
              }));
            }
          }
          if (takeBytes != null) {
            final takes = _takes[result.sectionIndex] ?? <_TakeRec>[];
            _takeCounter++;
            takes.add(_TakeRec(takeBytes, _takeCounter));
            while (takes.length > 3) {
              takes.removeAt(0);
            }
            _takes[result.sectionIndex] = takes;
            _selectedTake[result.sectionIndex] = takes.length - 1;
          }
          _takePreview = preview;
        }
        if (result.started && result.mode == RecordingMode.scale) {
          _scalePath = p;
          _scaleResult = null;
        }
      });
        if (_autoGrade &&
            result.started &&
            result.mode == RecordingMode.section &&
            takeBytes != null &&
            takeBytes.length >= 16000 * 2 * 2 &&
            _selected != null &&
            _detail != null) {
          LessonSection? target;
          for (final s in _detail!.sections) {
            if (s.index == result.sectionIndex) target = s;
          }
          if (target != null) {
            unawaited(_submitPractice(target));
          }
        }
      } finally {
        _stopUiLock = null;
        done.complete();
      }
    });
    return done.future;
  }

  Future<void> _openLesson(Lesson lesson) async {
    await _stopEverything();
    if (!mounted) return;
    setState(() {
      _selected = lesson;
      _loadingDetail = true;
      _error = null;
      _detail = null;
      _results.clear();
      _recordPaths.clear();
      _takes.clear();
      _selectedTake.clear();
      _signedSampleUrls.clear();
      _signedRefUrl = null;
      _takePreview = null;
      _serverProgress = [];
      _takeCounter = 0;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = LessonApi(dio);
      final detail = await api.detail(lesson.id);
      if (!mounted || _selected?.id != lesson.id) return;
      final sampleTargets = detail.sections.where((s) => s.hasSample && s.sampleUrl.isNotEmpty).toList();
      final signedList = await Future.wait<String?>([
        _signPath(dio, '/api/heritage/${lesson.id}/audio'),
        for (final s in sampleTargets) _signPath(dio, s.sampleUrl),
      ]);
      if (!mounted || _selected?.id != lesson.id) return;
      _signedRefUrl = signedList[0];
      for (var i = 0; i < sampleTargets.length; i++) {
        final signed = signedList[i + 1];
        if (signed != null) _signedSampleUrls[sampleTargets[i].index] = signed;
      }
      List<ProgressEntry> progress = [];
      bool serverOk = false;
      try {
        progress = await api.myProgress(lessonId: lesson.id);
        serverOk = true;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _serverProgress = progress;
        _serverProgressAvailable = serverOk;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<String?> _signPath(Dio dio, String path) async {
    try {
      final res = await dio.get('/api/music/play-url', queryParameters: {'path': path});
      final data = res.data;
      if (data is Map && data['url'] is String) {
        final signed = data['url'] as String;
        return signed.startsWith('http') ? signed : '${dio.options.baseUrl}$signed';
      }
    } catch (_) {}
    return null;
  }

  Future<void> _playSegment(String url, {Duration? clipStart, Duration? clipEnd, required bool loop, int? gen}) async {
    await _samplePlayer.stop();
    if (gen != null && gen != _playGen) return;
    await _samplePlayer.setUrl(url);
    if (gen != null && gen != _playGen) return;
    if (clipStart != null && clipEnd != null) {
      await _samplePlayer.setClip(start: clipStart, end: clipEnd);
    }
    if (gen != null && gen != _playGen) return;
    await _samplePlayer.setLoopMode(loop ? LoopMode.one : LoopMode.off);
    await _samplePlayer.setSpeed(_speed);
    if (gen != null && gen != _playGen) return;
    await _samplePlayer.play();
  }

  Future<void> _toggleSample(LessonSection section) async {
    final detail = _detail;
    if (detail == null) return;
    final gen = ++_playGen;
    final dio = context.read<ServerConfig>().api.dio;
    final basePath = '/api/heritage/${detail.id}/audio';
    final looping = _looping[section.index] ?? false;
    try {
      if (looping) {
        await _samplePlayer.stop();
        if (gen != _playGen || !mounted) return;
        setState(() => _looping.remove(section.index));
        return;
      }
      var url = _signedRefUrl ?? (await _signPath(dio, basePath));
      if (gen != _playGen) return;
      url ??= '${dio.options.baseUrl}$basePath';
      final clipStart = Duration(milliseconds: (section.start * 1000).round());
      final clipEnd = Duration(milliseconds: (section.end * 1000).round());
      try {
        await _playSegment(url, clipStart: clipStart, clipEnd: clipEnd, loop: true, gen: gen);
      } catch (_) {
        if (gen != _playGen) return;
        final resigned = await _signPath(dio, basePath);
        if (gen != _playGen) return;
        if (resigned == null || resigned == url) rethrow;
        _signedRefUrl = resigned;
        await _playSegment(resigned, clipStart: clipStart, clipEnd: clipEnd, loop: true, gen: gen);
      }
      if (gen != _playGen || !mounted) return;
      setState(() {
        _looping.clear();
        _playingSample.clear();
        _looping[section.index] = true;
      });
    } catch (e) {
      if (gen != _playGen || !mounted) return;
      setState(() => _error = ApiClient.describe(e));
    }
  }

  Future<void> _toggleMasterSample(LessonSection section) async {
    final playing = _playingSample[section.index] ?? false;
    final gen = ++_playGen;
    try {
      if (playing) {
        await _samplePlayer.stop();
        if (gen != _playGen || !mounted) return;
        setState(() => _playingSample.remove(section.index));
        return;
      }
      final dio = context.read<ServerConfig>().api.dio;
      var url = _signedSampleUrls[section.index];
      if (url == null || url.isEmpty) {
        url = await _signPath(dio, section.sampleUrl);
      }
      if (gen != _playGen) return;
      if (url == null || url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.practiceSampleUnavailable), duration: const Duration(seconds: 4)),
          );
        }
        return;
      }
      try {
        await _playSegment(url, loop: true, gen: gen);
      } catch (_) {
        if (gen != _playGen) return;
        final resigned = await _signPath(dio, section.sampleUrl);
        if (gen != _playGen) return;
        if (resigned == null || resigned == url) rethrow;
        _signedSampleUrls[section.index] = resigned;
        await _playSegment(resigned, loop: true, gen: gen);
      }
      if (gen != _playGen || !mounted) return;
      setState(() {
        _looping.clear();
        _playingSample.clear();
        _playingSample[section.index] = true;
      });
    } catch (e) {
      if (gen != _playGen || !mounted) return;
      setState(() => _error = ApiClient.describe(e));
    }
  }

  Future<void> _playRefSegment(double start, double end, LessonSection section) async {
    final detail = _detail;
    if (detail == null || end <= start) return;
    final gen = ++_playGen;
    final dio = context.read<ServerConfig>().api.dio;
    final basePath = '/api/heritage/${detail.id}/audio';
    try {
      var useSample = section.hasSample && section.sampleUrl.isNotEmpty;
      var url = useSample
          ? (_signedSampleUrls[section.index] ?? (await _signPath(dio, section.sampleUrl)))
          : null;
      if (gen != _playGen) return;
      if (url == null) {
        useSample = false;
        url = _signedRefUrl ?? (await _signPath(dio, basePath));
        if (gen != _playGen) return;
        url ??= '${dio.options.baseUrl}$basePath';
      }
      final base = useSample ? 0.0 : section.start;
      final clipStart = Duration(milliseconds: (math.max(0, base + start - 0.25) * 1000).round());
      final clipEnd = Duration(milliseconds: ((base + end) * 1000).round());
      try {
        await _playSegment(url, clipStart: clipStart, clipEnd: clipEnd, loop: false, gen: gen);
      } catch (_) {
        if (gen != _playGen) return;
        final path = useSample ? section.sampleUrl : basePath;
        final resigned = await _signPath(dio, path);
        if (gen != _playGen) return;
        if (resigned == null || resigned == url) rethrow;
        if (useSample) {
          _signedSampleUrls[section.index] = resigned;
        } else {
          _signedRefUrl = resigned;
        }
        await _playSegment(resigned, clipStart: clipStart, clipEnd: clipEnd, loop: false, gen: gen);
      }
      if (gen != _playGen || !mounted) return;
      setState(() {
        _looping.clear();
        _playingSample.clear();
      });
    } catch (e) {
      if (gen != _playGen || !mounted) return;
      setState(() => _error = ApiClient.describe(e));
    }
  }

  Future<void> _setSpeed(double v) async {
    setState(() => _speed = v);
    try {
      await _samplePlayer.setSpeed(v);
    } catch (_) {}
  }

  String _practicePath(int sectionIndex) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return kIsWeb ? 'hue_practice_$sectionIndex.wav' : '${Directory.systemTemp.path}/hue_practice_${sectionIndex}_$stamp.wav';
  }

  Uint8List _metronomeWav(int bpm, {int beats = 4}) {
    const sr = 22050;
    final beatLen = (sr * 60 / (bpm > 0 ? bpm : 60)).round();
    final total = beatLen * beats;
    final data = Int16List(total);
    final tickLen = (sr * 0.07).round();
    for (var b = 0; b < beats; b++) {
      final start = b * beatLen;
      final amp = b == 0 ? 12000 : 9000;
      for (var i = 0; i < tickLen && start + i < total; i++) {
        final env = (1.0 - i / tickLen);
        data[start + i] = (amp * env * math.sin(2 * math.pi * (b == 0 ? 1320.0 : 880.0) * i / sr)).toInt();
      }
    }
    final header = ByteData(44);
    header.setUint32(0, 0x46464952, Endian.little);
    header.setUint32(4, 36 + total * 2, Endian.little);
    header.setUint32(8, 0x45564157, Endian.little);
    header.setUint32(12, 0x20746D66, Endian.little);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sr, Endian.little);
    header.setUint32(28, sr * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(36, 0x61746164, Endian.little);
    header.setUint32(40, total * 2, Endian.little);
    final out = BytesBuilder();
    out.add(header.buffer.asUint8List());
    out.add(data.buffer.asUint8List(0, total * 2));
    return out.toBytes();
  }

  void _startVuPolling() {
    _vuTimer?.cancel();
    _heardVoice = false;
    _lastVoiceAt = null;
    if (kIsWeb) {
      final webEpoch = _rec.epoch;
      _vuTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || webEpoch != _rec.epoch) return;
        if (_recStartAt != null) {
          _recElapsed.value = DateTime.now().difference(_recStartAt!).inMilliseconds / 1000.0;
        }
      });
      return;
    }
    final epoch = _rec.epoch;
    _vuTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      try {
        final amp = await _rec.currentAmplitude();
        if (!mounted || epoch != _rec.epoch) return;
        _vuLevel.value = amp;
        if (_recStartAt != null) {
          _recElapsed.value = DateTime.now().difference(_recStartAt!).inMilliseconds / 1000.0;
        }
        if (_vuLevel.value > -35) {
          _heardVoice = true;
          _lastVoiceAt = DateTime.now();
        } else if (_heardVoice && _lastVoiceAt != null) {
          final quietFor = DateTime.now().difference(_lastVoiceAt!).inMilliseconds;
          if (quietFor > 1200 && mounted && _rec.isSectionRecording && epoch == _rec.epoch) {
            _vuTimer?.cancel();
            _stopActiveRecording();
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _toggleRecord(LessonSection section) async {
    if (_rec.isSectionRecording && _rec.activeSection == section.index) {
      await _stopActiveRecording();
      return;
    }
    if (_rec.isSectionRecording) {
      await _stopActiveRecording();
      if (!mounted) return;
    }
    if (_rec.isScaleRecording) {
      setState(() => _error = strings.practiceBusyScale);
      return;
    }
    if (_rec.arming || _rec.stopping || _stopUiLock != null) return;
    _rec.arming = true;
    final lessonAtStart = _selected?.id;
    if (!await _rec.hasPermission()) {
      _rec.arming = false;
      if (!mounted) return;
      setState(() => _error = strings.practiceMicDenied);
      return;
    }
    if (!mounted || _selected?.id != lessonAtStart) {
      _rec.arming = false;
      return;
    }
    final epochAtStart = _rec.epoch;
    if (_countIn) {
      try {
        final bpmVal = (_detail?.bpm ?? 60).round();
        final chain = _metroChain.then((_) async {
          try {
            await _metronomePlayer.stop();
            await _metronomePlayer.setAudioSource(await _bytesSource(_metronomeWav(bpmVal)));
          } catch (_) {}
        });
        _metroChain = chain;
        await chain;
        final done = Completer<void>();
        final sub = _metronomePlayer.playerStateStream.listen((st) {
          if (st.processingState == ProcessingState.completed && !done.isCompleted) {
            done.complete();
          }
        });
        try {
          await _metronomePlayer.play();
          final est = (240 * 1000 / (bpmVal > 0 ? bpmVal : 60)).ceil() + 1500;
          await done.future.timeout(Duration(milliseconds: est), onTimeout: () {});
        } finally {
          await sub.cancel();
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.practiceCountInFail)));
        }
      } finally {
        try {
          await _metronomePlayer.stop();
        } catch (_) {}
      }
      if (!mounted || _rec.epoch != epochAtStart) {
        _rec.arming = false;
        return;
      }
    }
    final started = await _rec.begin(
      mode: RecordingMode.section,
      path: _practicePath(section.index),
      sectionIndex: section.index,
    );
    _rec.arming = false;
    if (!mounted) return;
    if (!started || _selected?.id != lessonAtStart) {
      if (!started) {
        setState(() => _error = strings.practiceMicStartFail);
        return;
      }
      await _rec.stop();
      return;
    }
    setState(() {
      _error = null;
      _takePreview = null;
    });
    _recStartAt = DateTime.now();
    _recElapsed.value = 0;
    _startVuPolling();
    final waitSeconds = section.duration + 8.0 + (_countIn ? 4 * 60 / ((_detail?.bpm ?? 60)) : 0.0);
    final epochForTimer = _rec.epoch;
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(Duration(seconds: waitSeconds.ceil()), () {
      if (mounted && _rec.isSectionRecording && _rec.activeSection == section.index && _rec.epoch == epochForTimer) {
        _stopActiveRecording();
      }
    });
  }

  _TakeRec? _selectedTakeRec(int sectionIndex) {
    final takes = _takes[sectionIndex];
    if (takes == null || takes.isEmpty) return null;
    final idx = (_selectedTake[sectionIndex] ?? takes.length - 1).clamp(0, takes.length - 1);
    return takes[idx];
  }

  Future<void> _submitPractice(LessonSection section) async {
    final detail = _detail;
    if (detail == null) return;
    final bytes = _selectedTakeRec(section.index)?.bytes;
    final path = _recordPaths[section.index];
    if (bytes == null && path == null) return;
    setState(() {
      _practicingSection = section.index;
      _error = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = LessonApi(dio);
      _uploadProgress.value = 0.0;
      PracticeResult result;
      if (bytes != null) {
        result = await api.practiceBytes(detail.id, section.index, bytes, onProgress: (sent, total) {
          if (!mounted) return;
          if (total > 0) _uploadProgress.value = (sent / total).clamp(0.0, 1.0);
        });
      } else if (kIsWeb) {
        final webBytes = await XFile(path!).readAsBytes();
        result = await api.practiceBytes(detail.id, section.index, webBytes);
      } else {
        result = await api.practiceFile(detail.id, section.index, path!);
      }
      if (!mounted || _selected?.id != detail.id) return;
      setState(() => _results[section.index] = result);
      context.read<HistoryService>().add(
            HistoryEntry(
              id: HistoryService.newId(),
              kind: 'practice',
              title: strings.practiceHistoryPhrase(detail.title, section.index + 1),
              status: 'done',
              at: DateTime.now(),
              score: result.metrics.score,
              detail: detail.id,
            ),
          );
      try {
        final progress = await api.myProgress(lessonId: detail.id);
        if (mounted && _selected?.id == detail.id) setState(() => _serverProgress = progress);
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) {
        _uploadProgress.value = null;
        setState(() => _practicingSection = null);
      }
    }
  }

  Future<void> _downloadPracticeMidi(PracticeResult result) async {
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final url = '${dio.options.baseUrl}/api/lessons/practice-midi/${result.userMidi}';
      final name = 'luyen_tap_cau${result.sectionIndex + 1}.mid';
      if (kIsWeb) {
        var dl = url;
        try {
          final raw = url.substring(url.indexOf('/api/'));
          final res = await dio.get('/api/music/play-url', queryParameters: {'path': raw});
          final data = res.data;
          if (data is Map && data['url'] is String && (data['url'] as String).isNotEmpty) {
            final signed = data['url'] as String;
            dl = signed.startsWith('http') ? signed : '${dio.options.baseUrl}$signed';
          }
        } catch (_) {}
        triggerDownload(dl, name);
        return;
      }
      var savePath = '${Directory.systemTemp.path}/$name';
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        try {
          final picked = await FilePicker.platform.saveFile(dialogTitle: strings.saveFileDialog(name), fileName: name);
          if (picked == null) return;
          savePath = picked;
        } catch (_) {}
      }
      await dio.download(url, savePath);
      final shared = Platform.isAndroid || Platform.isIOS;
      if (shared) {
        await shareDownloadedFile(savePath, name);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(shared ? strings.practiceShared(name) : '${strings.practiceSaved} $savePath')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
      }
    }
  }

  List<HistoryEntry> _practiceHistory() {
    final detail = _detail;
    final entries = context.watch<HistoryService>().entries;
    return entries.where((e) => e.kind == 'practice' && (detail == null || e.detail == detail.id)).toList();
  }

  String _scalePathTmp() {
    return kIsWeb ? 'hue_scale.wav' : '${Directory.systemTemp.path}/hue_scale.wav';
  }

  Future<void> _toggleScaleRecord() async {
    if (_rec.isScaleRecording) {
      await _stopActiveRecording();
      return;
    }
    if (_rec.isSectionRecording || _rec.arming || _rec.stopping || _stopUiLock != null) {
      setState(() => _error = strings.practiceBusySection);
      return;
    }
    if (!await _rec.hasPermission()) {
      if (!mounted) return;
      setState(() => _error = strings.practiceMicDenied);
      return;
    }
    _rec.arming = true;
    final epochAtStart = _rec.epoch;
    if (_countIn) {
      try {
        final chain = _metroChain.then((_) async {
          try {
            await _metronomePlayer.stop();
            await _metronomePlayer.setAudioSource(await _bytesSource(_metronomeWav(60)));
          } catch (_) {}
        });
        _metroChain = chain;
        await chain;
        final done = Completer<void>();
        final sub = _metronomePlayer.playerStateStream.listen((st) {
          if (st.processingState == ProcessingState.completed && !done.isCompleted) {
            done.complete();
          }
        });
        try {
          await _metronomePlayer.play();
          await done.future.timeout(const Duration(seconds: 6), onTimeout: () {});
        } finally {
          sub.cancel();
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.practiceCountInFail)));
        }
      } finally {
        try {
          await _metronomePlayer.stop();
        } catch (_) {}
      }
      if (!mounted || _rec.epoch != epochAtStart) {
        _rec.arming = false;
        return;
      }
    }
    final started = await _rec.begin(
      mode: RecordingMode.scale,
      path: _scalePathTmp(),
    );
    _rec.arming = false;
    if (!mounted) return;
    if (!started) {
      setState(() => _error = strings.practiceMicStartFail);
      return;
    }
    setState(() {
      _error = null;
      _scaleResult = null;
    });
    _scaleAutoStop = Timer(const Duration(seconds: 18), () {
      if (mounted && _rec.isScaleRecording && _rec.epoch == epochAtStart) {
        _stopActiveRecording();
      }
    });
  }

  Future<void> _submitScalePractice() async {
    final scale = _selectedScale;
    final path = _scalePath;
    if (scale == null || path == null) return;
    setState(() {
      _scaleBusy = true;
      _error = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = LessonApi(dio);
      Uint8List bytes;
      if (kIsWeb) {
        bytes = await XFile(path).readAsBytes();
      } else {
        bytes = await File(path).readAsBytes();
      }
      final result = await api.scalePracticeBytes(scale.id, bytes, transpose: _scaleTranspose);
      if (!mounted) return;
      setState(() => _scaleResult = result);
      context.read<HistoryService>().add(
            HistoryEntry(
              id: HistoryService.newId(),
              kind: 'practice',
              title: strings.practiceHistoryScale(scale.name),
              status: 'done',
              at: DateTime.now(),
              score: result.score,
              detail: 'scale:${scale.id}',
            ),
          );
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _scaleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    strings = context.watch<LocaleProvider>().strings;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_loadingLessons)
          const Column(
            children: [
              SkeletonLoader(height: 88, margin: EdgeInsets.only(bottom: 8)),
              SkeletonLoader(height: 88, margin: EdgeInsets.only(bottom: 8)),
              SkeletonLoader(height: 88, margin: EdgeInsets.only(bottom: 8)),
            ],
          )
        else if (_lessons.isEmpty)
          EmptyState(
            icon: Icons.school_rounded,
            title: strings.practiceNoLessons,
          )
        else ...[
          DropdownButtonFormField<Lesson>(
            initialValue: _selected,
            decoration: InputDecoration(labelText: strings.practicePickLesson, border: const OutlineInputBorder()),
            items: [
              for (final l in _lessons)
                DropdownMenuItem(value: l, child: Text(l.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (l) {
              if (l != null) _openLesson(l);
            },
          ),
          if (_selected != null) _buildLessonHeader(),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ErrorPanel(message: _error!),
          ),
        if (_loadingDetail)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_detail != null) ...[
          _buildSpeedBar(),
          for (final section in _detail!.sections) _buildSectionCard(section),
          const SizedBox(height: 12),
          _buildProgressCard(),
        ],
        if (_scales.isNotEmpty) ...[
          const SizedBox(height: 12),
          ScalePracticeCard(
            scales: _scales,
            selected: _selectedScale,
            onChanged: (s) => setState(() {
              _selectedScale = s;
              _scaleResult = null;
              _scalePath = null;
            }),
            recording: _rec.isScaleRecording,
            onToggleRecord: _toggleScaleRecord,
            busy: _scaleBusy,
            onSubmit: _submitScalePractice,
            recordPath: _scalePath,
            result: _scaleResult,
            transpose: _scaleTranspose,
            onTransposeChanged: (v) => setState(() {
              _scaleTranspose = v;
              _scaleResult = null;
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildSpeedBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(strings.practiceSlowSpeed, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          for (final v in const [0.5, 0.75, 1.0])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${v}x', style: const TextStyle(fontSize: 11)),
                selected: _speed == v,
                onSelected: (_) => _setSpeed(v),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLessonHeader() {
    final d = _detail;
    final sel = _selected!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (sel.type.isNotEmpty) Chip(label: Text(sel.type, style: const TextStyle(fontSize: 11))),
          if (sel.modeSystem.isNotEmpty) Chip(label: Text(strings.lessonModeChip(sel.modeSystem), style: const TextStyle(fontSize: 11))),
          if (sel.bpm != null) Chip(label: Text('${sel.bpm!.toStringAsFixed(0)} BPM', style: const TextStyle(fontSize: 11))),
          if (d != null) Chip(label: Text(strings.lessonSectionCount(d.sections.length), style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildSectionCard(LessonSection section) {
    final scheme = Theme.of(context).colorScheme;
    final result = _results[section.index];
    final recorded = _takes[section.index]?.isNotEmpty == true || _recordPaths.containsKey(section.index);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${strings.practiceSentence} ${section.index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('${section.start.toStringAsFixed(0)}s - ${section.end.toStringAsFixed(0)}s',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                if (section.hasSample) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.record_voice_over, size: 14, color: AppTheme.imperialGold),
                ],
              ],
            ),
            if (section.lyrics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(section.lyrics, style: const TextStyle(fontSize: 12.5, height: 1.4)),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Switch(
                  value: _countIn,
                  onChanged: (v) => setState(() => _countIn = v),
                ),
                Text(
                  strings.practiceCountInLabel(_detail?.bpm != null ? "(${_detail!.bpm!.toStringAsFixed(0)} BPM)" : ""),
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                Text(
                  strings.practiceSilenceStopHint,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant.withAlpha(150)),
                ),
                Switch(
                  value: _autoGrade,
                  onChanged: (v) => setState(() => _autoGrade = v),
                ),
                Text(
                  strings.practiceAutoGrade,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  icon: Icon(((_looping[section.index] ?? false)) ? Icons.stop : Icons.headphones, size: 16),
                  label: Text((_looping[section.index] ?? false) ? strings.practiceStopSample : strings.practiceListenLoop),
                  onPressed: () => _toggleSample(section),
                ),
                if (section.hasSample)
                  OutlinedButton.icon(
                    icon: Icon(_playingSample[section.index] == true ? Icons.stop : Icons.record_voice_over, size: 16),
                    label: Text(_playingSample[section.index] == true ? strings.practiceStopSample : strings.practiceListenSample),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.goldReadable(context)),
                    onPressed: () => _toggleMasterSample(section),
                  ),
                FilledButton.icon(
                  icon: Icon(_rec.isSectionRecording && _rec.activeSection == section.index ? Icons.stop : Icons.mic, size: 16),
                  label: Text(_rec.isSectionRecording && _rec.activeSection == section.index ? strings.practiceStopRecord : strings.practiceRecord),
                  style: FilledButton.styleFrom(
                    backgroundColor: _rec.isSectionRecording && _rec.activeSection == section.index ? AppTheme.statusDanger : null,
                  ),
                  onPressed: () => _toggleRecord(section),
                ),
                CommonButton(
                  label: strings.practiceGrade,
                  loading: _practicingSection == section.index,
                  onPressed: recorded && _practicingSection != section.index ? () => _submitPractice(section) : null,
                ),
                if (recorded && result != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(strings.practiceRegrade),
                    onPressed: _practicingSection == section.index ? null : () => _submitPractice(section),
                  ),
                if (result?.userMidi.isNotEmpty == true)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.music_note, size: 16),
                    label: Text(strings.practiceMidiBtn),
                  onPressed: () => _downloadPracticeMidi(result!),
                ),
              ],
            ),
            if (_practicingSection == section.index)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ValueListenableBuilder<double?>(
                  valueListenable: _uploadProgress,
                  builder: (context, prog, _) => LinearProgressIndicator(
                    value: prog,
                    minHeight: 6,
                    color: scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            if (_rec.isSectionRecording && _rec.activeSection == section.index) ...[
              _buildSectionGuide(section),
              if (!kIsWeb) ...[
                const SizedBox(height: 8),
                ValueListenableBuilder<double>(
                  valueListenable: _vuLevel,
                  builder: (context, vu, _) => Row(
                    children: [
                      const Icon(Icons.fiber_manual_record, color: AppTheme.statusDanger, size: 12),
                      const SizedBox(width: 6),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: ((vu + 60) / 60).clamp(0.0, 1.0),
                          minHeight: 8,
                          color: scheme.primary,
                          backgroundColor: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${vu.toStringAsFixed(0)} dB', style: const TextStyle(fontSize: 10.5)),
                    ],
                  ),
                ),
              ],
            ],
            if (recorded && _takes[section.index]?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _takes[section.index]!.length; i++)
                    ChoiceChip(
                      label: Text(strings.practiceTakeChip(_takes[section.index]![i].no),
                          style: const TextStyle(fontSize: 11)),
                      selected: (_selectedTake[section.index] ?? 0) == i,
                      onSelected: (_) => setState(() => _selectedTake[section.index] = i),
                    ),
                ],
              ),
              AudioPlayerBar(bytes: _selectedTakeRec(section.index)?.bytes),
            ] else if (recorded && !kIsWeb && _recordPaths[section.index] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.replay, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(strings.practiceReplayTake, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
              AudioPlayerBar(filePath: _recordPaths[section.index]),
            ],
            if (_takePreview != null && recorded && result == null) _buildTakePreview(section),
            if (recorded && result == null && _practicingSection != section.index)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(strings.practiceRecorded, style: const TextStyle(fontSize: 12)),
              ),
            if (result != null) ...[
              const Divider(height: 20),
              _buildResultSummary(result, section),
              const SizedBox(height: 8),
              OverlayPitchChart(result: result),
              if (result.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in result.notes)
                      Tooltip(
                        message: n.hint.isNotEmpty ? '${_verdictLabel(n.verdictCode)}: ${n.hint}' : _verdictLabel(n.verdictCode),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: n.refEnd > n.refStart ? () => _playRefSegment(n.refStart, n.refEnd, section) : null,
                          child: Chip(
                            backgroundColor: _verdictColor(n.verdictCode),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (n.verdictCode == 'off' || n.verdictCode == 'octave' || n.verdictCode == 'minor')
                                  Icon(n.errCents > 0 ? Icons.arrow_upward : Icons.arrow_downward, size: 11, color: scheme.onSurfaceVariant),
                                if (n.verdictCode == 'ok' && n.vibrato) Icon(Icons.waves, size: 11, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 3),
                                Text(
                                  n.verdictCode == 'unclear'
                                      ? _verdictLabel(n.verdictCode)
                                      : '${n.errCents > 0 ? '+' : ''}${n.errCents.toStringAsFixed(0)}c',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Color _verdictColor(String code) {
    switch (code) {
      case 'ok':
        return AppTheme.statusSuccess.withAlpha(40);
      case 'minor':
        return AppTheme.statusWarning.withAlpha(40);
      case 'octave':
        return AppTheme.statusWarning.withAlpha(70);
      case 'off':
        return AppTheme.statusDanger.withAlpha(40);
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(40);
    }
  }

  String _verdictLabel(String code) {
    switch (code) {
      case 'ok':
        return strings.verdictOk;
      case 'minor':
        return strings.verdictMinor;
      case 'off':
        return strings.verdictOff;
      case 'octave':
        return strings.verdictOctave;
      default:
        return strings.verdictUnclear;
    }
  }

  List<FlSpot> _guideSpots(LessonSection section) {
    final detail = _detail;
    final spots = <FlSpot>[];
    if (detail == null) return spots;
    final pts = <FlSpot>[];
    for (var i = 0; i < detail.contourTimes.length && i < detail.contourF0.length; i++) {
      final t = detail.contourTimes[i];
      if (t >= section.start && t <= section.end && detail.contourF0[i] > 0) {
        pts.add(FlSpot(t - section.start, detail.contourF0[i]));
      }
    }
    if (pts.length > 200) {
      final step = pts.length / 200;
      var k = 0.0;
      while (spots.length < 200 && k < pts.length) {
        spots.add(pts[k.toInt()]);
        k += step;
      }
    } else {
      spots.addAll(pts);
    }
    return spots;
  }

  Widget _buildSectionGuide(LessonSection section) {
    final scheme = Theme.of(context).colorScheme;
    final spots = _guideSpots(section);
    final lines = section.lyrics.isEmpty
        ? <String>[]
        : section.lyrics.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final palette = ChartPalette.of(context);
    var maxY = spots.isEmpty ? 1.0 : spots.map((s) => s.y).reduce(math.max);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, size: 13, color: AppTheme.imperialGold),
              const SizedBox(width: 4),
              Expanded(
                child: Text(strings.practiceGuideTitle, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
          if (spots.isNotEmpty)
            SizedBox(
              height: 110,
              child: ValueListenableBuilder<double>(
                valueListenable: _recElapsed,
                builder: (context, elapsed, _) {
                  final maxX = math.max(1.0, section.duration);
                  return LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX,
                      minY: 0,
                      maxY: maxY * 1.15,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: true, border: Border.all(color: Theme.of(context).dividerColor)),
                      titlesData: const FlTitlesData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      extraLinesData: ExtraLinesData(
                        verticalLines: [
                          if (elapsed > 0 && elapsed <= maxX)
                            VerticalLine(x: elapsed, color: scheme.primary, strokeWidth: 1.2),
                        ],
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: false,
                          barWidth: 2,
                          color: palette.reference,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (lines.isNotEmpty)
            ValueListenableBuilder<double>(
              valueListenable: _recElapsed,
              builder: (context, elapsed, _) {
                final lineDur = lines.isNotEmpty ? section.duration / lines.length : section.duration;
                final current = lineDur > 0 ? (elapsed / lineDur).floor().clamp(0, lines.length - 1) : 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            lines[i],
                            style: TextStyle(
                              fontSize: i == current ? 13.5 : 11.5,
                              height: 1.35,
                              fontWeight: i == current ? FontWeight.bold : FontWeight.w400,
                              color: i == current ? scheme.onSurface : scheme.onSurfaceVariant.withAlpha(130),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTakePreview(LessonSection section) {
    final detail = _detail;
    final scheme = Theme.of(context).colorScheme;
    final preview = _takePreview!;
    final target = <FlSpot>[];
    if (detail != null) {
      final pts = <FlSpot>[];
      for (var i = 0; i < detail.contourTimes.length && i < detail.contourF0.length; i++) {
        final t = detail.contourTimes[i];
        if (t >= section.start - 0.5 && t <= section.end + 0.5 && detail.contourF0[i] > 0) {
          pts.add(FlSpot(t - section.start, detail.contourF0[i]));
        }
      }
      if (pts.length > 300) {
        final step = pts.length / 300;
        var k = 0.0;
        while (target.length < 300 && k < pts.length) {
          target.add(pts[k.toInt()]);
          k += step;
        }
      } else {
        target.addAll(pts);
      }
    }
    final taken = <FlSpot>[];
    for (final p in preview.points) {
      if (p.f0 > 0) taken.add(FlSpot(p.t, p.f0));
    }
    if (taken.isEmpty) return const SizedBox.shrink();
    final all = [...taken, ...target];
    var maxY = all.map((s) => s.y).fold(0.0, math.max);
    final maxX = all.map((s) => s.x).fold(0.0, math.max);
    if (maxY <= 0) maxY = 1;
    final palette = ChartPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.practiceTakePreview, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          SizedBox(
            height: 130,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(1, maxX),
                minY: 0,
                maxY: maxY * 1.15,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: true, border: Border.all(color: Theme.of(context).dividerColor)),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: ChartPalette.styledTouch(context),
                lineBarsData: [
                  if (target.isNotEmpty)
                    LineChartBarData(
                      spots: target,
                      isCurved: false,
                      barWidth: 2,
                      color: palette.reference,
                      dotData: const FlDotData(show: false),
                    ),
                  LineChartBarData(
                    spots: taken,
                    isCurved: false,
                    barWidth: 1.5,
                    color: palette.user,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSummary(PracticeResult result, LessonSection section) {
    final m = result.metrics;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _scoreBadge(strings.practiceScoreTotal, m.score, scheme.primary),
            const SizedBox(width: 8),
            _scoreBadge(strings.practiceScorePitch, m.pitchScore, AppTheme.goldReadable(context)),
            const SizedBox(width: 8),
            _scoreBadge(strings.practiceScoreRhythm, m.rhythmScore, ChartPalette.of(context).user),
            const SizedBox(width: 8),
            _scoreBadge(strings.practiceScoreStability, m.stabilityScore, scheme.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.practiceAvgError(m.meanAbsCents.toStringAsFixed(0)), style: const TextStyle(fontSize: 12)),
                  Text(
                    result.reference == 'sample' ? strings.practiceRefSample : strings.practiceRefOriginal,
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (m.ornament > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              strings.practiceOrnamentValue(m.ornament.toStringAsFixed(0), m.vibratoRate.toStringAsFixed(1)),
              style: TextStyle(fontSize: 11.5, color: AppTheme.goldReadable(context)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            strings.practiceMatchedNotes(m.matchedNotes, m.missingNotes),
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ),
        if (m.referenceQuality == 'poor')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.statusWarning.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 13, color: AppTheme.statusWarning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(strings.practiceRefPoorWarning, style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
        if (m.summaryHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(m.summaryHint, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _scoreBadge(String label, double value, Color color) {
    return Column(
      children: [
        Text(value.toStringAsFixed(0), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildProgressCard() {
    final strings = this.strings;
    final scheme = Theme.of(context).colorScheme;
    final history = _practiceHistory();
    final serverEntries = _serverProgress;
    List<double> scores;
    String sourceLabel;
    if (_serverProgressAvailable && serverEntries.isNotEmpty) {
      scores = serverEntries.take(10).map((e) => e.score).toList().reversed.toList();
      sourceLabel = strings.practiceServerProgress;
    } else {
      if (history.isEmpty) {
        return const SizedBox.shrink();
      }
      scores = history.take(10).map((e) => e.score ?? 0).toList().reversed.toList();
      sourceLabel = strings.practiceLocalProgress;
    }
    final avgList = _serverProgressAvailable && serverEntries.isNotEmpty
        ? serverEntries.take(5).map((e) => e.score).toList()
        : history.take(5).map((e) => e.score ?? 0).toList();
    final avg = avgList.length >= 2 ? (avgList.reduce((a, b) => a + b) / avgList.length).toStringAsFixed(1) : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(strings.practiceProgressTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('($sourceLabel)', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (avg != null)
                  Text('${strings.practiceAvg5}: $avg', style: const TextStyle(fontSize: 12, color: AppTheme.statusSuccess)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: scores.length >= 2
                  ? _ProgressLineChart(scores: scores)
                  : Text('${strings.practiceLastScore}: ${scores.last.toStringAsFixed(1)}'),
            ),
            const SizedBox(height: 6),
            if (_serverProgressAvailable && serverEntries.isNotEmpty)
              for (final e in serverEntries.take(6))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Text(
                        e.createdAt.length >= 16 ? e.createdAt.substring(0, 16) : e.createdAt,
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          strings.practiceHistoryPhrase(_selected?.title ?? '', e.section + 1),
                          style: const TextStyle(fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        e.score.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.statusSuccess, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              else
                for (final e in history.take(6))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        Text(
                          '${e.at.day.toString().padLeft(2, '0')}/${e.at.month.toString().padLeft(2, '0')} ${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.title,
                            style: const TextStyle(fontSize: 11.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          (e.score ?? 0).toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.statusSuccess, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLineChart extends StatelessWidget {
  final List<double> scores;

  const _ProgressLineChart({required this.scores});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: true, border: Border.all(color: Theme.of(context).dividerColor)),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < scores.length; i++) FlSpot(i.toDouble(), scores[i])],
            isCurved: true,
            barWidth: 2,
            color: ChartPalette.of(context).reference,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
