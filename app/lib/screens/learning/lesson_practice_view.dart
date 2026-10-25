import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/lesson_api.dart';
import '../../models/lesson.dart';
import '../../services/history_service.dart';
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
  List<Lesson> _lessons = [];
  Lesson? _selected;
  LessonDetail? _detail;
  bool _loadingLessons = false;
  bool _loadingDetail = false;
  String? _error;

  int? _recordingSection;
  int? _recordedSection;
  String? _recordPath;
  int? _practicingSection;
  final Map<int, PracticeResult> _results = {};
  final Map<int, bool> _looping = {};

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
    super.dispose();
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

  Future<void> _toggleRecord(LessonSection section) async {
    if (_recordingSection == section.index) {
      final p = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recordingSection = null;
        _recordedSection = section.index;
        _recordPath = p;
      });
      return;
    }
    if (_scaleRecording) {
      setState(() => _error = 'Đang thu luyện thang — hãy dừng bản thu đó trước.');
      return;
    }
    final ok = await _recorder.hasPermission();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Mic bị từ chối');
      return;
    }
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
        path: _practicePath(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không bắt đầu được ghi âm. Kiểm tra quyền microphone.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _recordingSection = section.index;
      _error = null;
    });
    final waitSeconds = section.duration + 3.0;
    Timer(Duration(seconds: waitSeconds.ceil()), () {
      if (mounted && _recordingSection == section.index) {
        _toggleRecord(section);
      }
    });
  }

  Future<void> _submitPractice(LessonSection section) async {
    final path = _recordPath;
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
      setState(() => _error = 'Đang thu câu hát — hãy dừng bản thu đó trước.');
      return;
    }
    final ok = await _recorder.hasPermission();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Mic bị từ chối');
      return;
    }
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
        path: _scalePathTmp(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không bắt đầu được ghi âm. Kiểm tra quyền microphone.');
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
                'Chưa có bài học nào. Hãy nạp dữ liệu di sản trên máy chủ (bài có file âm thanh sẽ thành bài học).',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else ...[
          DropdownButtonFormField<Lesson>(
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Chọn bài học', border: OutlineInputBorder()),
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
          _buildScaleCard(),
        ],
      ],
    );
  }

  Widget _buildScaleCard() {
    final scheme = Theme.of(context).colorScheme;
    final scale = _selectedScale;
    final dio = context.read<ServerConfig>().api.dio;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Luyện thang ngũ cung', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Nghe mẫu thang âm rồi hát theo — chấm độ bám thang (chroma).',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ScaleInfo>(
              initialValue: scale,
              decoration: const InputDecoration(labelText: 'Điệu thang', border: OutlineInputBorder()),
              items: [
                for (final s in _scales)
                  DropdownMenuItem(value: s, child: Text(s.name)),
              ],
              onChanged: (s) {
                if (s != null) {
                  setState(() {
                    _selectedScale = s;
                    _scaleResult = null;
                    _scalePath = null;
                  });
                }
              },
            ),
            if (scale != null) ...[
              const SizedBox(height: 8),
              Text('Nốt: ${scale.noteNames.join(" - ")}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              AudioPlayerBar(url: LessonApi(dio).scaleReferenceUrl(scale.id), label: 'Mẫu thang', dio: dio),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    icon: Icon(_scaleRecording ? Icons.stop : Icons.mic, size: 16),
                    label: Text(_scaleRecording ? 'Dừng thu' : 'Thu tiếng hát'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _scaleRecording ? Colors.red : null,
                    ),
                    onPressed: _toggleScaleRecord,
                  ),
                  CommonButton(
                    label: 'Chấm thang',
                    loading: _scaleBusy,
                    onPressed: _scalePath != null && !_scaleBusy ? _submitScalePractice : null,
                  ),
                ],
              ),
              if (_scaleResult != null) ...[
                const Divider(height: 20),
                Text(
                  'Độ bám thang: ${_scaleResult!.score.toStringAsFixed(0)}/100 (trong thang: ${(_scaleResult!.onScaleShare * 100).toStringAsFixed(0)}%)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in _scaleResult!.notes)
                      Chip(
                        backgroundColor: n.hit ? Colors.green.withAlpha(40) : Colors.red.withAlpha(40),
                        label: Text('${n.name} (${(n.share * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 11)),
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
                Text('Câu ${section.index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  icon: Icon((_looping[section.index] ?? false) ? Icons.stop : Icons.headphones, size: 16),
                  label: Text((_looping[section.index] ?? false) ? 'Dừng mẫu' : 'Nghe mẫu (lặp)'),
                  onPressed: () => _toggleSample(section),
                ),
                FilledButton.icon(
                  icon: Icon(_recordingSection == section.index ? Icons.stop : Icons.mic, size: 16),
                  label: Text(_recordingSection == section.index ? 'Dừng thu' : 'Thu câu này'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _recordingSection == section.index ? Colors.red : null,
                  ),
                  onPressed: () => _toggleRecord(section),
                ),
                CommonButton(
                  label: 'Chấm điểm',
                  loading: _practicingSection == section.index,
                  onPressed: recorded && _practicingSection != section.index ? () => _submitPractice(section) : null,
                ),
              ],
            ),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tiến độ gần đây', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: scores.length >= 2
                  ? _ProgressLineChart(scores: scores)
                  : Text('Điểm lần gần nhất: ${scores.last.toStringAsFixed(1)}'),
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
