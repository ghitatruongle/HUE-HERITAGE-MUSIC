import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
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
import '../../services/download_helper.dart';
import '../../core/localization/app_strings.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';
import '../../widgets/overlay_pitch_chart.dart';

class LessonPracticeView extends StatefulWidget {
  const LessonPracticeView({super.key});

  @override
  State<LessonPracticeView> createState() => _LessonPracticeViewState();
}

class _LessonPracticeViewState extends State<LessonPracticeView> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _samplePlayer = AudioPlayer();
  final AudioPlayer _metronomePlayer = AudioPlayer();
  List<Lesson> _lessons = [];
  Lesson? _selected;
  LessonDetail? _detail;
  bool _loadingLessons = false;
  bool _loadingDetail = false;
  String? _error;
  bool _countIn = true;
  late AppStrings strings;

  int? _recordingSection;
  int? _recordedSection;
  String? _recordPath;
  final Map<int, String> _recordPaths = {};
  int? _practicingSection;
  final Map<int, PracticeResult> _results = {};
  final Map<int, bool> _looping = {};
  final Map<int, Uint8List> _recordings = {};

  List<ScaleInfo> _scales = [];
  ScaleInfo? _selectedScale;
  bool _scaleRecording = false;
  String? _scalePath;
  bool _scaleBusy = false;
  ScalePractice? _scaleResult;

  @override
  void initState() {
    super.initState();
    _loadLessons();
    _samplePlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() => _looping.updateAll((k, v) => false));
      }
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _samplePlayer.dispose();
    _metronomePlayer.dispose();
    super.dispose();
  }

  Future<AudioSource> _bytesSource(Uint8List bytes) async {
    if (kIsWeb) {
      return AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav'));
    }
    final file = File('${Directory.systemTemp.path}/hue_beep_${DateTime.now().millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(bytes);
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

  Future<void> _openLesson(Lesson lesson) async {
    setState(() {
      _selected = lesson;
      _loadingDetail = true;
      _detail = null;
      _error = null;
      _results.clear();
      _recordedSection = null;
      _recordPath = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final detail = await LessonApi(dio).detail(lesson.id);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _toggleSample(LessonSection section) async {
    final detail = _detail;
    if (detail == null) return;
    final looping = _looping[section.index] ?? false;
    try {
      if (looping) {
        await _samplePlayer.stop();
        if (mounted) setState(() => _looping[section.index] = false);
        return;
      }
      final dio = context.read<ServerConfig>().api.dio;
      var url = '${dio.options.baseUrl}/api/heritage/${detail.id}/audio';
      try {
        final res = await dio.get('/api/music/play-url', queryParameters: {'path': '/api/heritage/${detail.id}/audio'});
        final data = res.data;
        if (data is Map && data['url'] is String) {
          final signed = data['url'] as String;
          url = signed.startsWith('http') ? signed : '${dio.options.baseUrl}$signed';
        }
      } catch (_) {}
      await _samplePlayer.stop();
      await _samplePlayer.setUrl(url);
      await _samplePlayer.setClip(
        start: Duration(milliseconds: (section.start * 1000).round()),
        end: Duration(milliseconds: (section.end * 1000).round()),
      );
      await _samplePlayer.setLoopMode(LoopMode.one);
      await _samplePlayer.play();
      if (mounted) setState(() => _looping[section.index] = true);
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.describe(e));
    }
  }

  String _practicePath() {
    return kIsWeb ? 'hue_practice.wav' : '${Directory.systemTemp.path}/hue_practice.wav';
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

  Future<void> _toggleRecord(LessonSection section) async {
    if (_recordingSection == section.index) {
      final p = await _recorder.stop();
      if (!mounted) return;
      Uint8List? recorded;
      if (kIsWeb && p != null) {
        try {
          recorded = await XFile(p).readAsBytes();
        } catch (_) {}
      }
      setState(() {
        _recordingSection = null;
        _recordedSection = section.index;
        _recordPath = p;
        if (p != null) {
          _recordPaths[section.index] = p;
        }
        if (recorded != null) {
          _recordings[section.index] = recorded;
        } else if (p != null) {
          _recordings.remove(section.index);
        }
      });
      return;
    }
    if (_scaleRecording) {
      setState(() => _error = strings.practiceBusyScale);
      return;
    }
    final ok = await _recorder.hasPermission();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = strings.practiceMicDenied);
      return;
    }
    if (_countIn) {
      try {
        final bpmVal = (_detail?.bpm ?? 60).round();
        await _metronomePlayer.stop();
        await _metronomePlayer.setAudioSource(await _bytesSource(_metronomeWav(bpmVal)));
        await _metronomePlayer.play();
        await _metronomePlayer.playerStateStream.firstWhere(
          (s) => s.processingState == ProcessingState.completed,
          orElse: () => throw StateError('done'),
        );
      } catch (_) {}
      if (!mounted) return;
    }
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
        path: _practicePath(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = strings.practiceMicStartFail);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _recordingSection = section.index;
      _error = null;
    });
    final waitSeconds = section.duration + 3.0 + (_countIn ? 4 * 60 / ((_detail?.bpm ?? 60)) : 0.0);
    Timer(Duration(seconds: waitSeconds.ceil()), () {
      if (mounted && _recordingSection == section.index) {
        _toggleRecord(section);
      }
    });
  }

  Future<void> _submitPractice(LessonSection section) async {
    final path = _recordPaths[section.index];
    if (path == null || _recordedSection != section.index) return;
    final detail = _detail;
    if (detail == null) return;
    setState(() {
      _practicingSection = section.index;
      _error = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = LessonApi(dio);
      PracticeResult result;
      if (kIsWeb) {
        final bytes = await XFile(path).readAsBytes();
        result = await api.practiceBytes(detail.id, section.index, bytes);
      } else {
        result = await api.practiceFile(detail.id, section.index, path);
      }
      if (!mounted) return;
      setState(() => _results[section.index] = result);
      context.read<HistoryService>().add(
            HistoryEntry(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              kind: 'practice',
              title: '${detail.title} — Câu ${section.index + 1}',
              status: 'done',
              at: DateTime.now(),
              score: result.metrics.score,
              detail: detail.id,
            ),
          );
    } catch (e) {
      if (mounted) setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _practicingSection = null);
    }
  }

  Future<void> _downloadPracticeMidi(PracticeResult result) async {
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final url = '${dio.options.baseUrl}/api/lessons/practice-midi/${result.userMidi}';
      final name = 'luyen_tap_cau${result.sectionIndex + 1}.mid';
      if (kIsWeb) {
        triggerDownload(url, name);
        return;
      }
      var savePath = '${Directory.systemTemp.path}/$name';
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        try {
          final picked = await FilePicker.platform.saveFile(dialogTitle: 'Lưu $name', fileName: name);
          if (picked == null) return;
          savePath = picked;
        } catch (_) {}
      }
      await dio.download(url, savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${strings.practiceSaved} $savePath')));
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
    if (_scaleRecording) {
      final p = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _scaleRecording = false;
        _scalePath = p;
        _scaleResult = null;
      });
      return;
    }
    if (_recordingSection != null) {
      setState(() => _error = strings.practiceBusySection);
      return;
    }
    final ok = await _recorder.hasPermission();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = strings.practiceMicDenied);
      return;
    }
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
        path: _scalePathTmp(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = strings.practiceMicStartFail);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _scaleRecording = true;
      _error = null;
    });
    Timer(const Duration(seconds: 14), () {
      if (mounted && _scaleRecording) {
        _toggleScaleRecord();
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
      final result = await api.scalePracticeBytes(scale.id, bytes);
      if (!mounted) return;
      setState(() => _scaleResult = result);
      context.read<HistoryService>().add(
            HistoryEntry(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              kind: 'practice',
              title: 'Luyện thang ${scale.name}',
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
    final scheme = Theme.of(context).colorScheme;
    strings = context.watch<LocaleProvider>().strings;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_loadingLessons)
          const Center(child: CircularProgressIndicator())
        else if (_lessons.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                strings.practiceNoLessons,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
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
          Card(
            color: scheme.errorContainer,
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ),
        if (_loadingDetail)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_detail != null) ...[
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
            recording: _scaleRecording,
            onToggleRecord: _toggleScaleRecord,
            busy: _scaleBusy,
            onSubmit: _submitScalePractice,
            recordPath: _scalePath,
            result: _scaleResult,
          ),
        ],
      ],
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
          if (sel.modeSystem.isNotEmpty) Chip(label: Text('Điệu ${sel.modeSystem}', style: const TextStyle(fontSize: 11))),
          if (sel.bpm != null) Chip(label: Text('${sel.bpm!.toStringAsFixed(0)} BPM', style: const TextStyle(fontSize: 11))),
          if (d != null) Chip(label: Text('${d.sections.length} câu', style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildSectionCard(LessonSection section) {
    final scheme = Theme.of(context).colorScheme;
    final result = _results[section.index];
    final recorded = _recordedSection == section.index;
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
              ],
            ),
            if (section.lyrics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(section.lyrics, style: const TextStyle(fontSize: 12.5, height: 1.4)),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    child: Switch(
                      value: _countIn,
                      onChanged: (v) => setState(() => _countIn = v),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Đếm nhập ${_detail?.bpm != null ? "(${_detail!.bpm!.toStringAsFixed(0)} BPM)" : ""}',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  icon: Icon((_looping[section.index] ?? false) ? Icons.stop : Icons.headphones, size: 16),
                  label: Text((_looping[section.index] ?? false) ? strings.practiceStopSample : strings.practiceListenLoop),
                  onPressed: () => _toggleSample(section),
                ),
                FilledButton.icon(
                  icon: Icon(_recordingSection == section.index ? Icons.stop : Icons.mic, size: 16),
                  label: Text(_recordingSection == section.index ? strings.practiceStopRecord : strings.practiceRecord),
                  style: FilledButton.styleFrom(
                    backgroundColor: _recordingSection == section.index ? Colors.red : null,
                  ),
                  onPressed: () => _toggleRecord(section),
                ),
                CommonButton(
                  label: strings.practiceGrade,
                  loading: _practicingSection == section.index,
                  onPressed: recorded && _practicingSection != section.index ? () => _submitPractice(section) : null,
                ),
                if (result?.userMidi.isNotEmpty == true)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.music_note, size: 16),
                    label: Text(strings.practiceMidiBtn),
                    onPressed: () => _downloadPracticeMidi(result!),
                  ),
              ],
            ),
            if (recorded && _recordings[section.index] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.replay, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(strings.practiceReplayTake, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
              AudioPlayerBar(bytes: _recordings[section.index]),
            ] else if (recorded && !kIsWeb && _recordPath != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.replay, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(strings.practiceReplayTake, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
              AudioPlayerBar(filePath: _recordPaths[section.index]),
            ],
            if (recorded && result == null && _practicingSection != section.index)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Đã thu xong — bấm "Chấm điểm".', style: TextStyle(fontSize: 12)),
              ),
            if (result != null) ...[
              const Divider(height: 20),
              _buildResultSummary(result),
              const SizedBox(height: 8),
              OverlayPitchChart(result: result),
              if (result.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in result.notes.take(24))
                      Chip(
                        backgroundColor: n.verdict == 'Chuẩn'
                            ? Colors.green.withAlpha(40)
                            : n.verdict == 'Lệch nhẹ'
                                ? Colors.amber.withAlpha(40)
                                : Colors.red.withAlpha(40),
                        label: Text(
                          '${n.errCents > 0 ? '+' : ''}${n.errCents.toStringAsFixed(0)}c',
                          style: const TextStyle(fontSize: 11),
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

  Widget _buildResultSummary(PracticeResult result) {
    final m = result.metrics;
    return Row(
      children: [
        _scoreBadge('Tổng', m.score, Colors.deepPurple),
        const SizedBox(width: 8),
        _scoreBadge('Cao độ', m.pitchScore, const Color(0xFFD4AF37)),
        const SizedBox(width: 8),
        _scoreBadge('Nhịp', m.timeScore, Colors.lightBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Sai số TB: ${m.meanAbsCents.toStringAsFixed(0)} cents',
              style: const TextStyle(fontSize: 12)),
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
    final history = _practiceHistory();
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }
    final scores = history.take(10).map((e) => e.score ?? 0).toList().reversed.toList();
    final avg = history.length >= 2
        ? (history.take(5).map((e) => e.score ?? 0).reduce((a, b) => a + b) / (history.take(5).length)).toStringAsFixed(1)
        : null;
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
                const Spacer(),
                if (avg != null)
                  Text('${strings.practiceAvg5}: $avg', style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
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
            for (final e in history.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Text(
                      '${e.at.day.toString().padLeft(2, '0')}/${e.at.month.toString().padLeft(2, '0')} ${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white54),
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
                      style: const TextStyle(fontSize: 11.5, color: Colors.greenAccent, fontWeight: FontWeight.w600),
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
            color: const Color(0xFFD4AF37),
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
