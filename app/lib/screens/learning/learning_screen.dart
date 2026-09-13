import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/sing_api.dart';
import '../../models/compare_result.dart';
import '../../models/pitch_data.dart';
import '../../services/history_service.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/audio_player_bar.dart';
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
  bool _lastWasCompare = false;

  String _samplePath() {
    return '${Directory.systemTemp.path}/hue_sample.wav';
  }

  String _tmpPath() {
    return '${Directory.systemTemp.path}/hue_learn.wav';
  }

  void _log(String kind, String title, String status) {
    context.read<HistoryService>().add(
          HistoryEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), kind: kind, title: title, status: status, at: DateTime.now()),
        );
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
      _log('analyze-pitch', 'Phân tích bản thu', 'done');
      if (mounted) {
        setState(() => _result = data);
      }
    } catch (e) {
      _log('analyze-pitch', 'Phân tích bản thu', 'error');
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
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
        _log('compare', 'So sánh với bản mẫu', 'done');
        if (mounted) {
          setState(() => _compare = data);
        }
      } catch (e) {
        _log('compare', 'So sánh với bản mẫu', 'error');
        if (mounted) {
          setState(() => _error = ApiClient.describe(e));
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
      _log('compare', 'So sánh với bản mẫu', 'done');
      if (mounted) {
        setState(() => _compare = data);
      }
    } catch (e) {
      _log('compare', 'So sánh với bản mẫu', 'error');
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _comparing = false);
      }
    }
  }

  Future<void> _retry() async {
    if (_lastWasCompare) {
      await _runCompare();
    } else {
      await _analyze();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = context.watch<SessionMedia>();
    final hasSample = media.samplePath != null || media.sampleBytes != null;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: hasSample
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bản mẫu', style: Theme.of(context).textTheme.titleSmall),
                      AudioPlayerBar(
                        filePath: kIsWeb ? null : (media.samplePath ?? _samplePath()),
                        bytes: media.sampleBytes,
                        label: 'Nghe bản mẫu chuẩn trước khi hát theo',
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Chưa chọn bản mẫu. Vào màn Kho di sản, nhấn icon trường học trên một bản ghi để dùng làm bản mẫu.'),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        CommonButton(
          label: _recording ? 'Dừng thu âm' : 'Thu âm giọng hát',
          onPressed: _toggle,
        ),
        const SizedBox(height: 8),
        if (_recording)
          const Row(
            children: [
              Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
              SizedBox(width: 6),
              Text('Đang thu âm...'),
            ],
          ),
        if (_filePath != null && !kIsWeb) Text(_filePath!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        CommonButton(
          label: 'Phân tích cao độ',
          loading: _busy,
          onPressed: _filePath == null ? null : () {
            setState(() => _lastWasCompare = false);
            _analyze();
          },
        ),
        const SizedBox(height: 8),
        CommonButton(
          label: 'So sánh với bản mẫu',
          loading: _comparing,
          onPressed: _filePath == null ? null : () {
            setState(() => _lastWasCompare = true);
            _runCompare();
          },
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                  TextButton(onPressed: _retry, child: const Text('Thử lại')),
                ],
              ),
            ),
          ),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Text('Mean F0: ${_result!.meanF0} Hz - ${_result!.frames} frames'),
          PitchContourChart(data: _result!),
        ],
        if (_compare != null) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.primaryContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Điểm tổng thể: ${_compare!.metrics.score}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text('Cao độ: ${_compare!.metrics.pitchScore} · Thời gian: ${_compare!.metrics.timeScore}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Lệch cao độ trung bình: ${_compare!.metrics.meanAbsCents} cents (trung vị ${_compare!.metrics.medianCents})'),
          Text('Vào câu sớm/trễ: ${_compare!.metrics.startOffsetMs} ms'),
          Text('Khoảng cách DTW: ${_compare!.metrics.dtwDistance.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          CompareChart(
            times: _compare!.times,
            sampleF0: _compare!.sampleF0,
            warpedF0: _compare!.warpedF0,
          ),
          const SizedBox(height: 4),
          for (final n in _compare!.notes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(n.name),
              subtitle: Text('${n.start}s - ${n.end}s'),
              trailing: Text('${n.errCents} cents - ${n.verdict}'),
            ),
        ],
      ],
    );
  }
}
