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
import '../../services/practice_resume.dart';
import '../../services/teaching_utils.dart';
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
import '../../widgets/hue_icons.dart';

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
  String? _loadError;
  bool _countIn = true;
  late AppStrings strings;

  final Map<int, String> _recordPaths = {};
  int? _practicingSection;
  int? _countInSection;
  int _detailEpoch = 0;
  Timer? _countInBeatTimer;
  Completer<void>? _countInDone;
  final Map<int, PracticeResult> _results = {};
  final Map<int, bool> _looping = {};
  final Map<int, List<_TakeRec>> _takes = {};
  final Map<int, int> _selectedTake = {};
  final Map<int, Map<int, PracticeResult>> _takeResults = {};
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
  final ValueNotifier<int> _countInLeft = ValueNotifier<int>(0);
  final ValueNotifier<({double hz, String? note, int? centsDelta})?> _livePitch = ValueNotifier(null);
  DateTime? _recStartAt;
  String? _activeRecordPath;
  bool _autoGrade = false;
  bool _heardVoice = false;
  DateTime? _lastVoiceAt;
  int _takeCounter = 0;
  LocalPitchResult? _takePreview;
  int? _takePreviewNo;
  bool _analyzingPreview = false;

  List<ProgressEntry> _serverProgress = [];
  List<ProgressEntry> _allProgress = [];
  bool _serverProgressAvailable = false;
  DateTime? _serverToday;

  List<ScaleInfo> _scales = [];
  ScaleInfo? _selectedScale;
  String? _scalePath;
  Uint8List? _scaleBytes;
  bool _scaleBusy = false;
  bool _downloadingMidi = false;
  ScalePractice? _scaleResult;
  String? _scaleError;
  bool _scaleCanRetry = false;
  int _scaleTranspose = 0;
  StreamSubscription? _sampleSub;

  @override
  void initState() {
    super.initState();
    _loadLessons();
    PracticeResume.lessonId.addListener(_flushPendingResume);
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
    PracticeResume.lessonId.removeListener(_flushPendingResume);
    AppLifecycleService.instance.unregister(_lifecycleHooks);
    _vuTimer?.cancel();
    _autoStopTimer?.cancel();
    _scaleAutoStop?.cancel();
    _countInBeatTimer?.cancel();
    _countInBeatTimer = null;
    if (_countInDone != null && !_countInDone!.isCompleted) {
      _countInDone!.complete();
    }
    _countInDone = null;
    _sampleSub?.cancel();
    _vuLevel.dispose();
    _recElapsed.dispose();
    _uploadProgress.dispose();
    _countInLeft.dispose();
    _livePitch.dispose();
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
      _loadError = null;
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
        _loadingLessons = false;
      });
      _flushPendingResume();
    } catch (e) {
      if (mounted) setState(() => _loadError = _localizedError(e));
    } finally {
      if (mounted && _loadingLessons) setState(() => _loadingLessons = false);
    }
  }

  void _flushPendingResume() {
    final id = PracticeResume.lessonId.value;
    if (id == null || id.isEmpty || !mounted) return;
    if (id.startsWith('scale:')) {
      PracticeResume.lessonId.value = null;
      return;
    }
    if (_loadingLessons) return;
    if (_lessons.isEmpty) {
      unawaited(_loadLessons());
      return;
    }
    PracticeResume.lessonId.value = null;
    unawaited(_openLessonById(id));
  }

  String _localizedError(Object e) {
    final code = ApiClient.errorCode(e);
    switch (code) {
      case 'too_quiet':
        return strings.practiceErrTooQuiet;
      case 'no_voice':
        return strings.practiceErrNoVoice;
      case 'too_short':
        return strings.practiceErrTooShort;
      case 'reference_invalid':
        return strings.practiceErrRefInvalid;
      default:
        return ApiClient.describe(e);
    }
  }

  Future<void> _stopEverything() async {
    _playGen++;
    _countInBeatTimer?.cancel();
    _countInBeatTimer = null;
    if (_countInDone != null && !_countInDone!.isCompleted) {
      _countInDone!.complete();
    }
    _countInDone = null;
    if (mounted) _countInLeft.value = 0;
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
    _livePitch.value = null;
    _activeRecordPath = null;
    _recStartAt = null;
    _recElapsed.value = 0;
    _looping.clear();
    _playingSample.clear();
    _countInSection = null;
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
        int newTakeNo = 0;
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
        var webAnalyze = false;
        Uint8List? scaleBytesRead;
        if (result.started && result.mode == RecordingMode.scale && p != null) {
          try {
            scaleBytesRead = kIsWeb ? await XFile(p).readAsBytes() : await File(p).readAsBytes();
          } catch (_) {
            scaleBytesRead = null;
          }
        }
        setState(() {
          _vuLevel.value = -60;
          _livePitch.value = null;
          _activeRecordPath = null;
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
              newTakeNo = _takeCounter;
              while (takes.length > 3) {
                final removed = takes.removeAt(0);
                _takeResults[result.sectionIndex]?.remove(removed.no);
              }
              _takes[result.sectionIndex] = takes;
              _selectedTake[result.sectionIndex] = takes.length - 1;
              _results.remove(result.sectionIndex);
            }
            if (preview != null && newTakeNo > 0) {
              _takePreview = preview;
              _takePreviewNo = newTakeNo;
            }
            if (kIsWeb && takeBytes != null && preview == null && newTakeNo > 0) {
              _analyzingPreview = true;
              webAnalyze = true;
            }
          }
          if (result.started && result.mode == RecordingMode.scale) {
            _scalePath = p;
            _scaleResult = null;
            _scaleError = null;
            _scaleCanRetry = false;
            _scaleBytes = scaleBytesRead;
          }
        });
        if (webAnalyze && takeBytes != null) {
          final epoch = _rec.epoch;
          final bytes = takeBytes;
          final no = newTakeNo;
          Future(() async {
            LocalPitchResult? p2;
            try {
              p2 = await LocalPitch.analyzeChunked(bytes, secondsLimit: 10);
            } catch (_) {}
            if (!mounted) {
              return;
            }
            if (epoch != _rec.epoch) {
              setState(() => _analyzingPreview = false);
              return;
            }
            setState(() {
              _analyzingPreview = false;
              if (p2 != null) {
                _takePreview = p2;
                _takePreviewNo = no;
              }
            });
          });
        }
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

  Future<void> _openLessonById(String lessonId) async {
    if (lessonId.isEmpty || lessonId.startsWith('scale:')) return;
    final matches = _lessons.where((l) => l.id == lessonId).toList();
    if (matches.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.practiceLessonGone)));
      }
      return;
    }
    await _openLesson(matches.first);
  }

  Future<void> _openLesson(Lesson lesson) async {
    final epoch = ++_detailEpoch;
    await _stopEverything();
    if (!mounted || epoch != _detailEpoch) return;
    _rec.epoch++;
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
      _takePreviewNo = null;
      _analyzingPreview = false;
      _serverProgress = [];
      _allProgress = [];
      _takeResults.clear();
      _takeCounter = 0;
      _scalePath = null;
      _scaleResult = null;
      _scaleBytes = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = LessonApi(dio);
      final detail = await api.detail(lesson.id);
      if (!mounted || epoch != _detailEpoch) return;
      final sampleTargets = detail.sections.where((s) => s.hasSample && s.sampleUrl.isNotEmpty).toList();
      final signedList = await Future.wait<String?>([
        _signPath(dio, '/api/heritage/${lesson.id}/audio'),
        for (final s in sampleTargets) _signPath(dio, s.sampleUrl),
      ]);
      if (!mounted || epoch != _detailEpoch) return;
      _signedRefUrl = signedList[0];
      for (var i = 0; i < sampleTargets.length; i++) {
        final signed = signedList[i + 1];
        if (signed != null) _signedSampleUrls[sampleTargets[i].index] = signed;
      }
      List<ProgressEntry> progress = [];
      List<ProgressEntry> allProgress = [];
      bool serverOk = false;
      DateTime? serverToday;
      try {
        final page = await api.myProgress(limit: 400);
        allProgress = page.items;
        progress = allProgress.where((e) => e.lessonId == lesson.id).toList();
        serverToday = parsePracticeDate(
          page.serverUtcNow.isNotEmpty ? page.serverUtcNow : page.serverToday,
          utcOffset: page.serverUtcNow.isNotEmpty ? DateTime.now().timeZoneOffset : null,
        );
        serverOk = true;
      } catch (_) {}
      if (!mounted || epoch != _detailEpoch) return;
      setState(() {
        _detail = detail;
        _serverProgress = progress;
        _allProgress = allProgress;
        _serverProgressAvailable = serverOk;
        _serverToday = serverToday;
      });
    } catch (e) {
      if (mounted && epoch == _detailEpoch) setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted && epoch == _detailEpoch) setState(() => _loadingDetail = false);
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
    unawaited(_samplePlayer.play());
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

  Future<void> _playRefSegment(double start, double end, LessonSection section, {double leadIn = 0.25}) async {
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
      final clipStart = Duration(milliseconds: (math.max(0, base + start - leadIn) * 1000).round());
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

  double _refF0AtElapsed(LessonSection section, double elapsed) {
    final detail = _detail;
    if (detail == null || detail.contourTimes.isEmpty || detail.contourF0.isEmpty) return 0;
    final targetT = section.start + elapsed;
    var bestDist = 0.25;
    var bestF0 = 0.0;
    final n = math.min(detail.contourTimes.length, detail.contourF0.length);
    for (var i = 0; i < n; i++) {
      final f = detail.contourF0[i];
      if (f <= 0) continue;
      final d = (detail.contourTimes[i] - targetT).abs();
      if (d < bestDist) {
        bestDist = d;
        bestF0 = f;
      }
    }
    return bestF0;
  }

  Future<double?> _readLiveTailF0(String path) async {
    const needBytes = LocalPitch.frameSize * 2;
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final len = await raf.length();
      if (len < 44 + needBytes) return null;
      final start = math.max(44, len - needBytes);
      await raf.setPosition(start);
      final tail = await raf.read(len - start);
      return LocalPitch.estimateLiveF0(tail);
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  void _startVuPolling([LessonSection? section]) {
    _vuTimer?.cancel();
    _heardVoice = false;
    _lastVoiceAt = null;
    _livePitch.value = null;
    final epoch = _rec.epoch;
    const period = kIsWeb ? Duration(milliseconds: 200) : Duration(milliseconds: 120);
    _vuTimer = Timer.periodic(period, (_) async {
      try {
        final amp = await _rec.currentAmplitude();
        if (!mounted || epoch != _rec.epoch) return;
        _vuLevel.value = amp;
        if (_recStartAt != null) {
          _recElapsed.value = DateTime.now().difference(_recStartAt!).inMilliseconds / 1000.0;
        }
        if (section != null && !kIsWeb && _activeRecordPath != null && amp > -42) {
          final hz = await _readLiveTailF0(_activeRecordPath!);
          if (!mounted || epoch != _rec.epoch) return;
          if (hz != null && hz > 0) {
            final refHz = _refF0AtElapsed(section, _recElapsed.value * _speed);
            final note = LocalPitch.noteLabel(hz);
            final delta = refHz > 0 ? LocalPitch.foldOctaveDiffCents(hz, refHz)?.round() : null;
            _livePitch.value = (hz: hz, note: note, centsDelta: delta);
          } else {
            _livePitch.value = null;
          }
        } else {
          _livePitch.value = null;
        }
        if (_vuLevel.value > -35) {
          _heardVoice = true;
          _lastVoiceAt = DateTime.now();
        } else if (_heardVoice && _lastVoiceAt != null) {
          final quietFor = DateTime.now().difference(_lastVoiceAt!).inMilliseconds;
          if (quietFor > 1200 && mounted && _rec.isSectionRecording && epoch == _rec.epoch) {
            _vuTimer?.cancel();
            _livePitch.value = null;
            _activeRecordPath = null;
            _stopActiveRecording();
          }
        }
      } catch (_) {}
    });
  }

  Future<bool> _runCountIn({
    required int bpmVal,
    required int epochAtStart,
    String? lessonAtStart,
  }) async {
    if (!_countIn) return true;
    try {
      final chain = _metroChain.then((_) async {
        try {
          await _metronomePlayer.stop();
          await _metronomePlayer.setAudioSource(await _bytesSource(_metronomeWav(bpmVal)));
        } catch (_) {}
      });
      _metroChain = chain;
      await chain;
      if (!mounted || _rec.epoch != epochAtStart || (lessonAtStart != null && _selected?.id != lessonAtStart)) {
        return false;
      }
      final done = Completer<void>();
      _countInDone = done;
      final sub = _metronomePlayer.playerStateStream.listen((st) {
        if (st.processingState == ProcessingState.completed && !done.isCompleted) {
          done.complete();
        }
      });
      try {
        final safeBpm = bpmVal > 0 ? bpmVal : 60;
        final beatMs = (60000 / safeBpm).round().clamp(100, 2000);
        const beats = 4;
        _countInLeft.value = beats;
        var beatIdx = 0;
        _countInBeatTimer?.cancel();
        _countInBeatTimer = Timer.periodic(Duration(milliseconds: beatMs), (t) {
          if (!mounted || _rec.epoch != epochAtStart) {
            t.cancel();
            if (!done.isCompleted) done.complete();
            return;
          }
          beatIdx++;
          _countInLeft.value = beats - beatIdx > 0 ? beats - beatIdx : 0;
        });
        unawaited(_metronomePlayer.play());
        final est = (240 * 1000 / safeBpm).ceil() + 1500;
        await done.future.timeout(Duration(milliseconds: est), onTimeout: () {});
      } finally {
        _countInBeatTimer?.cancel();
        _countInBeatTimer = null;
        _countInDone = null;
        if (mounted) _countInLeft.value = 0;
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
    return mounted && _rec.epoch == epochAtStart && (lessonAtStart == null || _selected?.id == lessonAtStart);
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
    setState(() => _countInSection = section.index);
    if (!await _rec.hasPermission()) {
      _rec.arming = false;
      if (!mounted) return;
      setState(() {
        _countInSection = null;
        _error = strings.practiceMicDenied;
      });
      return;
    }
    if (!mounted || _selected?.id != lessonAtStart) {
      _rec.arming = false;
      if (mounted) setState(() => _countInSection = null);
      return;
    }
    final epochAtStart = _rec.epoch;
    final bpmVal = (((_detail?.bpm ?? 60) * _speed).round()).clamp(30, 200);
    final ok = await _runCountIn(bpmVal: bpmVal, epochAtStart: epochAtStart, lessonAtStart: lessonAtStart);
    if (!ok) {
      _rec.arming = false;
      if (mounted) setState(() => _countInSection = null);
      return;
    }
    final recPath = _practicePath(section.index);
    final started = await _rec.begin(
      mode: RecordingMode.section,
      path: recPath,
      sectionIndex: section.index,
    );
    _rec.arming = false;
    if (!mounted) return;
    if (!started || _selected?.id != lessonAtStart) {
      setState(() => _countInSection = null);
      if (!started) {
        setState(() => _error = strings.practiceMicStartFail);
        return;
      }
      await _rec.stop();
      return;
    }
    _activeRecordPath = recPath;
    setState(() {
      _error = null;
      _takePreview = null;
      _takePreviewNo = null;
      _analyzingPreview = false;
      _countInSection = null;
    });
    _recStartAt = DateTime.now();
    _recElapsed.value = 0;
    _startVuPolling(section);
    final waitSeconds = (section.duration / _speed) + 8.0;
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
    if (_practicingSection == section.index) return;
    final detail = _detail;
    if (detail == null) return;
    final selectedTake = _selectedTakeRec(section.index);
    final bytes = selectedTake?.bytes;
    final takeNo = selectedTake?.no;
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
      final stillSelectedTake = _selectedTakeRec(section.index)?.no == takeNo;
      setState(() {
        if (takeNo != null) {
          final m = _takeResults[section.index] ?? <int, PracticeResult>{};
          m[takeNo] = result;
          _takeResults[section.index] = m;
        }
        if (stillSelectedTake) {
          _results[section.index] = result;
        }
      });
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
        final page = await api.myProgress(limit: 400);
        if (mounted && _selected?.id == detail.id) {
          setState(() {
            _allProgress = page.items;
            _serverProgress = page.items.where((e) => e.lessonId == detail.id).toList();
            _serverToday = parsePracticeDate(
              page.serverUtcNow.isNotEmpty ? page.serverUtcNow : page.serverToday,
              utcOffset: page.serverUtcNow.isNotEmpty ? DateTime.now().timeZoneOffset : null,
            ) ?? _serverToday;
          });
        }
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _error = _localizedError(e));
    } finally {
      if (mounted) {
        _uploadProgress.value = null;
        setState(() => _practicingSection = null);
      }
    }
  }

  Future<void> _downloadPracticeMidi(PracticeResult result) async {
    if (_downloadingMidi) return;
    setState(() => _downloadingMidi = true);
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final url = '${dio.options.baseUrl}/api/lessons/practice-midi/${result.userMidi}';
      final name = 'luyen_tap_cau${result.sectionIndex + 1}.mid';
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
      if (kIsWeb) {
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
      await dio.download(dl, savePath);
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
    } finally {
      if (mounted) {
        setState(() => _downloadingMidi = false);
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
    if (_rec.isSectionRecording) {
      setState(() {
        _scaleError = strings.practiceBusySection;
        _scaleCanRetry = false;
      });
      return;
    }
    if (_rec.arming || _rec.stopping || _stopUiLock != null) return;
    _rec.arming = true;
    setState(() {
      _scaleError = null;
      _scaleCanRetry = false;
    });
    if (!await _rec.hasPermission()) {
      _rec.arming = false;
      if (!mounted) return;
      setState(() {
        _scaleError = strings.practiceMicDenied;
        _scaleCanRetry = false;
      });
      return;
    }
    if (!mounted) {
      _rec.arming = false;
      return;
    }
    final epochAtStart = _rec.epoch;
    final ok = await _runCountIn(bpmVal: 60, epochAtStart: epochAtStart);
    if (!ok) {
      _rec.arming = false;
      if (mounted) setState(() {});
      return;
    }
    final started = await _rec.begin(
      mode: RecordingMode.scale,
      path: _scalePathTmp(),
    );
    _rec.arming = false;
    if (!mounted) return;
    if (!started) {
      setState(() {
        _scaleError = strings.practiceMicStartFail;
        _scaleCanRetry = false;
      });
      return;
    }
    setState(() {
      _scaleError = null;
      _scaleCanRetry = false;
      _scaleResult = null;
    });
    _scaleAutoStop = Timer(const Duration(seconds: 18), () {
      if (mounted && _rec.isScaleRecording && _rec.epoch == epochAtStart) {
        _stopActiveRecording();
      }
    });
  }

  Future<void> _submitScalePractice() async {
    if (_scaleBusy) return;
    final scale = _selectedScale;
    final path = _scalePath;
    if (scale == null || path == null) return;
    setState(() {
      _scaleBusy = true;
      _scaleError = null;
      _scaleCanRetry = false;
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
      if (mounted) {
        setState(() {
          _scaleError = ApiClient.describe(e);
          _scaleCanRetry = true;
        });
      }
    } finally {
      if (mounted) setState(() => _scaleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    strings = context.watch<LocaleProvider>().strings;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_loadingLessons)
          const Column(
            children: [
              SkeletonLoader(height: 88, margin: EdgeInsets.only(bottom: AppSpacing.sm)),
              SkeletonLoader(height: 88, margin: EdgeInsets.only(bottom: AppSpacing.sm)),
              SkeletonLoader(height: 88, margin: EdgeInsets.only(bottom: AppSpacing.sm)),
            ],
          )
        else if (_lessons.isEmpty)
          EmptyState(
            icon: HueIcons.school,
            title: strings.practiceNoLessons,
          )
        else ...[
          DropdownButtonFormField<Lesson>(
            initialValue: _selected,
            isExpanded: true,
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
        if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: ErrorPanel(message: _loadError!, onRetry: _loadLessons),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: ErrorPanel(message: _error!),
          ),
        if (_loadingDetail)
          const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator())),
        if (_detail != null) ...[
          _buildPracticeToolbar(),
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
              _scaleError = null;
              _scaleCanRetry = false;
              _scalePath = null;
              _scaleBytes = null;
            }),
            recording: _rec.isScaleRecording,
            onToggleRecord: _toggleScaleRecord,
            busy: _scaleBusy,
            arming: _rec.arming,
            countInLeft: _countInLeft,
            errorMessage: _scaleError,
            onRetryError: (_scaleCanRetry && _scalePath != null && !_scaleBusy && !_rec.isScaleRecording && !_rec.arming)
                ? _submitScalePractice
                : null,
            onSubmit: _submitScalePractice,
            recordPath: _scalePath,
            result: _scaleResult,
            transpose: _scaleTranspose,
              onTransposeChanged: (v) => setState(() {
                _scaleTranspose = v;
                _scaleResult = null;
                _scaleError = null;
                _scaleCanRetry = false;
              }),
            ),
            if (_scaleResult != null && _scaleBytes != null) ...[
              const SizedBox(height: 8),
              AudioPlayerBar(bytes: _scaleBytes),
            ],
          ],
        ],
    );
  }

  Widget _buildPracticeToolbar() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(strings.practiceSlowSpeed, style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant)),
            for (final v in const [0.5, 0.75, 1.0])
              ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                label: Text('${v}x', style: const TextStyle(fontSize: AppFontSize.xs)),
                selected: _speed == v,
                onSelected: (_) => _setSpeed(v),
              ),
            Switch(
              value: _countIn,
              onChanged: (v) => setState(() => _countIn = v),
            ),
            Text(
              strings.practiceCountInLabel(_detail?.bpm != null ? "(${_detail!.bpm!.toStringAsFixed(0)} BPM)" : ""),
              style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
            ),
            Text(
              strings.practiceSilenceStopHint,
              style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant),
            ),
            Switch(
              value: _autoGrade,
              onChanged: (v) => setState(() => _autoGrade = v),
            ),
            Text(
              strings.practiceAutoGrade,
              style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonHeader() {
    final d = _detail;
    final sel = _selected!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (sel.type.isNotEmpty) Chip(label: Text(sel.type, style: const TextStyle(fontSize: AppFontSize.xs))),
          if (sel.modeSystem.isNotEmpty) Chip(label: Text(strings.lessonModeChip(sel.modeSystem), style: const TextStyle(fontSize: AppFontSize.xs))),
          if (sel.bpm != null) Chip(label: Text('${sel.bpm!.toStringAsFixed(0)} BPM', style: const TextStyle(fontSize: AppFontSize.xs))),
          if (d != null) Chip(label: Text(strings.lessonSectionCount(d.sections.length), style: const TextStyle(fontSize: AppFontSize.xs))),
        ],
      ),
    );
  }

  Widget _buildSectionCard(LessonSection section) {
    final scheme = Theme.of(context).colorScheme;
    final result = _results[section.index];
    final recorded = _takes[section.index]?.isNotEmpty == true || _recordPaths.containsKey(section.index);
    return Card(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
              children: [
                Text('${strings.practiceSentence} ${section.index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('${section.start.toStringAsFixed(0)}s - ${section.end.toStringAsFixed(0)}s',
                    style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant)),
                if (section.hasSample) ...[
                  const SizedBox(width: 8),
                  HueIcon(HueIcons.recordVoiceOver, size: 14, color: AppTheme.goldReadable(context)),
                ],
              ],
            ),
            if (section.lyrics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(section.lyrics, style: const TextStyle(fontSize: AppFontSize.sm, height: 1.4)),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  icon: HueIcon(((_looping[section.index] ?? false)) ? HueIcons.stop : HueIcons.headphones, size: 16, decorative: true),
                  label: Text((_looping[section.index] ?? false) ? strings.practiceStopSample : strings.practiceListenLoop),
                  onPressed: () => _toggleSample(section),
                ),
                if (section.hasSample)
                  OutlinedButton.icon(
                    icon: HueIcon(_playingSample[section.index] == true ? HueIcons.stop : HueIcons.recordVoiceOver, size: 16, decorative: true),
                    label: Text(_playingSample[section.index] == true ? strings.practiceStopSample : strings.practiceListenSample),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.goldReadable(context)),
                    onPressed: () => _toggleMasterSample(section),
                  ),
                ValueListenableBuilder<int>(
                  valueListenable: _countInLeft,
                  builder: (context, countLeft, _) {
                    final sectionRecording = _rec.isSectionRecording && _rec.activeSection == section.index;
                    final counting = countLeft > 0;
                    return FilledButton.icon(
                      icon: HueIcon(sectionRecording ? HueIcons.stop : HueIcons.mic, size: 16, decorative: true),
                      label: Text(
                        sectionRecording
                            ? strings.practiceStopRecord
                            : counting
                                ? strings.practiceCountingIn(countLeft)
                                : strings.practiceRecord,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: sectionRecording ? AppTheme.statusReadable(context, AppStatusKind.danger) : null,
                        foregroundColor: sectionRecording ? scheme.onError : null,
                      ),
                      onPressed: counting || _rec.arming ? null : () => _toggleRecord(section),
                    );
                  },
                ),
                ValueListenableBuilder<int>(
                  valueListenable: _countInLeft,
                  builder: (context, countLeft, _) {
                    final sectionRecording = _rec.isSectionRecording && _rec.activeSection == section.index;
                    return CommonButton(
                      label: strings.practiceGrade,
                      loading: _practicingSection == section.index,
                      onPressed: recorded && _practicingSection != section.index && !sectionRecording && countLeft == 0 && !_rec.arming
                          ? () => _submitPractice(section)
                          : null,
                    );
                  },
                ),
                if (recorded && result != null)
                  OutlinedButton.icon(
                    icon: const HueIcon(HueIcons.refresh, size: 16),
                    label: Text(strings.practiceRegrade),
                    onPressed: _practicingSection == section.index ? null : () => _submitPractice(section),
                  ),
                if (result?.userMidi.isNotEmpty == true)
                  OutlinedButton.icon(
                    icon: const HueIcon(HueIcons.musicNote, size: 16),
                    label: Text(strings.practiceMidiBtn),
                    onPressed: _downloadingMidi ? null : () => _downloadPracticeMidi(result!),
                  ),
              ],
            ),
            if (_practicingSection == section.index)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ValueListenableBuilder<double?>(
                  valueListenable: _uploadProgress,
                  builder: (context, prog, _) => LinearProgressIndicator(
                    value: prog,
                    minHeight: 6,
                    color: scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ),
            if (_detail?.contourF0.isNotEmpty ?? false) ...[
              _buildSectionGuide(section),
              const SizedBox(height: 8),
            ],
            if (_rec.isSectionRecording && _rec.activeSection == section.index) ...[
            RepaintBoundary(
              child: ValueListenableBuilder<double>(
                valueListenable: _vuLevel,
                builder: (context, vu, _) => Row(
                  children: [
                    HueIcon(HueIcons.recordDot, color: AppTheme.statusReadable(context, AppStatusKind.danger), size: 12),
                    const SizedBox(width: 6),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: ((vu + 60) / 60).clamp(0.0, 1.0),
                        minHeight: 8,
                        color: scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${vu.toStringAsFixed(0)} dB', style: const TextStyle(fontSize: AppFontSize.xs)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<({double hz, String? note, int? centsDelta})?>(
              valueListenable: _livePitch,
              builder: (context, live, _) {
                final Color toneColor;
                final String msg;
                if (live == null || live.note == null) {
                  toneColor = scheme.onSurfaceVariant;
                  msg = strings.practiceLiveCoachListening;
                } else {
                  final delta = live.centsDelta;
                  if (delta != null) {
                    final absDelta = delta.abs();
                    toneColor = absDelta <= 35
                        ? AppTheme.statusReadable(context, AppStatusKind.success)
                        : absDelta <= 75
                            ? AppTheme.statusReadable(context, AppStatusKind.warning)
                            : AppTheme.statusReadable(context, AppStatusKind.danger);
                    msg = strings.practiceLiveCoachInTune(live.note!, live.hz, delta);
                  } else {
                    toneColor = AppTheme.goldReadable(context);
                    msg = strings.practiceLiveCoachNoteOnly(live.note!, live.hz);
                  }
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: toneColor.withAlpha(24),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      HueIcon(HueIcons.waves, size: 14, color: toneColor),
                      const SizedBox(width: 6),
                      Text(
                        '${strings.practiceLiveCoachLabel}: ',
                        style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant),
                      ),
                      Expanded(
                        child: Text(
                          msg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppFontSize.xs, fontWeight: FontWeight.w600, color: toneColor),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            ],
            if (recorded && _takes[section.index]?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _takes[section.index]!.length; i++)
                    ChoiceChip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      visualDensity: VisualDensity.standard,
                      label: Text(strings.practiceTakeChip(_takes[section.index]![i].no),
                          style: const TextStyle(fontSize: AppFontSize.xs)),
                      selected: (_selectedTake[section.index] ?? 0) == i,
                      onSelected: (_) => setState(() {
                        _selectedTake[section.index] = i;
                        final stored = _takeResults[section.index]?[_takes[section.index]![i].no];
                        if (stored != null) {
                          _results[section.index] = stored;
                        } else {
                          _results.remove(section.index);
                        }
                      }),
                    ),
                ],
              ),
              _buildTakeScoreRow(section),
              AudioPlayerBar(bytes: _selectedTakeRec(section.index)?.bytes),
            ] else if (recorded && !kIsWeb && _recordPaths[section.index] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  HueIcon(HueIcons.replay, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      strings.practiceReplayTake,
                      style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              AudioPlayerBar(filePath: _recordPaths[section.index]),
            ],
            if (_takePreview != null && recorded && result == null && _previewTakeMatches(section)) _buildTakePreview(section),
            if (_analyzingPreview && recorded && result == null) _buildAnalyzingRow(),
            if (recorded && result == null && _practicingSection != section.index)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(strings.practiceRecorded, style: const TextStyle(fontSize: AppFontSize.sm)),
              ),
            if (result != null) ...[
              const Divider(height: 20),
              _buildResultSummary(result, section),
              const SizedBox(height: 8),
              OverlayPitchChart(result: result),
              _buildWordScore(result, section),
              if (result.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in result.notes)
                      Tooltip(
                        message: _noteTooltip(n),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          onTap: n.refEnd > n.refStart ? () => _playRefSegment(n.refStart, n.refEnd, section) : null,
                          child: Chip(
                            backgroundColor: _verdictColor(n.verdictCode),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (n.errCents != null && (n.verdictCode == 'off' || n.verdictCode == 'octave' || n.verdictCode == 'minor'))
                                  HueIcon(n.errCents! > 0 ? HueIcons.arrowUpward : HueIcons.arrowDownward, size: 11, color: scheme.onSurfaceVariant),
                                if (n.verdictCode == 'ok' && n.vibrato) HueIcon(HueIcons.waves, size: 11, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 3),
                                Text(
                                  n.verdictCode == 'unclear' || n.errCents == null
                                      ? _verdictLabel(n.verdictCode)
                                      : '${n.errCents! > 0 ? '+' : ''}${n.errCents!.toStringAsFixed(0)}c',
                                  style: const TextStyle(fontSize: AppFontSize.xs),
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
            if (_countInSection == section.index)
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: _countInLeft,
                  builder: (context, countLeft, _) {
                    if (countLeft <= 0) return const SizedBox.shrink();
                    final digit = Text(
                      '$countLeft',
                      style: TextStyle(
                        fontFamily: AppTheme.displayFontFamily,
                        fontSize: AppFontSize.display,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.goldReadable(context),
                      ),
                    );
                    final disableAnimations = MediaQuery.of(context).disableAnimations;
                    return ColoredBox(
                      color: scheme.surface.withValues(alpha: 0.72),
                      child: Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.goldReadable(context), width: 1.4),
                          ),
                          child: disableAnimations
                              ? digit
                              : TweenAnimationBuilder<double>(
                                  key: ValueKey<int>(countLeft),
                                  tween: Tween<double>(begin: 0.86, end: 1),
                                  duration: AppMotion.fast,
                                  curve: AppMotion.emphasized,
                                  builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                                  child: digit,
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _verdictColor(String code) {
    final alpha = code == 'octave' ? 70 : 40;
    switch (practiceVerdictKind(code)) {
      case AppStatusKind.success:
        return AppTheme.statusReadable(context, AppStatusKind.success).withAlpha(alpha);
      case AppStatusKind.warning:
        return AppTheme.statusReadable(context, AppStatusKind.warning).withAlpha(alpha);
      case AppStatusKind.danger:
        return AppTheme.statusReadable(context, AppStatusKind.danger).withAlpha(alpha);
      case AppStatusKind.info:
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

  String _noteTooltip(PracticeNote n) {
    final hint = noteHintText(n.hintCodes, n.errCents, n.onsetErrMs, n.vibrato, n.hint, strings);
    if (hint.isNotEmpty) return '${_verdictLabel(n.verdictCode)}: $hint';
    return _verdictLabel(n.verdictCode);
  }

  bool _previewTakeMatches(LessonSection section) {
    final takes = _takes[section.index];
    if (takes == null || takes.isEmpty || _takePreviewNo == null) return false;
    final idx = (_selectedTake[section.index] ?? takes.length - 1).clamp(0, takes.length - 1);
    return takes[idx].no == _takePreviewNo;
  }

  Widget _buildAnalyzingRow() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text(strings.practiceAnalyzingPreview, style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildTakeScoreRow(LessonSection section) {
    final results = _takeResults[section.index];
    if (results == null || results.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final entries = results.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final best = entries.reduce((a, b) => a.value.metrics.score >= b.value.metrics.score ? a : b);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(strings.practiceCompareTakes, style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
          for (final e in entries)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              onTap: () => setState(() {
                final takes = _takes[section.index];
                if (takes != null) {
                  final idx = takes.indexWhere((t) => t.no == e.key);
                  if (idx >= 0) _selectedTake[section.index] = idx;
                }
                _results[section.index] = e.value;
              }),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.key == best.key) ...[
                      HueIcon(HueIcons.workspacePremium, size: 12, color: AppTheme.goldReadable(context)),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      'T${e.key}: ${e.value.metrics.score.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: AppFontSize.xs,
                        fontWeight: FontWeight.w600,
                        color: e.value.metrics.score >= 80
                            ? AppTheme.statusReadable(context, AppStatusKind.success)
                            : (e.value.metrics.score >= 60
                                ? AppTheme.statusReadable(context, AppStatusKind.warning)
                                : AppTheme.statusReadable(context, AppStatusKind.danger)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWordScore(PracticeResult result, LessonSection section) {
    if (section.lyrics.isEmpty) return const SizedBox.shrink();
    final fromServer = result.words.isNotEmpty;
    final words = fromServer ? serverWordScores(result.words) : wordScores(section, result.notes);
    if (words.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(strings.practiceWordScoreTitle, style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
              Text(
                strings.practiceWordTapHint,
                style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (fromServer && result.wordsAlignment.isNotEmpty)
            Text(
              strings.practiceWordApprox,
              style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 3,
            children: [
              for (final w in words)
                Tooltip(
                  message: w.verdictCode.isEmpty
                      ? strings.practiceWordMissing
                      : w.errCents == null
                          ? _verdictLabel(w.verdictCode)
                          : '${_verdictLabel(w.verdictCode)} · ${w.errCents! > 0 ? '+' : ''}${w.errCents!.toStringAsFixed(0)}c · ${w.onsetErrMs.toStringAsFixed(0)}ms${w.octaveDiff ? ' · ${strings.wordOctaveDiffHint}' : ''}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () => unawaited(_playWordRef(section, w, absolute: fromServer)),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: w.verdictCode.isEmpty
                              ? scheme.onSurfaceVariant.withAlpha(25)
                              : _verdictColor(w.verdictCode),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              w.word,
                              style: TextStyle(
                                fontSize: AppFontSize.sm,
                                color: w.verdictCode.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
                              ),
                            ),
                            if (w.octaveDiff) ...[
                              const SizedBox(width: 3),
                              HueIcon(HueIcons.waves, size: 11, color: AppTheme.goldReadable(context)),
                            ],
                            const SizedBox(width: 3),
                            HueIcon(HueIcons.playArrow, size: 11, color: scheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _playWordRef(LessonSection section, WordScore w, {required bool absolute}) async {
    final startRel = absolute ? math.max(0.0, w.start - section.start) : w.start;
    final endRel = absolute ? math.max(0.0, w.end - section.start) : w.end;
    if (endRel <= startRel) return;
    await _playRefSegment(startRel, endRel, section, leadIn: 0.05);
  }

  List<FlSpot> _guideSpots(LessonSection section) {
    final detail = _detail;
    final spots = <FlSpot>[];
    if (detail == null) return spots;
    final pts = <FlSpot>[];
    for (var i = 0; i < detail.contourTimes.length && i < detail.contourF0.length; i++) {
      final t = detail.contourTimes[i];
      final f = detail.contourF0[i];
      if (t.isFinite && f.isFinite && t >= section.start && t <= section.end && f > 0) {
        pts.add(FlSpot(t - section.start, f));
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
    final boundaries = <double>[
      for (final lt in section.lineTimes)
        if (lt.start - section.start > 0.01) lt.start - section.start,
    ];
    final palette = ChartPalette.of(context);
    var maxY = spots.isEmpty ? 1.0 : spots.map((s) => s.y).reduce(math.max);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HueIcon(HueIcons.musicNote, size: 13, color: AppTheme.goldReadable(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(strings.practiceGuideTitle, style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
          if (spots.isNotEmpty)
            RepaintBoundary(
              child: SizedBox(
                height: 110,
                child: ValueListenableBuilder<double>(
                  valueListenable: _recElapsed,
                  builder: (context, elapsed, _) {
                    final active = _rec.isSectionRecording && _rec.activeSection == section.index;
                    final maxX = math.max(1.0, section.duration);
                    final guidePos = active ? elapsed * _speed : 0.0;
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
                          if (guidePos > 0 && guidePos <= maxX)
                            VerticalLine(x: guidePos, color: scheme.primary, strokeWidth: 1.2),
                          for (final bx in boundaries)
                            VerticalLine(x: bx, color: scheme.onSurfaceVariant.withAlpha(90), strokeWidth: 0.8, dashArray: const [3, 3]),
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
            ),
          if (lines.isNotEmpty)
            ValueListenableBuilder<double>(
              valueListenable: _recElapsed,
              builder: (context, elapsed, _) {
                final active = _rec.isSectionRecording && _rec.activeSection == section.index;
                final current = active
                    ? currentLineIndex(
                        lineTimes: section.lineTimes,
                        lineCount: lines.length,
                        duration: section.duration,
                        elapsed: elapsed * _speed,
                        offset: section.start,
                      )
                    : -1;
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 0),
                          child: Text(
                            lines[i],
                            style: TextStyle(
                              fontSize: i == current ? 14 : 12,
                              height: 1.35,
                              fontWeight: i == current ? FontWeight.bold : FontWeight.w400,
                              color: i == current ? AppTheme.goldReadable(context) : scheme.onSurfaceVariant,
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
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.practiceTakePreview, style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          RepaintBoundary(
            child: SizedBox(
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
        if (m.truncated && m.uploadedSeconds != null && m.analyzedSeconds != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                HueIcon(HueIcons.contentCut, size: 12, color: AppTheme.statusReadable(context, AppStatusKind.warning)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    strings.practiceTruncatedFlag(m.analyzedSeconds!, m.uploadedSeconds!),
                    style: TextStyle(fontSize: AppFontSize.xs, color: AppTheme.statusReadable(context, AppStatusKind.warning)),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _scoreBadge(strings.practiceScoreTotal, m.score, scheme.primary),
            _scoreBadge(strings.practiceScorePitch, m.pitchScore, AppTheme.goldReadable(context)),
            _scoreBadge(strings.practiceScoreRhythm, m.rhythmScore, ChartPalette.of(context).user),
            _scoreBadge(strings.practiceScoreStability, m.stabilityScore, scheme.tertiary),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(strings.practiceAvgError(m.meanAbsCents.toStringAsFixed(0)), style: const TextStyle(fontSize: AppFontSize.sm)),
                Text(
                  result.reference == 'sample' ? strings.practiceRefSample : strings.practiceRefOriginal,
                  style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        if (m.ornament > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              strings.practiceOrnamentValue(m.ornament.toStringAsFixed(0), m.vibratoRate.toStringAsFixed(1)),
              style: TextStyle(fontSize: AppFontSize.sm, color: AppTheme.goldReadable(context)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            strings.practiceMatchedNotes(m.matchedNotes, m.missingNotes),
            style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
          ),
        ),
        if (m.referenceQuality == 'poor')
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppTheme.statusReadable(context, AppStatusKind.warning).withAlpha(30),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  HueIcon(HueIcons.info, size: 13, color: AppTheme.statusReadable(context, AppStatusKind.warning)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(strings.practiceRefPoorWarning, style: const TextStyle(fontSize: AppFontSize.xs)),
                  ),
                ],
              ),
            ),
          ),
        if (m.summaryHint.isNotEmpty || m.summaryCodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              summaryHintText(
                verdictCounts: m.verdictCounts,
                summaryCodes: m.summaryCodes,
                missingNotes: m.missingNotes,
                fallback: m.summaryHint,
                strings: strings,
              ),
              style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _scoreBadge(String label, double value, Color color) {
    return Column(
      children: [
        Text(value.toStringAsFixed(0), style: TextStyle(fontSize: AppFontSize.heading, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: AppFontSize.xs)),
      ],
    );
  }

  Widget _buildProgressCard() {
    final strings = this.strings;
    final scheme = Theme.of(context).colorScheme;
    final history = _practiceHistory();
    final serverEntries = _serverProgress;
    List<double> scores;
    List<DateTime> pointDates;
    String sourceLabel;
    final tzOffset = DateTime.now().timeZoneOffset;
    if (_serverProgressAvailable && serverEntries.isNotEmpty) {
      final es = serverEntries.take(10).toList().reversed.toList();
      scores = es.map((e) => e.score).toList();
      pointDates = es.map((e) => parsePracticeDate(e.createdAt, utcOffset: tzOffset)).whereType<DateTime>().toList();
      sourceLabel = strings.practiceServerProgress;
    } else {
      if (history.isEmpty) {
        return const SizedBox.shrink();
      }
      final es = history.take(10).toList().reversed.toList();
      scores = es.map((e) => e.score ?? 0).toList();
      pointDates = es.map((e) => e.at).toList();
      sourceLabel = strings.practiceLocalProgress;
    }
    final dayOffsets = <double>[];
    if (pointDates.length == scores.length && pointDates.isNotEmpty) {
      final base = pointDates.first;
      for (final d in pointDates) {
        dayOffsets.add(d.difference(base).inMinutes / 1440.0);
      }
    }
    final avgList = _serverProgressAvailable && serverEntries.isNotEmpty
        ? serverEntries.take(5).map((e) => e.score).toList()
        : history.take(5).map((e) => e.score ?? 0).toList();
    final avg = avgList.length >= 2 ? (avgList.reduce((a, b) => a + b) / avgList.length).toStringAsFixed(1) : null;
    final dates = <DateTime>[];
    if (_serverProgressAvailable) {
      for (final e in _allProgress) {
        final d = parsePracticeDate(e.createdAt, utcOffset: tzOffset);
        if (d != null) dates.add(d);
      }
    } else {
      for (final e in context.read<HistoryService>().entries) {
        if (e.kind == 'practice') dates.add(e.at);
      }
    }
    final stats = practiceStatsFromDates(dates, _serverToday ?? DateTime.now());
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(strings.practiceProgressTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('($sourceLabel)', style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  if (avg != null)
                    Text('${strings.practiceAvg5}: $avg', style: TextStyle(fontSize: AppFontSize.sm, color: AppTheme.statusReadable(context, AppStatusKind.success))),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        stats.streakDays > 0 ? strings.practiceStreakDays(stats.streakDays) : strings.practiceNoPracticeYet,
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: stats.streakDays > 0 ? AppTheme.goldReadable(context) : scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(strings.practicePracticeCount(stats.totalPractices), style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  Text(strings.practiceWeekLabel, style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: stats.last7Counts[i] > 0
                            ? scheme.primary.withAlpha(60 + math.min(195, stats.last7Counts[i] * 65))
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                  ),
                  if (i < 6) const SizedBox(width: 3),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: scores.length >= 2
                  ? _ProgressLineChart(scores: scores, dayOffsets: dayOffsets)
                  : Text('${strings.practiceLastScore}: ${scores.last.toStringAsFixed(1)}'),
            ),
            const SizedBox(height: 6),
            if (_serverProgressAvailable && serverEntries.isNotEmpty)
              for (final e in serverEntries.take(6))
                _buildProgressEntryRow(
                  scheme: scheme,
                  timeLabel: e.createdAt.length >= 16 ? e.createdAt.substring(0, 16) : e.createdAt,
                  title: strings.practiceHistoryPhrase(_selected?.title ?? '', e.section + 1),
                  score: e.score,
                  lessonId: e.lessonId,
                )
            else
              for (final e in history.take(6))
                _buildProgressEntryRow(
                  scheme: scheme,
                  timeLabel:
                      '${e.at.day.toString().padLeft(2, '0')}/${e.at.month.toString().padLeft(2, '0')} ${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}',
                  title: e.title,
                  score: e.score ?? 0,
                  lessonId: e.detail,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressEntryRow({
    required ColorScheme scheme,
    required String timeLabel,
    required String title,
    required double score,
    required String lessonId,
  }) {
    final canOpenLesson = lessonId.isNotEmpty && !lessonId.startsWith('scale:');
    final row = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            timeLabel,
            style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: AppFontSize.sm),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            score.toStringAsFixed(1),
            style: TextStyle(
              fontSize: AppFontSize.sm,
              color: AppTheme.statusReadable(context, AppStatusKind.success),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (canOpenLesson)
            HueIcon(HueIcons.chevronRight, size: 13, color: scheme.onSurfaceVariant.withAlpha(140)),
        ],
      ),
    );
    if (!canOpenLesson) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: () => unawaited(_openLessonById(lessonId)),
      child: row,
    );
  }
}

class _ProgressLineChart extends StatelessWidget {
  final List<double> scores;
  final List<double> dayOffsets;

  const _ProgressLineChart({required this.scores, this.dayOffsets = const []});

  @override
  Widget build(BuildContext context) {
    final useDays = dayOffsets.length == scores.length && dayOffsets.length >= 2 && dayOffsets.last > dayOffsets.first;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: true, border: Border.all(color: Theme.of(context).dividerColor)),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < scores.length; i++)
                FlSpot(useDays ? dayOffsets[i] : i.toDouble(), scores[i]),
            ],
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

AppStatusKind practiceVerdictKind(String verdict) {
  switch (verdict) {
    case 'ok':
      return AppStatusKind.success;
    case 'minor':
    case 'octave':
      return AppStatusKind.warning;
    case 'off':
      return AppStatusKind.danger;
    default:
      return AppStatusKind.info;
  }
}
