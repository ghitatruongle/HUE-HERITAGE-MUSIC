import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/instrument_api.dart';
import '../../models/instrument_result.dart';
import '../../models/pitch_data.dart';
import '../../api/endpoints/sing_api.dart';
import '../../services/server_config.dart';
import '../../widgets/pitch_contour_chart.dart';
import '../../widgets/waveform_view.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _loading = false;
  String? _error;
  PitchData? _pitch;
  InstrumentResult? _instruments;
  WaveformData? _wave;
  String _source = '';

  Future<void> _pickAndAnalyze() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    await _run(file.bytes!, file.name);
  }

  Future<void> _run(Uint8List bytes, String name) async {
    final config = context.read<ServerConfig>();
    if (!config.hasServer) {
      setState(() => _error = 'Chưa cấu hình máy chủ. Vào Cài đặt để nhập địa chỉ.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _pitch = null;
      _instruments = null;
      _wave = WaveformData.fromWavBytes(bytes);
      _source = name;
    });
    try {
      final pitch = await SingApi(config.api.dio).analyzePitchBytes(bytes);
      InstrumentResult? instruments;
      try {
        instruments = await InstrumentApi(config.api.dio).detectBytes(bytes, name);
      } catch (_) {
        instruments = null;
      }
      setState(() {
        _pitch = pitch;
        _instruments = instruments;
      });
    } catch (e) {
      setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chọn bản thu để phân tích cao độ F0 và nhận diện nhạc cụ.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _pickAndAnalyze,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Chọn tệp âm thanh'),
                ),
              ],
            ),
          ),
        ),
        if (_loading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_source.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Tệp: $_source', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (_wave != null) WaveformView(data: _wave!),
        ],
        if (_pitch != null) ...[
          const SizedBox(height: 16),
          Text('Đường cao độ F0', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          PitchContourChart(data: _pitch!),
          const SizedBox(height: 8),
          Text(
            'F0 trung bình: ${_pitch!.meanF0.toStringAsFixed(1)} Hz',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (_instruments != null) ...[
          const SizedBox(height: 16),
          Text('Nhạc cụ nhận diện được', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._instruments!.segments.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.piano),
              title: Text(s.instrument),
              subtitle: Text('${s.start.toStringAsFixed(1)}s – ${s.end.toStringAsFixed(1)}s'),
              trailing: Text('${(s.confidence * 100).toStringAsFixed(0)}%'),
            ),
          ),
          if (_instruments!.segments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Không nhận diện được nhạc cụ nào.'),
            ),
        ],
      ],
    );
  }
}
