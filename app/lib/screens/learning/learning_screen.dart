import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../api/endpoints/sing_api.dart';
import '../../models/compare_result.dart';
import '../../models/pitch_data.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/common_button.dart';
import '../../widgets/compare_chart.dart';
import '../../widgets/pitch_contour_chart.dart';

class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key});

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _busy = false;
  bool _comparing = false;
  String? _filePath;
  PitchData? _result;
  CompareResult? _compare;
  String? _error;
  double _progress = 0;

  String _samplePath() {
    return '${Directory.systemTemp.path}/hue_sample.wav';
  }

  String _tmpPath() {
    return '${Directory.systemTemp.path}/hue_learn.wav';
  }

  Future<void> _toggle() async {
    if (_recording) {
      final p = await _recorder.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _recording = false;
        _filePath = p;
      });
      if (p != null) {
        final media = context.read<SessionMedia>();
        if (kIsWeb) {
          try {
            final bytes = await XFile(p).readAsBytes();
            media.setRecording(bytes: bytes);
          } catch (_) {}
        } else {
          media.setRecording(path: p);
        }
      }
      return;
    }
    final ok = await _recorder.hasPermission();
    if (!mounted) {
      return;
    }
    if (!ok) {
      setState(() => _error = 'Mic bị từ chối');
      return;
    }
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: kIsWeb ? 'hue_learn.wav' : _tmpPath(),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.toString());
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _recording = true;
      _error = null;
      _result = null;
    });
  }

  Future<void> _analyze() async {
    final path = _filePath;
    if (path == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = SingApi(dio);
      final data = kIsWeb
          ? await api.analyzePitchBytes(
              context.read<SessionMedia>().recordingBytes!,
              onProgress: (a, b) {
                if (mounted && b > 0) {
                  setState(() => _progress = a / b);
                }
              },
            )
          : await api.analyzePitch(
              path,
              onProgress: (a, b) {
                if (mounted && b > 0) {
                  setState(() => _progress = a / b);
                }
              },
            );
      if (mounted) {
        setState(() => _result = data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    if (_recording) {
      _recorder.stop().then<void>((_) => _recorder.dispose());
    } else {
      _recorder.dispose();
    }
    super.dispose();
  }

  Future<void> _runCompare() async {
    final media = context.read<SessionMedia>();
    final dio = context.read<ServerConfig>().api.dio;
    final api = SingApi(dio);
    if (kIsWeb) {
      final sample = media.sampleBytes;
      final user = media.recordingBytes;
      if (sample == null) {
        setState(() => _error = 'Chưa có bản mẫu (sang màn Kho di sản để tải một bản)');
        return;
      }
      if (user == null) {
        setState(() => _error = 'Chưa có bản thu');
        return;
      }
      setState(() {
        _comparing = true;
        _error = null;
        _compare = null;
      });
      try {
        final data = await api.compareBytes(sample, user);
        if (mounted) {
          setState(() => _compare = data);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _error = e.toString());
        }
      } finally {
        if (mounted) {
          setState(() => _comparing = false);
        }
      }
      return;
    }
    final path = _filePath;
    if (path == null) {
      return;
    }
    final sample = media.samplePath ?? _samplePath();
    if (!File(sample).existsSync()) {
      setState(() => _error = 'Chưa có bản mẫu (sang màn Kho di sản để tải một bản)');
      return;
    }
    setState(() {
      _comparing = true;
      _error = null;
      _compare = null;
    });
    try {
      final data = await api.compare(sample, path);
      if (mounted) {
        setState(() => _compare = data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _comparing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        CommonButton(
          label: _recording ? 'Dừng' : 'Thu âm',
          onPressed: _toggle,
        ),
        const SizedBox(height: 8),
        if (_filePath != null) Text(_filePath!),
        const SizedBox(height: 8),
        CommonButton(
          label: 'Phân tích cao độ',
          loading: _busy,
          onPressed: _filePath == null ? null : _analyze,
        ),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_result != null) ...[
          Text('Mean F0: ${_result!.meanF0} Hz - ${_result!.frames} frames'),
          PitchContourChart(data: _result!),
        ],
        const SizedBox(height: 8),
        CommonButton(
          label: 'So sánh với bản mẫu',
          loading: _comparing,
          onPressed: _filePath == null ? null : _runCompare,
        ),
        if (_compare != null) ...[
          Text(
            'Điểm: ${_compare!.metrics.score}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text('Cao độ: ${_compare!.metrics.pitchScore} · Thời gian: ${_compare!.metrics.timeScore}'),
          Text('Lệch cao độ TB: ${_compare!.metrics.meanAbsCents} cents'),
          Text('Vào sớm/trễ: ${_compare!.metrics.startOffsetMs} ms'),
          CompareChart(
            times: _compare!.times,
            sampleF0: _compare!.sampleF0,
            warpedF0: _compare!.warpedF0,
          ),
          for (final n in _compare!.notes)
            ListTile(
              title: Text(n.name),
              subtitle: Text('${n.start}s - ${n.end}s'),
              trailing: Text('${n.errCents} cents - ${n.verdict}'),
            ),
        ],
      ],
    );
  }
}
